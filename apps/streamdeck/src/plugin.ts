/**
 * WolfWave Stream Deck plugin entry point.
 *
 * Owns the single {@link WolfWaveClient} shared by every key, wires connection
 * settings from global settings (so the streamer configures port/control token once
 * rather than per key), and registers the v2 action set.
 */

import streamDeck from "@elgato/streamdeck";
import { ACTION_CLASSES } from "./actions/index.js";
import { WolfWaveClient } from "./wolfwave/client.js";
import { DEFAULT_PORT } from "./wolfwave/protocol.js";

const client = new WolfWaveClient();

for (const ActionClass of ACTION_CLASSES) {
  streamDeck.actions.registerAction(new ActionClass(client));
}

/**
 * Applies connection settings.
 *
 * Settings arrive as untyped JSON from the Property Inspector, so each field is
 * read defensively rather than trusted — a hand-edited settings file shouldn't
 * be able to hand the socket a non-string token.
 *
 * The control channel is fixed to loopback so a credential copied into Stream Deck cannot authorize commands from another machine.
 */
function applySettings(settings: Record<string, unknown>): void {
  const port = readPort(settings.port);
  const token = readString(settings.token);

  if (!token) {
    // Nothing to connect with yet — first run, before the streamer has pasted
    // their token. Keys render "Token?" rather than looking merely offline.
    client.stop();
    return;
  }

  client.configure({ port, token });
}

function readString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function readPort(value: unknown): number {
  if (typeof value !== "number" || !Number.isInteger(value)) return DEFAULT_PORT;
  return value > 0 && value <= 65535 ? value : DEFAULT_PORT;
}

streamDeck.settings.onDidReceiveGlobalSettings((ev) => {
  applySettings(ev.settings);
});

await streamDeck.connect();

applySettings(await streamDeck.settings.getGlobalSettings());
