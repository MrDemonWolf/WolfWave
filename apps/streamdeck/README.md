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

```bash
bun run --filter streamdeck icons
```

```bash
bun run --filter streamdeck pack
```

`build` bundles `src/plugin.ts` into `com.mrdemonwolf.wolfwave.sdPlugin/bin/plugin.js`
targeting Node, because Stream Deck runs `CodePath` under its own bundled Node
rather than Bun. The output is gitignored — it is rebuilt, not committed.

`pack` builds, then wraps the bundle into
`dist/com.mrdemonwolf.wolfwave.streamDeckPlugin`, the file the Elgato
Marketplace takes. It validates the manifest and every asset it references, so
CI runs it as the shippability check. Note that it rewrites `manifest.json` in
the Elgato CLI's own formatting; that formatting is what is committed, so a pack
run leaves the tree clean.

## Icons

`scripts/generate-icons.ts` emits every image the manifest points at, into
`com.mrdemonwolf.wolfwave.sdPlugin/imgs/`. Unlike `bin/`, these **are**
committed: they are inputs, not build output. Regenerate with
`bun run --filter streamdeck icons` after changing the glyph table or the brand
mark, and commit the result. CI fails the PR on drift.

Glyphs are authored once on a 24×24 grid and scaled per slot, so the action icon
and the key art can never disagree. Elgato's format rules drive the output:

| Slot | Format | Sizes | Style |
|---|---|---|---|
| Action `Icon` | PNG or SVG | 20×20, 40×40 (@2x) | monochrome `#FFFFFF`, transparent |
| State `Image` (key) | GIF, PNG or SVG | 72×72, 144×144 (@2x) | free |
| `CategoryIcon` | PNG or SVG | 28×28, 56×56 (@2x) | monochrome `#FFFFFF`, transparent |
| `Icon` (plugin) | **PNG only** | 256×256, 512×512 (@2x) | free |

Everything that accepts SVG ships as one SVG, so there is no @1x/@2x pair to keep
in sync. The plugin icon is the only raster file, rendered through resvg. Key art
uses brand blue for on/live states and grey for idle, which is the only state cue
a key has besides its title.

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
  Nothing here has been confirmed against real keys. Check the weakest
  assumption first: two keys bound to the same action, pressed in quick
  succession. Ack correlation is FIFO with no correlation id.
- Marketplace submission. The packaged `.streamDeckPlugin` is one `bun run
  --filter streamdeck pack` away; submitting it needs an Elgato Maker account.

Deferred v1 actions from WW-45: announce song, and a now-playing dial with album
art and rotation-bound volume. Both want app-side seams that don't exist yet.
