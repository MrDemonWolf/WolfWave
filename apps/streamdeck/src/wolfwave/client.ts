/**
 * The plugin's single connection to WolfWave.
 *
 * One socket is shared by every key: the app broadcasts `queue_state` / `health`
 * to all connected clients, so opening a socket per action would multiply the
 * broadcast fan-out for no benefit. Actions subscribe to state changes and send
 * commands through this client.
 *
 * Reconnects with capped exponential backoff, because "WolfWave isn't running
 * yet" is the normal state when a Stream Deck boots before the Mac finishes
 * logging in.
 */

import WebSocket from "ws";
import {
  encodeCommand,
  parseFrame,
  socketURL,
  tokenSubprotocol,
  type AckFrame,
  type WolfWaveAction,
} from "./protocol.js";
import {
  initialState,
  reduce,
  withPhase,
  type WolfWaveState,
} from "./state.js";

export interface ClientSettings {
  port: number;
  token: string;
}

export interface ClientEvents {
  /** Fired whenever the folded state actually changes. */
  onState: (state: WolfWaveState) => void;
  /** Fired for every ack, so the originating key can flash ok/alert. */
  onAck: (ack: AckFrame) => void;
}

const RECONNECT_BASE_MS = 1_000;
const RECONNECT_MAX_MS = 30_000;

/**
 * How long a key waits for its ack before giving up and showing an alert.
 * Generous: `play_pause` and `skip` cross an Apple Event round trip, which is
 * slow when Music.app is busy.
 */
const ACK_TIMEOUT_MS = 5_000;

interface PendingAck {
  resolve: (ack: AckFrame | null) => void;
  timer: ReturnType<typeof setTimeout>;
}

export class WolfWaveClient {
  private socket: WebSocket | null = null;
  private settings: ClientSettings | null = null;
  private state: WolfWaveState = initialState;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private attempt = 0;
  /** Set while `stop()` is in effect so a close event doesn't reconnect. */
  private stopped = true;

  private readonly stateListeners = new Set<(s: WolfWaveState) => void>();
  private readonly ackListeners = new Set<(a: AckFrame) => void>();
  /**
   * Keys awaiting an ack, bucketed by action token and resolved FIFO.
   *
   * The app's ack carries the action but no correlation id, so two keys bound to
   * the same action are matched in press order. That's the best available
   * correlation without a protocol change, and it's correct for the common case
   * of one key per action.
   */
  private readonly pendingAcks = new Map<string, PendingAck[]>();

  // MARK: - Public API

  get currentState(): WolfWaveState {
    return this.state;
  }

  onState(listener: (state: WolfWaveState) => void): () => void {
    this.stateListeners.add(listener);
    // Hand the new subscriber the current snapshot so a key added mid-session
    // renders correctly instead of waiting for the next broadcast.
    listener(this.state);
    return () => this.stateListeners.delete(listener);
  }

  onAck(listener: (ack: AckFrame) => void): () => void {
    this.ackListeners.add(listener);
    return () => this.ackListeners.delete(listener);
  }

  /**
   * Points the client at a WolfWave install and connects.
   *
   * Safe to call repeatedly — settings that haven't changed are a no-op, so the
   * Property Inspector can push on every keystroke without thrashing the socket.
   *
   * The `!this.stopped` term is load-bearing: clearing the token calls `stop()`
   * but leaves the last settings cached, so re-entering the *same* token would
   * otherwise match the cache, return early, and never reconnect — leaving every
   * key on "Offline" until Stream Deck restarts.
   */
  configure(settings: ClientSettings): void {
    if (
      !this.stopped &&
      this.settings &&
      this.settings.port === settings.port &&
      this.settings.token === settings.token
    ) {
      return;
    }
    this.settings = settings;
    this.attempt = 0;
    this.stopped = false;
    this.reconnect(0);
  }

  /** Closes the socket and stops reconnecting. */
  stop(): void {
    this.stopped = true;
    this.clearTimer();
    this.closeSocket();
    this.flushPending();
    this.setState(withPhase(this.state, "disconnected"));
  }

  /**
   * Sends a command. Returns false when there is no open socket, so the caller
   * can show an alert instead of silently dropping the key press.
   */
  send(action: WolfWaveAction, args?: Record<string, string>): boolean {
    if (this.socket?.readyState !== WebSocket.OPEN) return false;
    this.socket.send(encodeCommand(action, args));
    return true;
  }

  /**
   * Sends a command and resolves with its ack.
   *
   * Resolves `null` when there's no open socket, or when no ack arrives within
   * {@link ACK_TIMEOUT_MS} — both mean "show an alert", so the caller doesn't
   * need to tell them apart.
   */
  sendAwaitingAck(
    action: WolfWaveAction,
    args?: Record<string, string>,
  ): Promise<AckFrame | null> {
    if (!this.send(action, args)) return Promise.resolve(null);

    return new Promise<AckFrame | null>((resolve) => {
      const queue = this.pendingAcks.get(action) ?? [];
      const pending: PendingAck = {
        resolve,
        timer: setTimeout(() => {
          this.removePending(action, pending);
          resolve(null);
        }, ACK_TIMEOUT_MS),
      };
      pending.timer.unref?.();
      queue.push(pending);
      this.pendingAcks.set(action, queue);
    });
  }

  // MARK: - Connection lifecycle

  private connect(): void {
    const settings = this.settings;
    if (!settings || this.stopped) return;

    const subprotocol = tokenSubprotocol(settings.token);
    if (!subprotocol) {
      // A malformed token can never succeed, so don't burn a reconnect loop on
      // it — surface it and wait for the Property Inspector to fix it.
      this.setState(withPhase(this.state, "unauthorized"));
      return;
    }

    this.closeSocket();

    const socket = new WebSocket(socketURL(settings.port), [
      subprotocol,
    ]);
    this.socket = socket;

    socket.on("message", (raw: WebSocket.RawData) => {
      this.handleMessage(raw.toString());
    });

    socket.on("open", () => {
      this.attempt = 0;
    });

    socket.on("close", () => {
      if (socket !== this.socket) return;
      this.socket = null;
      this.flushPending();
      this.setState(withPhase(this.state, "disconnected"));
      this.scheduleReconnect();
    });

    socket.on("error", () => {
      // `ws` always follows an error with a close, which is where the reconnect
      // is scheduled. Handling it here too would double-schedule.
    });
  }

  private handleMessage(text: string): void {
    const frame = parseFrame(text);
    if (!frame) return;

    if (frame.kind === "ack") {
      this.resolvePending(frame);
      for (const listener of this.ackListeners) listener(frame);
    }

    this.setState(reduce(this.state, frame));
  }

  private resolvePending(ack: AckFrame): void {
    const queue = this.pendingAcks.get(ack.action);
    const pending = queue?.shift();
    if (!pending) return;
    if (queue && queue.length === 0) this.pendingAcks.delete(ack.action);
    clearTimeout(pending.timer);
    pending.resolve(ack);
  }

  private removePending(action: string, pending: PendingAck): void {
    const queue = this.pendingAcks.get(action);
    if (!queue) return;
    const index = queue.indexOf(pending);
    if (index >= 0) queue.splice(index, 1);
    if (queue.length === 0) this.pendingAcks.delete(action);
  }

  /**
   * Fails every in-flight ack wait. Called when the socket drops so keys show
   * an alert immediately instead of sitting until their individual timeouts.
   */
  private flushPending(): void {
    for (const queue of this.pendingAcks.values()) {
      for (const pending of queue) {
        clearTimeout(pending.timer);
        pending.resolve(null);
      }
    }
    this.pendingAcks.clear();
  }

  private scheduleReconnect(): void {
    if (this.stopped) return;
    const delay = Math.min(
      RECONNECT_BASE_MS * 2 ** this.attempt,
      RECONNECT_MAX_MS,
    );
    this.attempt += 1;
    this.reconnect(delay);
  }

  private reconnect(delayMs: number): void {
    this.clearTimer();
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.connect();
    }, delayMs);
    // Don't hold the plugin process open purely to retry a socket.
    this.reconnectTimer.unref?.();
  }

  private clearTimer(): void {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
  }

  private closeSocket(): void {
    if (!this.socket) return;
    const socket = this.socket;
    this.socket = null;
    // Drop handlers first: otherwise this deliberate close fires the `close`
    // handler and schedules a reconnect we're about to supersede.
    socket.removeAllListeners();
    socket.close();
  }

  private setState(next: WolfWaveState): void {
    if (next === this.state) return;
    this.state = next;
    for (const listener of this.stateListeners) listener(next);
  }
}
