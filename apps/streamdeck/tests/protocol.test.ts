import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import {
  ACTIONS,
  buildCommand,
  DEFAULT_PORT,
  encodeCommand,
  isAction,
  isProtocolMismatch,
  parseFrame,
  PROTOCOL_VERSION,
  socketURL,
  TOKEN_SUBPROTOCOL_PREFIX,
  tokenSubprotocol,
  type AckFrame,
} from "../src/wolfwave/protocol.js";

const HEX64 = "a".repeat(64);

function requiredMatch(source: string, pattern: RegExp, label: string): string {
  const value = pattern.exec(source)?.[1];
  if (value === undefined) {
    throw new Error("Could not read " + label + " from Swift source");
  }
  return value;
}

const SWIFT_COMMAND_SOURCE = readFileSync(
  new URL(
    "../../native/WolfWave/Services/WebSocket/StreamDeckCommand.swift",
    import.meta.url,
  ),
  "utf8",
);
const SWIFT_CONSTANTS_SOURCE = readFileSync(
  new URL("../../native/WolfWave/Core/AppConstants.swift", import.meta.url),
  "utf8",
);
const SWIFT_AUTH_SOURCE = readFileSync(
  new URL(
    "../../native/WolfWave/Services/WebSocket/WebSocketAuthToken.swift",
    import.meta.url,
  ),
  "utf8",
);

describe("native control contract", () => {
  test("matches Swift actions, version, port, and auth prefix", () => {
    const actionBody = requiredMatch(
      SWIFT_COMMAND_SOURCE,
      /enum StreamDeckAction[^\{]*\{([\s\S]*?)\n\}/,
      "StreamDeckAction",
    );
    const swiftActions = [
      ...actionBody.matchAll(/^\s*case\s+(\w+)(?:\s*=\s*"([^"]+)")?/gm),
    ].map(([, caseName, rawValue]) => rawValue ?? caseName);
    const swiftProtocolVersion = Number(
      requiredMatch(
        SWIFT_COMMAND_SOURCE,
        /static let protocolVersion\s*=\s*(\d+)/,
        "StreamDeckControl.protocolVersion",
      ),
    );
    const swiftDefaultPort = Number(
      requiredMatch(
        SWIFT_CONSTANTS_SOURCE,
        /static let defaultPort:\s*UInt16\s*=\s*(\d+)/,
        "AppConstants.WebSocketServer.defaultPort",
      ),
    );
    const swiftControlPrefix = requiredMatch(
      SWIFT_AUTH_SOURCE,
      /case \.control:\s*\n\s*return "([^"]+)"/,
      "WebSocketAuthToken control subprotocol prefix",
    );

    expect(swiftActions).toEqual([...ACTIONS]);
    expect(PROTOCOL_VERSION).toBe(swiftProtocolVersion);
    expect(DEFAULT_PORT).toBe(swiftDefaultPort);
    expect(TOKEN_SUBPROTOCOL_PREFIX).toBe(swiftControlPrefix);
  });

  test("isAction narrows known tokens only", () => {
    expect(isAction("skip")).toBe(true);
    expect(isAction("teleport")).toBe(false);
    expect(isAction("cycle_theme")).toBe(false); // removed in v3
    expect(isAction("")).toBe(false);
  });
});

describe("buildCommand", () => {
  test("stamps type and protocol version", () => {
    expect(buildCommand("skip")).toEqual({
      type: "command",
      action: "skip",
      protocol: PROTOCOL_VERSION,
    });
  });

  test("omits args when empty", () => {
    expect(buildCommand("skip", {})).not.toHaveProperty("args");
  });

  test("includes args when present", () => {
    expect(buildCommand("skip", { to: "3" }).args).toEqual({ to: "3" });
  });

  test("encodeCommand round-trips through the app's parse shape", () => {
    const decoded = JSON.parse(encodeCommand("play_pause"));
    expect(decoded.type).toBe("command");
    expect(decoded.action).toBe("play_pause");
    expect(decoded.protocol).toBe(PROTOCOL_VERSION);
  });
});

describe("tokenSubprotocol", () => {
  test("builds the prefixed subprotocol for a 64-hex token", () => {
    expect(tokenSubprotocol(HEX64)).toBe(`wolfwave.control.${HEX64}`);
  });

  test("trims without changing credential case", () => {
    expect(tokenSubprotocol(`  ${"AB".repeat(32)}  `)).toBe(
      `wolfwave.control.${"AB".repeat(32)}`,
    );
  });

  test("rejects wrong length and non-hex", () => {
    expect(tokenSubprotocol("")).toBeNull();
    expect(tokenSubprotocol("a".repeat(63))).toBeNull();
    expect(tokenSubprotocol("a".repeat(65))).toBeNull();
    expect(tokenSubprotocol("z".repeat(64))).toBeNull();
  });
});

describe("socketURL", () => {
  test("builds a ws:// URL", () => {
    expect(socketURL(8765)).toBe("ws://127.0.0.1:8765");
  });
});

describe("parseFrame", () => {
  test("returns null for malformed input", () => {
    expect(parseFrame("not json")).toBeNull();
    expect(parseFrame("[]")).toBeNull();
    expect(parseFrame("null")).toBeNull();
    expect(parseFrame('{"noType":1}')).toBeNull();
  });

  test("decodes welcome", () => {
    expect(
      parseFrame('{"type":"welcome","server":"WolfWave","version":"2.1.0"}'),
    ).toEqual({ kind: "welcome", server: "WolfWave", version: "2.1.0" });
  });

  test("decodes now_playing", () => {
    const frame = parseFrame(
      JSON.stringify({
        type: "now_playing",
        data: {
          track: "Howl",
          artist: "Grey Wolf",
          album: "Moonlit",
          duration: 210,
          elapsed: 12.5,
          isPlaying: true,
          artworkURL: "https://example.test/a.jpg",
        },
      }),
    );
    expect(frame).toEqual({
      kind: "now_playing",
      data: {
        track: "Howl",
        artist: "Grey Wolf",
        album: "Moonlit",
        duration: 210,
        elapsed: 12.5,
        isPlaying: true,
        artworkURL: "https://example.test/a.jpg",
      },
    });
  });

  test("coerces missing and wrong-typed now_playing fields", () => {
    const frame = parseFrame('{"type":"now_playing","data":{"duration":"x"}}');
    expect(frame).toEqual({
      kind: "now_playing",
      data: {
        track: "",
        artist: "",
        album: "",
        duration: 0,
        elapsed: 0,
        isPlaying: false,
        artworkURL: "",
      },
    });
  });

  test("treats non-finite numbers as zero", () => {
    // JSON has no Infinity literal, but 1e999 parses to Infinity.
    const frame = parseFrame('{"type":"now_playing","data":{"elapsed":1e999}}');
    expect(frame).toMatchObject({ data: { elapsed: 0 } });
  });

  test("decodes queue_state and health", () => {
    expect(
      parseFrame(
        '{"type":"queue_state","data":{"count":3,"pending":1,"held":true,"audience":"subscribers"}}',
      ),
    ).toEqual({
      kind: "queue_state",
      data: { count: 3, pending: 1, held: true, audience: "subscribers" },
    });

    expect(
      parseFrame(
        '{"type":"health","data":{"music":true,"twitch":true,"discord":false,"overlay":true}}',
      ),
    ).toEqual({
      kind: "health",
      data: { music: true, twitch: true, discord: false, discordState: "off", overlay: true },
    });
  });

  test("health decodes discordState and derives a missing or unknown one from discord", () => {
    expect(
      parseFrame(
        '{"type":"health","data":{"music":true,"twitch":true,"discord":true,"overlay":true}}',
      ),
    ).toMatchObject({ data: { discord: true, discordState: "connected" } });
    expect(
      parseFrame(
        '{"type":"health","data":{"music":true,"twitch":true,"discord":false,"discordState":"disconnected","overlay":true}}',
      ),
    ).toEqual({
      kind: "health",
      data: { music: true, twitch: true, discord: false, discordState: "disconnected", overlay: true },
    });
    expect(
      parseFrame(
        '{"type":"health","data":{"music":true,"twitch":true,"discord":false,"discordState":"bogus","overlay":true}}',
      ),
    ).toMatchObject({ data: { discordState: "off" } });
  });

  test("decodes a successful ack without an error field", () => {
    const frame = parseFrame('{"type":"ack","action":"skip","ok":true}');
    expect(frame).toEqual({ kind: "ack", action: "skip", ok: true });
    expect(frame).not.toHaveProperty("error");
  });

  test("decodes a failed ack with its error", () => {
    expect(
      parseFrame('{"type":"ack","action":"skip","ok":false,"error":"music"}'),
    ).toEqual({ kind: "ack", action: "skip", ok: false, error: "music" });
  });

  test("queue_state from an older WolfWave reads held as false", () => {
    // Pre-`held` builds omit the field. Defaulting to false is right: a build
    // that can't report hold also can't have been put on hold from a key.
    expect(
      parseFrame('{"type":"queue_state","data":{"count":1,"pending":0}}'),
    ).toEqual({
      kind: "queue_state",
      data: { count: 1, pending: 0, held: false, audience: "everyone" },
    });
  });

  test("an unrecognised audience falls back to everyone", () => {
    // A newer WolfWave could add a case this build has never heard of. Showing
    // the loosest state is the honest read of "this build cannot tell you".
    expect(
      parseFrame(
        '{"type":"queue_state","data":{"count":0,"pending":0,"audience":"nightbot-only"}}',
      ),
    ).toEqual({
      kind: "queue_state",
      data: { count: 0, pending: 0, held: false, audience: "everyone" },
    });
  });

  test("reports unmodelled types as unknown rather than null", () => {
    // `progress` and `widget_config` are real app frames the plugin ignores.
    expect(parseFrame('{"type":"progress","data":{"elapsed":1}}')).toEqual({
      kind: "unknown",
      type: "progress",
    });
  });
});

describe("isProtocolMismatch", () => {
  const ack = (ok: boolean, error?: string): AckFrame =>
    error === undefined
      ? { kind: "ack", action: "skip", ok }
      : { kind: "ack", action: "skip", ok, error };

  test("is true only for a failed protocol ack", () => {
    expect(isProtocolMismatch(ack(false, "protocol"))).toBe(true);
    expect(isProtocolMismatch(ack(false, "unknown_action"))).toBe(false);
    expect(isProtocolMismatch(ack(false))).toBe(false);
    expect(isProtocolMismatch(ack(true))).toBe(false);
  });
});
