import { once } from "node:events";
import type { AddressInfo } from "node:net";
import { describe, expect, test } from "bun:test";
import WebSocket, { WebSocketServer, type RawData } from "ws";
import { WolfWaveClient } from "../src/wolfwave/client.js";
import { PROTOCOL_VERSION } from "../src/wolfwave/protocol.js";

const HEX64 = "a".repeat(64);
const settings = { port: 8765, token: HEX64 };
const EVENT_TIMEOUT_MS = 2_000;

function bounded<T>(promise: Promise<T>, label: string): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error(`Timed out waiting for ${label}`)),
      EVENT_TIMEOUT_MS,
    );
    timer.unref?.();
    promise.then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      (error: unknown) => {
        clearTimeout(timer);
        reject(error);
      },
    );
  });
}

async function loopbackServer(): Promise<{
  port: number;
  server: WebSocketServer;
}> {
  const server = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await bounded(once(server, "listening"), "loopback server to listen");
  const address = server.address() as AddressInfo;
  return { port: address.port, server };
}

async function nextConnection(server: WebSocketServer): Promise<WebSocket> {
  const [socket] = (await bounded(
    once(server, "connection"),
    "WebSocket connection",
  )) as [WebSocket];
  return socket;
}

async function nextMessage(socket: WebSocket): Promise<string> {
  const [raw] = (await bounded(
    once(socket, "message"),
    "WebSocket message",
  )) as [RawData];
  return raw.toString();
}

function nextConnectedState(
  client: WolfWaveClient,
): Promise<typeof client.currentState> {
  return bounded(
    new Promise<typeof client.currentState>((resolve) => {
      let unsubscribe = () => {};
      unsubscribe = client.onState((snapshot) => {
        if (snapshot.phase === "connected") {
          unsubscribe();
          resolve(snapshot);
        }
      });
    }),
    "welcome state",
  );
}

async function closeLoopbackServer(server: WebSocketServer): Promise<void> {
  const peerCloses = [...server.clients]
    .filter((socket) => socket.readyState !== WebSocket.CLOSED)
    .map((socket) => once(socket, "close"));
  await bounded(Promise.all(peerCloses), "WebSocket peers to close");

  const closed = bounded(once(server, "close"), "loopback server to close");
  server.close();
  await closed;
}

/** Reaches private socket state for lifecycle details with no public signal. */
type ClientInternals = {
  stopped: boolean;
  settings: unknown;
  socket: {
    readyState: number;
    send: (message: string) => void;
    removeAllListeners: () => void;
    once: (event: "error", listener: () => void) => void;
    close: () => void;
  } | null;
};

function internals(client: WolfWaveClient): ClientInternals {
  return client as unknown as ClientInternals;
}

describe("configure / stop", () => {
  test("loopback flow keeps live settings and reconnects after stop", async () => {
    const { port, server } = await loopbackServer();
    const client = new WolfWaveClient();
    const liveSettings = { port, token: HEX64 };
    let connections = 0;
    server.on("connection", () => {
      connections += 1;
    });

    try {
      const firstConnection = nextConnection(server);
      client.configure(liveSettings);
      const first = await firstConnection;
      expect(first.protocol).toBe(`wolfwave.control.${HEX64}`);

      const state = nextConnectedState(client);
      first.send(
        JSON.stringify({
          type: "welcome",
          server: "WolfWave",
          version: "1.2.3",
        }),
      );
      expect(await state).toMatchObject({
        phase: "connected",
        serverVersion: "1.2.3",
      });

      const command = nextMessage(first);
      client.configure({ ...liveSettings });
      const ack = client.sendAwaitingAck("skip");
      expect(JSON.parse(await command)).toEqual({
        type: "command",
        action: "skip",
        protocol: PROTOCOL_VERSION,
      });
      expect(connections).toBe(1);

      first.send(JSON.stringify({ type: "ack", action: "skip", ok: true }));
      await expect(ack).resolves.toEqual({
        kind: "ack",
        action: "skip",
        ok: true,
      });

      const firstClosed = bounded(once(first, "close"), "first socket to close");
      client.stop();
      await firstClosed;

      const secondConnection = nextConnection(server);
      client.configure({ ...liveSettings });
      const second = await secondConnection;
      expect(second.protocol).toBe(`wolfwave.control.${HEX64}`);
      expect(connections).toBe(2);
    } finally {
      client.stop();
      await closeLoopbackServer(server);
    }
  });

  test("invalid reconfiguration immediately revokes the old socket", () => {
    const client = new WolfWaveClient();
    const raw = internals(client);
    let closes = 0;
    let sends = 0;
    raw.stopped = false;
    raw.settings = settings;
    raw.socket = {
      readyState: 1,
      send: () => {
        sends += 1;
      },
      removeAllListeners: () => {},
      once: () => {},
      close: () => {
        closes += 1;
      },
    };

    expect(client.send("skip")).toBe(true);
    expect(sends).toBe(1);

    client.configure({ port: 8765, token: "malformed" });

    expect(closes).toBe(1);
    expect(raw.socket).toBeNull();
    expect(client.send("skip")).toBe(false);
    client.stop();
  });

  test("retiring a connecting socket keeps an error sink before close", () => {
    const client = new WolfWaveClient();
    const raw = internals(client);
    let hasErrorSink = false;
    let closeSawErrorSink = false;
    raw.socket = {
      readyState: 0,
      send: () => {},
      removeAllListeners: () => {
        hasErrorSink = false;
      },
      once: (event) => {
        if (event === "error") hasErrorSink = true;
      },
      close: () => {
        closeSawErrorSink = hasErrorSink;
      },
    };

    client.stop();

    expect(closeSawErrorSink).toBe(true);
    expect(raw.socket).toBeNull();
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
