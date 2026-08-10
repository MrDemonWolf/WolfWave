import { describe, expect, test } from "bun:test";
import type { InboundFrame } from "../src/wolfwave/protocol.js";
import {
  initialState,
  reduce,
  withPhase,
  type WolfWaveState,
} from "../src/wolfwave/state.js";

const connected: WolfWaveState = { ...initialState, phase: "connected" };

describe("reduce", () => {
  test("welcome marks the connection live and records the version", () => {
    const next = reduce(initialState, {
      kind: "welcome",
      server: "WolfWave",
      version: "2.1.0",
    });
    expect(next.phase).toBe("connected");
    expect(next.serverVersion).toBe("2.1.0");
  });

  test("now_playing folds track metadata", () => {
    const next = reduce(connected, {
      kind: "now_playing",
      data: {
        track: "Howl",
        artist: "Grey Wolf",
        album: "Moonlit",
        duration: 210,
        elapsed: 0,
        isPlaying: true,
        artworkURL: "art",
      },
    });
    expect(next).toMatchObject({
      track: "Howl",
      artist: "Grey Wolf",
      album: "Moonlit",
      isPlaying: true,
      artworkURL: "art",
    });
  });

  test("playback_state flips isPlaying without touching artwork", () => {
    const playing = reduce(connected, {
      kind: "now_playing",
      data: {
        track: "Howl",
        artist: "Grey Wolf",
        album: "Moonlit",
        duration: 210,
        elapsed: 0,
        isPlaying: true,
        artworkURL: "art",
      },
    });
    const paused = reduce(playing, {
      kind: "playback_state",
      data: {
        isPlaying: false,
        track: "Howl",
        artist: "Grey Wolf",
        album: "Moonlit",
      },
    });
    expect(paused.isPlaying).toBe(false);
    expect(paused.artworkURL).toBe("art");
  });

  test("queue_state folds counts and hold state", () => {
    const next = reduce(connected, {
      kind: "queue_state",
      data: { count: 3, pending: 1, held: true },
    });
    expect(next.queueCount).toBe(3);
    expect(next.queuePending).toBe(1);
    expect(next.queueHeld).toBe(true);
  });

  test("hold released elsewhere flips queueHeld back", () => {
    // The app rebroadcasts queue_state on every hold change, including ones made
    // from the tray, chat, or Settings — so the key follows without a press.
    const held = reduce(connected, {
      kind: "queue_state",
      data: { count: 3, pending: 0, held: true },
    });
    const released = reduce(held, {
      kind: "queue_state",
      data: { count: 3, pending: 0, held: false },
    });
    expect(released.queueHeld).toBe(false);
  });

  test("health folds every flag", () => {
    const next = reduce(connected, {
      kind: "health",
      data: { music: true, twitch: false, discord: true, overlay: false },
    });
    expect(next.health).toEqual({
      music: true,
      twitch: false,
      discord: true,
      overlay: false,
    });
  });

  test("a protocol ack moves the plugin to outdated", () => {
    const next = reduce(connected, {
      kind: "ack",
      action: "skip",
      ok: false,
      error: "protocol",
    });
    expect(next.phase).toBe("outdated");
  });

  test("other acks leave state untouched", () => {
    for (const frame of [
      { kind: "ack", action: "skip", ok: true },
      { kind: "ack", action: "approve_next", ok: false, error: "empty" },
    ] satisfies InboundFrame[]) {
      expect(reduce(connected, frame)).toBe(connected);
    }
  });
});

describe("reference stability", () => {
  test("an unchanged fold returns the same object", () => {
    // This is what stops a per-second `progress`/`now_playing` re-emit from
    // repainting every visible key.
    const state = reduce(connected, {
      kind: "queue_state",
      data: { count: 2, pending: 0, held: false },
    });
    const again = reduce(state, {
      kind: "queue_state",
      data: { count: 2, pending: 0, held: false },
    });
    expect(again).toBe(state);
  });

  test("unknown frames are inert", () => {
    expect(reduce(connected, { kind: "unknown", type: "progress" })).toBe(
      connected,
    );
  });

  test("an unchanged health payload does not allocate", () => {
    const state = reduce(connected, {
      kind: "health",
      data: { music: true, twitch: true, discord: false, overlay: true },
    });
    const again = reduce(state, {
      kind: "health",
      data: { music: true, twitch: true, discord: false, overlay: true },
    });
    expect(again).toBe(state);
  });
});

describe("withPhase", () => {
  test("is a no-op for the current phase", () => {
    expect(withPhase(connected, "connected")).toBe(connected);
  });

  test("dropping to disconnected clears the stale snapshot", () => {
    const live = reduce(connected, {
      kind: "now_playing",
      data: {
        track: "Howl",
        artist: "Grey Wolf",
        album: "Moonlit",
        duration: 1,
        elapsed: 0,
        isPlaying: true,
        artworkURL: "art",
      },
    });
    const dropped = withPhase(live, "disconnected");
    // Keeping "Howl" on a key after WolfWave quits would read as live.
    expect(dropped.track).toBe("");
    expect(dropped.isPlaying).toBe(false);
    expect(dropped.phase).toBe("disconnected");
  });

  test("unauthorized also clears", () => {
    expect(withPhase(connected, "unauthorized")).toMatchObject({
      phase: "unauthorized",
      track: "",
    });
  });

  test("outdated preserves the snapshot", () => {
    // The socket is still live here — only the command channel is unusable.
    const live = { ...connected, track: "Howl" };
    expect(withPhase(live, "outdated")).toMatchObject({
      phase: "outdated",
      track: "Howl",
    });
  });
});
