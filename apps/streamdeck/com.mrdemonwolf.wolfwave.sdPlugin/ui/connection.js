"use strict";

/**
 * Property Inspector for the WolfWave plugin.
 *
 * Talks Elgato's Property Inspector protocol directly (the
 * `connectElgatoStreamDeckSocket` global) rather than through a component
 * library, so the panel has no network dependency.
 *
 * Settings are *global*, not per-action: one WolfWave install serves every key,
 * so asking for the token once per key would be busywork.
 */

const DEFAULT_HOST = "127.0.0.1";
const DEFAULT_PORT = 8765;
/** Matches the app's 64-hex token (`WebSocketAuthToken.generate`). */
const TOKEN_PATTERN = /^[0-9a-fA-F]{64}$/;

let socket = null;
let uuid = null;
let settings = {};

const fields = {
  token: document.getElementById("token"),
  host: document.getElementById("host"),
  port: document.getElementById("port"),
};
const status = document.getElementById("status");

/**
 * Stream Deck's Property Inspector entry point. Argument names and order are
 * fixed by Elgato; the app calls this global once the panel loads.
 */
globalThis.connectElgatoStreamDeckSocket = function (
  inPort,
  inUUID,
  inRegisterEvent,
  _inInfo,
  _inActionInfo,
) {
  uuid = inUUID;
  socket = new WebSocket(`ws://127.0.0.1:${inPort}`);

  socket.onopen = () => {
    send({ event: inRegisterEvent, uuid: inUUID });
    send({ event: "getGlobalSettings", context: inUUID });
  };

  socket.onmessage = (event) => {
    let payload;
    try {
      payload = JSON.parse(event.data);
    } catch {
      return;
    }
    if (payload.event !== "didReceiveGlobalSettings") return;
    settings = payload.payload?.settings ?? {};
    hydrate();
  };
};

function send(message) {
  if (socket?.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify(message));
  }
}

function hydrate() {
  fields.token.value = settings.token ?? "";
  fields.host.value = settings.host ?? "";
  fields.port.value = settings.port ?? "";
  refreshStatus();
}

/**
 * Strictly parses a port.
 *
 * `Number.parseInt` is too lenient for a field that has to agree with
 * `readPort` in `src/plugin.ts`: it turns `123abc` into 123, `1.5` into 1, and
 * `1e3` into 1. Any of those would be persisted as a number the streamer never
 * typed. Digits only, or it isn't a port.
 *
 * Returns `null` for blank (meaning "use the default") and `undefined` for
 * invalid, so callers can tell the two apart.
 */
function parsePort(raw) {
  if (!raw) return null;
  if (!/^\d+$/.test(raw)) return undefined;
  const port = Number(raw);
  return port > 0 && port <= 65535 ? port : undefined;
}

/**
 * Validates both fields and paints the single status line.
 *
 * Deliberately one function rather than one per field: there is only one status
 * element, so independent validators would overwrite each other's message and
 * leave a corrected field still showing its old error. Errors are reported
 * token-first because an unusable token blocks the connection outright, while a
 * bad port only falls back to the default.
 *
 * Local validation earns its keep because a bad token and a closed WolfWave
 * produce the same silent handshake rejection on the wire — without it, a typo
 * looks exactly like "the app isn't running".
 */
function refreshStatus() {
  const token = fields.token.value.trim();
  const tokenValid = TOKEN_PATTERN.test(token);
  if (!token) fields.token.removeAttribute("aria-invalid");
  else fields.token.setAttribute("aria-invalid", String(!tokenValid));

  const port = parsePort(fields.port.value.trim());
  const portValid = port !== undefined;
  fields.port.setAttribute("aria-invalid", String(!portValid));

  if (token && !tokenValid) {
    setStatus("That token isn't 64 hex characters.", false);
  } else if (!portValid) {
    setStatus("Port must be a whole number between 1 and 65535.", false);
  } else if (!token) {
    setStatus("Paste your access token to connect.", null);
  } else {
    setStatus("Token looks right.", true);
  }

  return { tokenValid, port };
}

function setStatus(text, ok) {
  status.textContent = text;
  if (ok === null) status.removeAttribute("data-ok");
  else status.setAttribute("data-ok", String(ok));
}

/**
 * Persists the current field values.
 *
 * Sends unconditionally, including when the token is blank or malformed. Both
 * cases have to reach the plugin: a blank token is how it knows to disconnect,
 * and a malformed one is what puts the keys into their "Token?" state. Gating
 * the send on validity would strand the plugin on the last good token while the
 * panel showed something else.
 */
function save() {
  const { port } = refreshStatus();
  settings = {
    token: fields.token.value.trim(),
    host: fields.host.value.trim() || DEFAULT_HOST,
    // null (blank) and undefined (invalid) both fall back to the default, which
    // is what plugin.ts's readPort does with the same values.
    port: port ?? DEFAULT_PORT,
  };
  send({ event: "setGlobalSettings", context: uuid, payload: settings });
}

for (const field of Object.values(fields)) {
  field.addEventListener("change", save);
  field.addEventListener("blur", save);
  field.addEventListener("input", refreshStatus);
}
