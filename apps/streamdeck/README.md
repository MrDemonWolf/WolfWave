# WolfWave Stream Deck Plugin

Elgato Stream Deck plugin for WolfWave (WW-45, Phase B). Consumes the
bidirectional control API shipped in Phase A — see
[`apps/native/docs/streamdeck-control-api.md`](../native/docs/streamdeck-control-api.md),
which is the authoritative contract for everything in `src/wolfwave/`.

## Layout

| Path | What |
|---|---|
| `src/wolfwave/protocol.ts` | Pure wire layer: action tokens, command envelope, inbound frame decode, token subprotocol. TypeScript mirror of `StreamDeckCommand.swift`. |
| `src/wolfwave/state.ts` | Pure reducer folding inbound frames into the state keys render from. |
| `src/wolfwave/client.ts` | The single shared WebSocket: reconnect backoff, ack correlation. |
| `src/actions/base.ts` | Shared key behaviour — subscribe on appear, send on press, paint connection states. |
| `src/actions/index.ts` | One class per manifest action. |
| `src/plugin.ts` | Entry point: registers actions, applies global settings. |
| `com.mrdemonwolf.wolfwave.sdPlugin/` | The plugin bundle Stream Deck loads (manifest, Property Inspector, built output). |

One socket is shared by every key. WolfWave broadcasts `queue_state` and
`health` to all connected clients, so a socket per key would multiply the
broadcast fan-out for no benefit.

## Commands

```bash
bun run --filter streamdeck build
```

```bash
bun run --filter streamdeck test
```

```bash
bun run --filter streamdeck typecheck
```

`build` bundles `src/plugin.ts` into `com.mrdemonwolf.wolfwave.sdPlugin/bin/plugin.js`
targeting Node, because Stream Deck runs `CodePath` under its own bundled Node
rather than Bun. The output is gitignored — it is rebuilt, not committed.

## Setup

1. Build, then symlink or copy `com.mrdemonwolf.wolfwave.sdPlugin/` into
   `~/Library/Application Support/com.elgato.StreamDeck/Plugins/`.
2. Restart the Stream Deck app.
3. Drop a WolfWave key onto a page, open its Property Inspector, and paste the
   access token from WolfWave: Settings → Stream Widgets.
4. Leave host and port alone unless WolfWave runs on a different Mac.

Settings are global, not per-key: one WolfWave install serves every key, so the
token is entered once.

## Key states

The base class paints these centrally, so no individual key can forget one:

| Phase | Key shows | Meaning |
|---|---|---|
| `disconnected` | `Offline` | No socket. Retrying with capped backoff. |
| `unauthorized` | `Token?` | Token missing or not 64 hex characters. Retrying won't help. |
| `outdated` | `Update` | WolfWave rejected the protocol version (`ack error:"protocol"`). |
| `connected` | per-key render | Live. |

## Protocol version

`PROTOCOL_VERSION` in `src/wolfwave/protocol.ts` must equal
`StreamDeckControl.protocolVersion` in the app. The action tokens in `ACTIONS`
are the raw values of the Swift `StreamDeckAction` enum, so renaming one is a
protocol change that requires bumping the version on both sides.
`tests/protocol.test.ts` pins the full v1 action set; it fails when the two
drift.

## Not yet done

Needs hardware or an Elgato account, so it cannot be completed or verified in
this repo:

- End-to-end verification on a physical Stream Deck or the Elgato simulator.
  Nothing here has been confirmed against real keys.
- Action icons. `manifest.json` references `imgs/…` paths that do not exist yet;
  Stream Deck renders a placeholder until they are added.
- `.streamDeckPlugin` packaging (`streamdeck pack`) and Marketplace submission.

Deferred v1 actions from WW-45: announce song, and a now-playing dial with album
art and rotation-bound volume. Both want app-side seams that don't exist yet.
