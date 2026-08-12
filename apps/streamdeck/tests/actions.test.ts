import { describe, expect, test } from "bun:test";
import { QueueHoldAction, StatusAction } from "../src/actions/index.js";
import { WolfWaveClient } from "../src/wolfwave/client.js";
import { initialState, type WolfWaveState } from "../src/wolfwave/state.js";

/** Reaches the protected command selector without exercising a real key. */
function commandFor(
  instance: object,
  state: WolfWaveState,
): string | null {
  return (
    instance as { commandFor(s: WolfWaveState): string | null }
  ).commandFor(state);
}

const connected: WolfWaveState = { ...initialState, phase: "connected" };

describe("QueueHoldAction", () => {
  const key = new QueueHoldAction(new WolfWaveClient());

  test("resumes when the queue is held", () => {
    expect(commandFor(key, { ...connected, queueHeld: true })).toBe(
      "resume_queue",
    );
  });

  test("is stateless across presses", () => {
    // The regression this guards: an earlier version tracked its own optimistic
    // toggle, so two presses with hold released elsewhere sent hold twice.
    expect(commandFor(key, { ...connected, queueHeld: false })).toBe(
      "hold_queue",
    );
    expect(commandFor(key, { ...connected, queueHeld: false })).toBe(
      "hold_queue",
    );
  });
});

describe("StatusAction", () => {
  test("sends nothing — it is display only", () => {
    const key = new StatusAction(new WolfWaveClient());
    expect(commandFor(key, connected)).toBeNull();
  });
});
