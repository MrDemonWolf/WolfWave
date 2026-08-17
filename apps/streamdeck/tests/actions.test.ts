import { afterEach, describe, expect, test } from "bun:test";
import { setClock } from "../src/clock.js";
import { ClearQueueAction, QueueHoldAction } from "../src/actions/index.js";
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

// MARK: - Hold to confirm

/** Minimal stand-in for the SDK's KeyAction, recording what the key was told. */
function fakeKey(id = "key-1") {
  const feedback: string[] = [];
  return {
    id,
    feedback,
    isKey: () => true,
    showOk: async () => {
      feedback.push("ok");
    },
    showAlert: async () => {
      feedback.push("alert");
    },
  };
}

/** Records commands instead of opening a socket. */
function recordingClient(): WolfWaveClient & { sent: string[] } {
  const client = new WolfWaveClient() as WolfWaveClient & { sent: string[] };
  client.sent = [];
  (client as unknown as { sendAwaitingAck: unknown }).sendAwaitingAck = async (
    action: string,
  ) => {
    client.sent.push(action);
    return { type: "ack", action, ok: true };
  };
  return client;
}

describe("ClearQueueAction hold-to-confirm", () => {
  afterEach(() => setClock());

  test("a tap sends nothing and alerts", async () => {
    let time = 1_000;
    setClock(() => time);
    const client = recordingClient();
    const key = new ClearQueueAction(client);
    const target = fakeKey();

    await key.onKeyDown({ action: target });
    time += 120; // a normal press
    await key.onKeyUp({ action: target });

    expect(client.sent).toEqual([]);
    expect(target.feedback).toEqual(["alert"]);
  });

  test("a hold past the threshold sends the command", async () => {
    let time = 1_000;
    setClock(() => time);
    const client = recordingClient();
    const key = new ClearQueueAction(client);
    const target = fakeKey();

    await key.onKeyDown({ action: target });
    time += 900;
    await key.onKeyUp({ action: target });

    expect(client.sent).toEqual(["clear_queue"]);
    expect(target.feedback).toEqual(["ok"]);
  });

  test("key-down alone never fires, however long it is held", async () => {
    let time = 1_000;
    setClock(() => time);
    const client = recordingClient();
    const key = new ClearQueueAction(client);

    await key.onKeyDown({ action: fakeKey() });
    time += 5_000;

    expect(client.sent).toEqual([]);
  });

  test("a key-up with no matching key-down is ignored", async () => {
    const client = recordingClient();
    const key = new ClearQueueAction(client);

    // Stream Deck can deliver a key-up for a press that started before the
    // plugin was listening (profile switch, plugin restart mid-press).
    await key.onKeyUp({ action: fakeKey() });

    expect(client.sent).toEqual([]);
  });

  test("two keys bound to the same action time independently", async () => {
    let time = 1_000;
    setClock(() => time);
    const client = recordingClient();
    const key = new ClearQueueAction(client);
    const first = fakeKey("key-1");
    const second = fakeKey("key-2");

    await key.onKeyDown({ action: first });
    time += 500;
    await key.onKeyDown({ action: second });
    time += 400; // first held 900ms, second only 400ms
    await key.onKeyUp({ action: first });
    await key.onKeyUp({ action: second });

    expect(client.sent).toEqual(["clear_queue"]);
    expect(first.feedback).toEqual(["ok"]);
    expect(second.feedback).toEqual(["alert"]);
  });
});

describe("keys without a hold", () => {
  test("fire on press, not on release", async () => {
    const client = recordingClient();
    const key = new QueueHoldAction(client);
    const target = fakeKey();

    await key.onKeyDown({ action: target });
    expect(client.sent).toEqual(["hold_queue"]);

    await key.onKeyUp({ action: target });
    expect(client.sent).toEqual(["hold_queue"]);
  });
});
