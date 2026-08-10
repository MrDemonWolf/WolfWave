/**
 * Shared behaviour for every WolfWave key.
 *
 * A key does two things: send a command on press and reflect live state. Both
 * are the same for all eleven v1 actions apart from which token they send and
 * what they render, so subclasses override only that.
 */

import {
  SingletonAction,
  type KeyAction,
  type WillAppearEvent,
  type WillDisappearEvent,
} from "@elgato/streamdeck";
import type { WolfWaveClient } from "../wolfwave/client.js";
import type { WolfWaveAction } from "../wolfwave/protocol.js";
import type { WolfWaveState } from "../wolfwave/state.js";

/** Key state indices; must match the `States` array order in `manifest.json`. */
export const KeyState = {
  /** Default / off / paused. */
  primary: 0,
  /** Active / on / playing. */
  secondary: 1,
} as const;

/**
 * Not generic over a settings type: connection settings are global (one
 * WolfWave install serves every key), so no action carries per-key settings.
 */
export abstract class WolfWaveKeyAction extends SingletonAction {
  /** Unsubscribe handles for visible keys, so disappearing keys stop rendering. */
  private readonly subscriptions = new Map<string, () => void>();

  constructor(protected readonly client: WolfWaveClient) {
    super();
  }

  /**
   * The command this key sends on press. Return `null` to make the key
   * display-only (the status key does this).
   */
  protected abstract commandFor(state: WolfWaveState): WolfWaveAction | null;

  /**
   * Renders the key for the current state. The base class handles the
   * disconnected and outdated cases before this is called, so implementations
   * only deal with a live connection.
   */
  protected abstract render(
    action: KeyAction,
    state: WolfWaveState,
  ): Promise<void> | void;

  override onWillAppear(ev: WillAppearEvent): void {
    const action = ev.action;
    if (!action.isKey()) return;

    // willAppear can fire again for the same action without an intervening
    // willDisappear — switching back to a profile, a device reconnecting, or a
    // missed willDisappear all do it. Overwriting the handle would strand the
    // previous listener in the client for the life of the process, and every
    // stranded one repaints the same key on every state change.
    this.subscriptions.get(action.id)?.();

    const unsubscribe = this.client.onState((state) => {
      void this.paint(action, state);
    });
    this.subscriptions.set(action.id, unsubscribe);
  }

  override onWillDisappear(ev: WillDisappearEvent): void {
    const unsubscribe = this.subscriptions.get(ev.action.id);
    if (!unsubscribe) return;
    unsubscribe();
    this.subscriptions.delete(ev.action.id);
  }

  override async onKeyDown(ev: { action: unknown }): Promise<void> {
    const action = ev.action as KeyAction;
    if (typeof action?.isKey !== "function" || !action.isKey()) return;

    const command = this.commandFor(this.client.currentState);
    if (!command) return;

    const ack = await this.client.sendAwaitingAck(command);
    if (ack?.ok) {
      await action.showOk();
    } else {
      await action.showAlert();
    }
  }

  // MARK: - Private helpers

  /**
   * Paints connection-level states centrally so no subclass can forget one —
   * a key that silently kept rendering its last-known title after WolfWave quit
   * would be actively misleading on stream.
   */
  private async paint(action: KeyAction, state: WolfWaveState): Promise<void> {
    switch (state.phase) {
      case "disconnected":
        await action.setTitle("Offline");
        await action.setState(KeyState.primary);
        return;
      case "unauthorized":
        await action.setTitle("Token?");
        await action.setState(KeyState.primary);
        return;
      case "outdated":
        await action.setTitle("Update");
        await action.setState(KeyState.primary);
        return;
      case "connected":
        await this.render(action, state);
    }
  }
}
