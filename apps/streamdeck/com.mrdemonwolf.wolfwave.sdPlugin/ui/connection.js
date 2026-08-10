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
  validate();
}

/**
 * Validates the token locally.
 *
 * Worth doing here because a bad token and a closed WolfWave produce the same
 * silent handshake rejection on the wire — without this check, a typo looks
 * exactly like "the app isn't running".
 */
function validate() {
  const token = fields.token.value.trim();
  if (!token) {
    fields.token.removeAttribute("aria-invalid");
    setStatus("Paste your access token to connect.", null);
    return false;
  }
  const valid = TOKEN_PATTERN.test(token);
  fields.token.setAttribute("aria-invalid", String(!valid));
  setStatus(
    valid ? "Token looks right." : "That token isn't 64 hex characters.",
    valid,
  );
  return valid;
}

function setStatus(text, ok) {
  status.textContent = text;
  if (ok === null) status.removeAttribute("data-ok");
  else status.setAttribute("data-ok", String(ok));
}

function save() {
  validate();
  const port = Number.parseInt(fields.port.value, 10);
  settings = {
    token: fields.token.value.trim(),
    host: fields.host.value.trim() || DEFAULT_HOST,
    port: Number.isFinite(port) && port > 0 ? port : DEFAULT_PORT,
  };
  send({ event: "setGlobalSettings", context: uuid, payload: settings });
}

for (const field of Object.values(fields)) {
  field.addEventListener("change", save);
  field.addEventListener("blur", save);
}
fields.token.addEventListener("input", validate);
