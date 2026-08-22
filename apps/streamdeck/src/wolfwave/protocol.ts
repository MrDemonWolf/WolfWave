/**
 * Wire protocol for the WolfWave Stream Deck control channel.
 *
 * This module is the TypeScript mirror of the app-side contract documented in
 * `apps/native/docs/streamdeck-control-api.md` and implemented in
 * `Services/WebSocket/StreamDeckCommand.swift`. Keep the two in lockstep: the
 * action tokens here are the Swift enum's raw values, so renaming one is a
 * protocol change that requires bumping `PROTOCOL_VERSION` on both sides.
 *
 * Everything here is pure — no sockets, no state — so it is directly unit
 * testable and safe to import from anywhere in the plugin.
 */

/**
 * Command protocol version. Must equal `StreamDeckControl.protocolVersion` in
 * the app. On a mismatch WolfWave replies with `error: "protocol"` rather than
 * running the command, which is what drives the plugin's "update" key state.
 */
export const PROTOCOL_VERSION = 3;

/** Subprotocol prefix the app's handshake checks (`WebSocketAuthToken`). */
export const TOKEN_SUBPROTOCOL_PREFIX = "wolfwave.control.";

/** Default WebSocket port (`AppConstants.WebSocketServer.defaultPort`). */
export const DEFAULT_PORT = 8765;

// MARK: - Actions

/**
 * The v3 action set. Tokens match `StreamDeckAction`'s raw values exactly.
 *
 * v3 dropped `discord_toggle`, `music_sync_toggle`, and `cycle_theme`. All
 * three were set-once preferences, and a deck slot is worth more than a key
 * pressed twice a year.
 */
export const ACTIONS = [
  "play_pause",
  "skip",
  "hold_queue",
  "resume_queue",
  "approve_next",
  "clear_queue",
  "block_current",
  "overlay_toggle",
  "announce_song",
  "reject_current",
  "block_requester",
  "cycle_audience",
] as const;

export type WolfWaveAction = (typeof ACTIONS)[number];

/** Narrows an arbitrary string to a known action token. */
export function isAction(value: string): value is WolfWaveAction {
  return (ACTIONS as readonly string[]).includes(value);
}

// MARK: - Outbound commands

export interface CommandEnvelope {
  type: "command";
  action: WolfWaveAction;
  protocol: number;
  args?: Record<string, string>;
}

/**
 * Builds a command envelope. `args` is omitted entirely when empty — the app
 * treats a missing `args` and an empty object identically, and leaving it out
 * keeps the frames small.
 */
export function buildCommand(
  action: WolfWaveAction,
  args?: Record<string, string>,
): CommandEnvelope {
  const envelope: CommandEnvelope = {
    type: "command",
    action,
    protocol: PROTOCOL_VERSION,
  };
  if (args && Object.keys(args).length > 0) {
    envelope.args = args;
  }
  return envelope;
}

/** Serializes a command envelope for `WebSocket.send`. */
export function encodeCommand(
  action: WolfWaveAction,
  args?: Record<string, string>,
): string {
  return JSON.stringify(buildCommand(action, args));
}

// MARK: - Auth

/**
 * Builds the `Sec-WebSocket-Protocol` value for a token.
 *
 * Returns `null` for anything that isn't a 64-char hex token so a typo in the
 * Property Inspector surfaces as a clear "bad token" state instead of a silent
 * handshake rejection that looks identical to "WolfWave isn't running".
 */
export function tokenSubprotocol(token: string): string | null {
  const trimmed = token.trim();
  if (!/^[0-9a-f]{64}$/i.test(trimmed)) return null;
  return TOKEN_SUBPROTOCOL_PREFIX + trimmed;
}

/** Builds the loopback-only control WebSocket URL. */
export function socketURL(port: number): string {
  return `ws://127.0.0.1:${port}`;
}

// MARK: - Inbound frames

export interface NowPlayingData {
  track: string;
  artist: string;
  album: string;
  duration: number;
  elapsed: number;
  isPlaying: boolean;
  artworkURL: string;
}

export interface PlaybackStateData {
  isPlaying: boolean;
  track: string;
  artist: string;
  album: string;
}

export interface QueueStateData {
  count: number;
  pending: number;
  /**
   * Whether the request queue is on hold.
   *
   * Authoritative — hold is togglable from the tray, chat (`!hold`), and
   * Settings, so the hold key renders from this rather than tracking its own
   * optimistic guess.
   */
  held: boolean;
  /**
   * Who may request right now, as `RequestAudience`'s raw value. Authoritative
   * for the same reason `held` is: the audience is changeable from Settings.
   */
  audience: RequestAudience;
}

/**
 * The four request audiences, loosest to strictest. Mirrors the Swift
 * `RequestAudience` enum's raw values and, critically, its declaration order:
 * the cycle key walks this list, so a reorder here changes what the key does.
 */
export const AUDIENCES = [
  "everyone",
  "subscribers",
  "vipsAndSubs",
  "modsOnly",
] as const;

export type RequestAudience = (typeof AUDIENCES)[number];

/** Short label for a 72px key. */
export const AUDIENCE_LABELS: Record<RequestAudience, string> = {
  everyone: "ALL",
  subscribers: "SUB",
  vipsAndSubs: "VIP",
  modsOnly: "MOD",
};

/**
 * Discord IPC state. `off` = the streamer turned the integration off;
 * `disconnected` / `connecting` = it is on but Rich Presence is not showing.
 * Mirrors `DiscordRPCService.ConnectionState` raw values plus `"off"`.
 */
export type DiscordState = "off" | "connecting" | "connected" | "disconnected";

const DISCORD_STATES: readonly DiscordState[] = ["off", "connecting", "connected", "disconnected"];

/**
 * An app that predates the field omits it; fall back to what the legacy
 * boolean says so a connected Discord never decodes as "off".
 */
function discordState(value: unknown, legacy: boolean): DiscordState {
  if (DISCORD_STATES.includes(value as DiscordState)) return value as DiscordState;
  return legacy ? "connected" : "off";
}

export interface HealthData {
  music: boolean;
  twitch: boolean;
  /** Legacy boolean: enabled AND connected. */
  discord: boolean;
  /** Additive in 2.1.1; an older app omits it and it is derived from `discord`. */
  discordState: DiscordState;
  overlay: boolean;
}

export interface AckFrame {
  kind: "ack";
  action: string;
  ok: boolean;
  error?: string;
}

export type InboundFrame =
  | { kind: "welcome"; server: string; version: string }
  | { kind: "now_playing"; data: NowPlayingData }
  | { kind: "playback_state"; data: PlaybackStateData }
  | { kind: "queue_state"; data: QueueStateData }
  | { kind: "health"; data: HealthData }
  | AckFrame
  | { kind: "unknown"; type: string };

/**
 * Decodes one inbound text frame.
 *
 * Returns `null` only for frames that aren't usable JSON objects with a `type`.
 * Recognized-but-unmodelled types (`progress`, `widget_config`) come back as
 * `unknown` rather than `null` so callers can distinguish "not for us" from
 * "malformed", and so a future app-side frame type doesn't look like corruption.
 */
export function parseFrame(text: string): InboundFrame | null {
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    return null;
  }
  if (typeof raw !== "object" || raw === null) return null;

  const obj = raw as Record<string, unknown>;
  const type = obj.type;
  if (typeof type !== "string") return null;

  const data = (obj.data ?? {}) as Record<string, unknown>;

  switch (type) {
    case "welcome":
      return {
        kind: "welcome",
        server: str(obj.server),
        version: str(obj.version),
      };

    case "now_playing":
      return {
        kind: "now_playing",
        data: {
          track: str(data.track),
          artist: str(data.artist),
          album: str(data.album),
          duration: num(data.duration),
          elapsed: num(data.elapsed),
          isPlaying: bool(data.isPlaying),
          artworkURL: str(data.artworkURL),
        },
      };

    case "playback_state":
      return {
        kind: "playback_state",
        data: {
          isPlaying: bool(data.isPlaying),
          track: str(data.track),
          artist: str(data.artist),
          album: str(data.album),
        },
      };

    case "queue_state":
      return {
        kind: "queue_state",
        data: {
          count: num(data.count),
          pending: num(data.pending),
          // An older WolfWave omits `held`; false is the right read, since a
          // build without the field also can't have been put on hold by a key.
          held: bool(data.held),
          audience: audience(data.audience),
        },
      };

    case "health":
      return {
        kind: "health",
        data: {
          music: bool(data.music),
          twitch: bool(data.twitch),
          discord: bool(data.discord),
          discordState: discordState(data.discordState, bool(data.discord)),
          overlay: bool(data.overlay),
        },
      };

    case "ack": {
      const frame: AckFrame = {
        kind: "ack",
        action: str(obj.action),
        ok: bool(obj.ok),
      };
      if (typeof obj.error === "string") frame.error = obj.error;
      return frame;
    }

    default:
      return { kind: "unknown", type };
  }
}

/** True when an ack means "your plugin is too old for this WolfWave". */
export function isProtocolMismatch(frame: AckFrame): boolean {
  return !frame.ok && frame.error === "protocol";
}

// MARK: - Coercion helpers

function str(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function num(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function bool(value: unknown): boolean {
  return value === true;
}

/**
 * An older WolfWave omits `audience`, and a future one could add a case this
 * build has never heard of. Both fall back to `everyone` — the key then shows
 * the loosest state, which is the honest read of "this build cannot tell you".
 */
function audience(value: unknown): RequestAudience {
  return (AUDIENCES as readonly string[]).includes(str(value))
    ? (value as RequestAudience)
    : "everyone";
}
