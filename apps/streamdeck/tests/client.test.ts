import { describe, expect, test } from "bun:test";
import { WolfWaveClient } from "../src/wolfwave/client.js";

const HEX64 = "a".repeat(64);
const settings = { port: 8765, token: HEX64 };

/** Reaches the private fields the reconnect guard turns on. */
function internals(client: WolfWaveClient): {
  stopped: boolean;
  settings: unknown;
} {
  return client as unknown as { stopped: boolean; settings: unknown };
}

describe("configure / stop", () => {
  test("re-configuring with identical settings after stop() reconnects", () => {
    // The regression: stop() leaves the last settings cached, so an unchanged
    // configure() used to match the cache and return early — every key stuck on
    // "Offline" until Stream Deck restarted. Clearing the token in the Property
    // Inspector and pasting the same one back hits exactly this path.
    const client = new WolfWaveClient();
    client.configure(settings);
    client.stop();
    expect(internals(client).stopped).toBe(true);

    client.configure({ ...settings });
    expect(internals(client).stopped).toBe(false);

    client.stop();
  });

  test("re-configuring with identical settings while live is a no-op", () => {
    // The Property Inspector pushes on every keystroke; unchanged settings must
    // not thrash the socket.
    const client = new WolfWaveClient();
    client.configure(settings);
    const before = internals(client).settings;

    client.configure({ ...settings });
    expect(internals(client).settings).toBe(before);

    client.stop();
  });

  test("stop() leaves the client disconnected", () => {
    const client = new WolfWaveClient();
    client.configure(settings);
    client.stop();
    expect(client.currentState.phase).toBe("disconnected");
  });

  test("send() reports failure when there is no open socket", () => {
    const client = new WolfWaveClient();
    expect(client.send("skip")).toBe(false);
    client.stop();
  });

  test("sendAwaitingAck resolves null with no socket", async () => {
    const client = new WolfWaveClient();
    await expect(client.sendAwaitingAck("skip")).resolves.toBeNull();
    client.stop();
  });

  test("a new subscriber immediately receives the current snapshot", () => {
    // Keys added mid-session must render now, not on the next broadcast.
    const client = new WolfWaveClient();
    let seen = 0;
    const unsubscribe = client.onState(() => {
      seen += 1;
    });
    expect(seen).toBe(1);
    unsubscribe();
    client.stop();
  });
});
