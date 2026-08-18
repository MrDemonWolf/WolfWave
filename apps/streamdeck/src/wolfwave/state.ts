/**
 * The plugin's view of WolfWave, folded from inbound frames.
 *
 * Kept as a pure reducer so key rendering is a function of state and every
 * transition is unit testable without a socket. The client owns an instance and
 * re-renders keys whenever `reduce` returns a changed object.
 */

import type {
  AckFrame,
  HealthData,
  InboundFrame,
  RequestAudience,
} from "./protocol.js";
import { isProtocolMismatch } from "./protocol.js";

/** How the plugin should render keys right now. */
export type ConnectionPhase =
  /** No socket, or actively retrying. Keys show the disconnected state. */
  | "disconnected"
  /** Socket open and authenticated. */
  | "connected"
  /** Token missing or malformed — retrying will not help. */
  | "unauthorized"
  /** WolfWave rejected our protocol version. Keys show the update state. */
  | "outdated";

export interface WolfWaveState {
  phase: ConnectionPhase;
  /** App version from the `welcome` frame, empty until connected. */
  serverVersion: string;
  track: string;
  artist: string;
  album: string;
  isPlaying: boolean;
  artworkURL: string;
  queueCount: number;
  queuePending: number;
  /** Authoritative hold state from `queue_state`, not a local guess. */
  queueHeld: boolean;
  /** Who may request right now. Authoritative, same as `queueHeld`. */
  requestAudience: RequestAudience;
  health: HealthData;
}

export const initialState: WolfWaveState = {
  phase: "disconnected",
  serverVersion: "",
  track: "",
  artist: "",
  album: "",
  isPlaying: false,
  artworkURL: "",
  queueCount: 0,
  queuePending: 0,
  queueHeld: false,
  requestAudience: "everyone",
  health: { music: false, twitch: false, discord: false, overlay: false },
};

/**
 * Folds an inbound frame into state.
 *
 * Returns the *same object reference* when nothing changed, so callers can use
 * an identity check to skip a key re-render. That matters: `progress` frames
 * arrive on a timer while a track plays, and none of them change key state.
 */
export function reduce(
  state: WolfWaveState,
  frame: InboundFrame,
): WolfWaveState {
  switch (frame.kind) {
    case "welcome":
      return changed(state, {
        phase: "connected",
        serverVersion: frame.version,
      });

    case "now_playing":
      return changed(state, {
        track: frame.data.track,
        artist: frame.data.artist,
        album: frame.data.album,
        isPlaying: frame.data.isPlaying,
        artworkURL: frame.data.artworkURL,
      });

    case "playback_state":
      return changed(state, {
        track: frame.data.track,
        artist: frame.data.artist,
        album: frame.data.album,
        isPlaying: frame.data.isPlaying,
      });

    case "queue_state":
      return changed(state, {
        queueCount: frame.data.count,
        queuePending: frame.data.pending,
        queueHeld: frame.data.held,
        requestAudience: frame.data.audience,
      });

    case "health":
      return healthChanged(state, frame.data)
        ? { ...state, health: frame.data }
        : state;

    case "ack":
      // A protocol rejection is the one ack that changes how keys render; every
      // other outcome is per-key feedback the action handles itself.
      return isProtocolMismatch(frame)
        ? changed(state, { phase: "outdated" })
        : state;

    case "unknown":
      return state;
  }
}

/** Applies a socket-level transition that no frame carries. */
export function withPhase(
  state: WolfWaveState,
  phase: ConnectionPhase,
): WolfWaveState {
  if (state.phase === phase) return state;
  // Dropping the connection invalidates the snapshot: keeping the last track on
  // screen after WolfWave quits would show stale info as if it were live.
  if (phase === "disconnected" || phase === "unauthorized") {
    return { ...initialState, phase };
  }
  return { ...state, phase };
}

// MARK: - Private helpers

function changed(
  state: WolfWaveState,
  patch: Partial<WolfWaveState>,
): WolfWaveState {
  for (const [key, value] of Object.entries(patch)) {
    if (state[key as keyof WolfWaveState] !== value) {
      return { ...state, ...patch };
    }
  }
  return state;
}

function healthChanged(state: WolfWaveState, next: HealthData): boolean {
  const current = state.health;
  return (
    current.music !== next.music ||
    current.twitch !== next.twitch ||
    current.discord !== next.discord ||
    current.overlay !== next.overlay
  );
}

/** Re-exported for tests that assert on ack handling. */
export type { AckFrame };
