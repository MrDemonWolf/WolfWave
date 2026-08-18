/**
 * Every key must actually paint.
 *
 * The bug this exists to catch: a `render()` that throws is turned into an
 * unhandled rejection by the base class's `void this.paint(...)`, which kills
 * the Node plugin process. Stream Deck restarts it, the same key throws again,
 * and the deck sits showing its last cached image — indistinguishable, from the
 * outside, from an image the renderer rejected. Hours went into bisecting SVG
 * that was never being sent.
 */

import { afterEach, describe, expect, test } from "bun:test";
import { ACTION_CLASSES } from "../src/actions/index.js";
import { WolfWaveClient } from "../src/wolfwave/client.js";
import { initialState, type WolfWaveState } from "../src/wolfwave/state.js";

interface Painted {
  images: string[];
  titles: string[];
  states: number[];
}

/** Stand-in for the SDK's KeyAction, recording what it was told to draw. */
function fakeKey(id = "key-1") {
  const painted: Painted = { images: [], titles: [], states: [] };
  const key = {
    id,
    painted,
    isKey: () => true,
    setImage: async (image?: string) => {
      painted.images.push(image ?? "<cleared>");
    },
    setTitle: async (title?: string) => {
      painted.titles.push(title ?? "");
    },
    setState: async (state: number) => {
      painted.states.push(state);
    },
    showOk: async () => {},
    showAlert: async () => {},
  };
  return key;
}

/** Calls the protected renderer the way the base class does. */
async function render(instance: object, key: unknown, state: WolfWaveState) {
  await (
    instance as { render(k: unknown, s: WolfWaveState): Promise<void> | void }
  ).render(key, state);
}

const timers: Array<ReturnType<typeof setInterval>> = [];
afterEach(() => {
  for (const t of timers) clearInterval(t);
  timers.length = 0;
});

/** A live connection with a long track, i.e. the marquee case. */
const playing: WolfWaveState = {
  ...initialState,
  phase: "connected",
  track: "Trapped at Midnight",
  artist: "Grey Wolf",
  isPlaying: true,
  queueCount: 3,
  queuePending: 1,
};

describe("every action renders without throwing", () => {
  for (const ActionClass of ACTION_CLASSES) {
    test(ActionClass.name, async () => {
      const instance = new ActionClass(new WolfWaveClient());
      const key = fakeKey();

      // The assertion is simply that this resolves. A throw here is what took
      // the whole plugin process down on hardware.
      await render(instance, key, playing);

      const drew =
        key.painted.images.length > 0 ||
        key.painted.titles.length > 0 ||
        key.painted.states.length > 0;
      expect(drew).toBe(true);

      const scrollers = (instance as unknown as { scrollers?: Map<string, ReturnType<typeof setInterval>> })
        .scrollers;
      if (scrollers) timers.push(...scrollers.values());
    });
  }
});

describe("NowPlayingAction", () => {
  test("paints an image, not just a title", async () => {
    // Looked up by position, not by `name`: the `@action` decorator replaces
    // the class, so the constructor's `.name` is not the source name.
    const NowPlaying = ACTION_CLASSES[ACTION_CLASSES.length - 1];
    const action = new NowPlaying(new WolfWaveClient());
    const key = fakeKey();
    await render(action, key, playing);

    const scrollers = (action as unknown as { scrollers?: Map<string, ReturnType<typeof setInterval>> })
      .scrollers;
    if (scrollers) timers.push(...scrollers.values());

    expect(key.painted.images.length).toBeGreaterThan(0);
    expect(key.painted.images[0]).toContain("<svg");
  });
});

describe("willAppear wiring", () => {
  /** Drives the real subscription path rather than calling render directly. */
  function appear(instance: object, key: unknown) {
    (instance as { onWillAppear(ev: { action: unknown }): void }).onWillAppear({
      action: key,
    });
  }

  function disappear(instance: object, key: { id: string }) {
    (
      instance as { onWillDisappear(ev: { action: { id: string } }): void }
    ).onWillDisappear({ action: key });
  }

  test("a key paints as soon as it appears", async () => {
    // `onState` hands a new subscriber the current snapshot, so a key added
    // mid-session must not sit blank waiting for the next broadcast.
    const action = new ACTION_CLASSES[0](new WolfWaveClient());
    const key = fakeKey();

    appear(action, key);
    await Bun.sleep(0);

    expect(key.painted.titles.length + key.painted.images.length).toBeGreaterThan(0);
  });

  test("appearing twice without a disappear does not strand a listener", async () => {
    // Profile switches and device reconnects both deliver a second willAppear.
    // A stranded listener repaints the same key forever.
    const client = new WolfWaveClient();
    const action = new ACTION_CLASSES[0](client);
    const key = fakeKey();

    appear(action, key);
    appear(action, key);
    await Bun.sleep(0);

    const subs = (action as unknown as { subscriptions?: Map<string, unknown> }).subscriptions;
    expect(subs?.size).toBe(1);
  });

  test("a key stops painting once it disappears", async () => {
    const action = new ACTION_CLASSES[0](new WolfWaveClient());
    const key = fakeKey();

    appear(action, key);
    disappear(action, key);

    const subs = (action as unknown as { subscriptions?: Map<string, unknown> }).subscriptions;
    expect(subs?.size).toBe(0);
  });
});
