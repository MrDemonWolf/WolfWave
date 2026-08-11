import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { createContext, runInContext } from "node:vm";

/**
 * Exercises the Property Inspector script.
 *
 * It has to stay a classic browser script (Stream Deck loads it via a plain
 * `<script src>` and calls a global entry point), so it can't be imported. It is
 * also the only place the port and token rules are enforced before they reach
 * the plugin, and a stale error message or a leniently-parsed port is exactly
 * the kind of thing that looks fine until someone is live. Running it in a `vm`
 * with stub DOM elements is the cheapest way to actually test it.
 */

const SOURCE = readFileSync(
  new URL(
    "../com.mrdemonwolf.wolfwave.sdPlugin/ui/connection.js",
    import.meta.url,
  ),
  "utf8",
);
const HTML = readFileSync(
  new URL(
    "../com.mrdemonwolf.wolfwave.sdPlugin/ui/connection.html",
    import.meta.url,
  ),
  "utf8",
);

interface StubField {
  value: string;
  attributes: Record<string, string>;
  listeners: Record<string, Array<() => void>>;
  setAttribute(name: string, value: string): void;
  removeAttribute(name: string): void;
  addEventListener(type: string, handler: () => void): void;
  /** Fires every handler registered for `type`, like a real event would. */
  dispatch(type: string): void;
}

function stubField(): StubField {
  return {
    value: "",
    attributes: {},
    listeners: {},
    setAttribute(name, value) {
      this.attributes[name] = value;
    },
    removeAttribute(name) {
      delete this.attributes[name];
    },
    addEventListener(type, handler) {
      (this.listeners[type] ??= []).push(handler);
    },
    dispatch(type) {
      for (const handler of this.listeners[type] ?? []) handler();
    },
  };
}

interface Panel {
  token: StubField;
  port: StubField;
  status: StubField & { textContent: string };
  sent: unknown[];
  refreshStatus(): void;
  save(): void;
}

/**
 * Loads the script with stub DOM nodes and an already-open stub socket, then
 * runs its real Stream Deck entry point.
 *
 * Going through `connectElgatoStreamDeckSocket` rather than poking internals
 * means the test covers the actual registration path and the real `send`
 * guard, and `sent` holds exactly what would go over the wire.
 */
function loadPanel(): Panel {
  const token = stubField();
  const port = stubField();
  const status = { ...stubField(), textContent: "" };
  const sent: unknown[] = [];

  const elements: Record<string, unknown> = { token, port, status };

  class StubSocket {
    static readonly OPEN = 1;
    readyState = 1;
    onopen: (() => void) | null = null;
    onmessage: ((event: { data: string }) => void) | null = null;
    send(raw: string) {
      sent.push(JSON.parse(raw));
    }
  }

  const sandbox: Record<string, unknown> = {
    document: { getElementById: (id: string) => elements[id] },
    WebSocket: StubSocket,
    console,
  };
  sandbox.globalThis = sandbox;

  const context = createContext(sandbox);
  runInContext(SOURCE, context);

  const scoped = context as unknown as {
    connectElgatoStreamDeckSocket(
      port: number,
      uuid: string,
      registerEvent: string,
      info: unknown,
      actionInfo: unknown,
    ): void;
    refreshStatus(): void;
    save(): void;
  };

  scoped.connectElgatoStreamDeckSocket(28196, "test-uuid", "registerPI", {}, {});
  // Drop the registration traffic so assertions see only what save() emits.
  sent.length = 0;

  return {
    token,
    port,
    status,
    sent,
    refreshStatus: () => scoped.refreshStatus(),
    save: () => scoped.save(),
  };
}

const HEX64 = "a".repeat(64);

describe("property inspector document", () => {
  test("provides the elements and script required by connection.js", () => {
    expect(HTML).toContain(`id="token"`);
    expect(HTML).toContain(`id="port"`);
    expect(HTML).toContain(`id="status"`);
    expect(HTML).toContain(`<script src="connection.js"></script>`);
  });
});

describe("port parsing", () => {
  test("accepts a plain decimal port", () => {
    const panel = loadPanel();
    panel.token.value = HEX64;
    panel.port.value = "9000";
    panel.save();
    expect(panel.sent.at(-1)).toMatchObject({ payload: { port: 9000 } });
  });

  test("blank falls back to the default", () => {
    const panel = loadPanel();
    panel.token.value = HEX64;
    panel.port.value = "";
    panel.save();
    expect(panel.sent.at(-1)).toMatchObject({ payload: { port: 8765 } });
  });

  test("trims surrounding whitespace", () => {
    const panel = loadPanel();
    panel.token.value = HEX64;
    panel.port.value = "  9000  ";
    panel.save();
    expect(panel.sent.at(-1)).toMatchObject({ payload: { port: 9000 } });
  });

  test.each(["123abc", "1.5", "1e3", "1 2", "-1", "0", "65536", "abc"])(
    "rejects %p and falls back to the default",
    (raw) => {
      // parseInt would have quietly saved 123, 1, and 1 for the first three —
      // a port the streamer never typed.
      const panel = loadPanel();
      panel.token.value = HEX64;
      panel.port.value = raw;
      panel.save();
      expect(panel.sent.at(-1)).toMatchObject({ payload: { port: 8765 } });
    },
  );

  test("accepts the range boundaries", () => {
    for (const [raw, expected] of [
      ["1", 1],
      ["65535", 65535],
    ] as const) {
      const panel = loadPanel();
      panel.token.value = HEX64;
      panel.port.value = raw;
      panel.save();
      expect(panel.sent.at(-1)).toMatchObject({ payload: { port: expected } });
    }
  });
});

describe("status line", () => {
  test("a corrected port clears its error", () => {
    // The regression: independent per-field validators left "Port must be…"
    // on screen after the field was fixed.
    const panel = loadPanel();
    panel.token.value = HEX64;
    panel.port.value = "70000";
    panel.refreshStatus();
    expect(panel.status.textContent).toContain("Port must be");

    panel.port.value = "8765";
    panel.refreshStatus();
    expect(panel.status.textContent).toBe("Control token looks right.");
    expect(panel.port.attributes["aria-invalid"]).toBe("false");
  });

  test("a token error outranks a port error", () => {
    // An unusable token blocks the connection outright; a bad port only falls
    // back to the default.
    const panel = loadPanel();
    panel.token.value = "nope";
    panel.port.value = "70000";
    panel.refreshStatus();
    expect(panel.status.textContent).toContain("64 hex characters");
  });

  test("a corrected token clears its error", () => {
    const panel = loadPanel();
    panel.token.value = "nope";
    panel.refreshStatus();
    expect(panel.token.attributes["aria-invalid"]).toBe("true");

    panel.token.value = HEX64;
    panel.refreshStatus();
    expect(panel.token.attributes["aria-invalid"]).toBe("false");
    expect(panel.status.textContent).toBe("Control token looks right.");
  });

  test("blank token prompts rather than erroring", () => {
    const panel = loadPanel();
    panel.refreshStatus();
    expect(panel.status.textContent).toContain("Paste your control token");
    expect(panel.token.attributes["aria-invalid"]).toBeUndefined();
  });
});

describe("save", () => {
  test("persists a blank token so the plugin disconnects", () => {
    // Gating the send on validity would strand the plugin on the last good
    // token while the panel showed an empty field.
    const panel = loadPanel();
    panel.token.value = "";
    panel.save();
    expect(panel.sent.at(-1)).toMatchObject({ payload: { token: "" } });
  });

  test("persists a malformed token so keys can show Token?", () => {
    const panel = loadPanel();
    panel.token.value = "nope";
    panel.save();
    expect(panel.sent.at(-1)).toMatchObject({ payload: { token: "nope" } });
  });

  test("never persists a configurable host", () => {
    const panel = loadPanel();
    panel.token.value = HEX64;
    panel.save();

    const message = panel.sent.at(-1) as { payload: Record<string, unknown> };
    expect(message.payload).not.toHaveProperty("host");
    expect(message.payload.port).toBe(8765);
  });

  test("trims the token", () => {
    const panel = loadPanel();
    panel.token.value = `  ${HEX64}  `;
    panel.save();
    expect(panel.sent.at(-1)).toMatchObject({ payload: { token: HEX64 } });
  });
});

describe("event wiring", () => {
  test("one edit writes settings once", () => {
    // Both `change` and `blur` were registered to save, so committing an edit
    // sent setGlobalSettings twice.
    const panel = loadPanel();
    panel.token.value = HEX64;
    panel.token.dispatch("input");
    panel.token.dispatch("change");
    panel.token.dispatch("blur");
    expect(panel.sent).toHaveLength(1);
  });

  test("typing updates the status without persisting", () => {
    // `input` fires per keystroke; persisting there would write on every
    // character of a 64-character token.
    const panel = loadPanel();
    panel.token.value = "nope";
    panel.token.dispatch("input");
    expect(panel.sent).toHaveLength(0);
    expect(panel.status.textContent).toContain("64 hex characters");
  });
});
