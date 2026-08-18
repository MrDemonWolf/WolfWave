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

The art lives in `src/keyart.ts` — glyphs plus the composers that arrange them.
`scripts/generate-icons.ts` bakes the static manifest images from it, and the
actions import the same module to repaint keys live, so a key's live art and its
manifest fallback can never disagree.

Generated images land in `com.mrdemonwolf.wolfwave.sdPlugin/imgs/`. Unlike
`bin/`, these **are** committed: they are inputs, not build output. Regenerate
with `bun run --filter streamdeck icons` after changing `keyart.ts` or the brand
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
in sync. The plugin icon is the only raster file, rendered through resvg.

### Reading a key

A key is 72×72 and gets glanced at from across a room, so state is carried by the
whole key rather than by the glyph alone:

| Treatment | Means | Keys |
|---|---|---|
| Brand tile `#0066CC`, glyph knocked out white | On / live | the three toggles, playing, queue held, links up |
| Amber tile `#FF9F0A` | Wants the streamer to act | Approve Next with requests pending |
| Red glyph on black `#FF453A` | Destructive | Clear Queue, Block Song |
| White glyph on black | Available, currently off | everything else |
| Grey glyph `#8E8E93` | Nothing to act on | Approve Next with an empty queue |

Brand **600** rather than 500 is deliberate: the default white Elgato title only
clears 4.5:1 contrast on the darker blue.

Some keys paint themselves at runtime with `setImage` instead of using their
manifest state image, because no static file can carry a number, a word, or a
cover:

| Key | Live art |
|---|---|
| Hold Queue | queue glyph plus the queue depth as a large numeral, capped at `99+` |
| Approve Next | check plus the pending count, amber tile when any are pending |
| Clear Queue | red trash plus the queue depth |
| Request Access | the gate glyph plus the current audience (`ALL` / `SUB` / `VIP` / `MOD`), tiled once it is narrower than everyone |
| Now Playing | the track's album art, fetched and inlined as a data URI; falls back to the note glyph |

Those leave the Elgato title alone, so a user-set label survives. Play /
Pause still writes the track name into the title. Any key drops back to its
manifest image when the connection goes away, so a stale count can never sit
under an `Offline` title.

### Hold to confirm

`clear_queue` and `block_requester` do not fire on press. `WolfWaveKeyAction`
exposes `holdToConfirmMs` (default `0` = fire on press); those two override it
to 800ms, and the base class times the gap between `keyDown` and `keyUp`,
because the Stream Deck payload carries no press duration. Timing goes through
`src/clock.ts` so tests control elapsed time rather than sleeping.

### Album art

`src/artwork.ts` fetches `artworkURL` (an iTunes CDN URL from WolfWave) and
inlines it as a data URI, since `setImage` takes no URLs. HTTPS only, bounded
size, bounded timeout, cached by URL, and every failure path returns
`undefined` so the key falls back to its glyph rather than throwing on air.

## Setup

1. Build, then symlink or copy `com.mrdemonwolf.wolfwave.sdPlugin/` into
   `~/Library/Application Support/com.elgato.StreamDeck/Plugins/`.
2. Restart the Stream Deck app.
3. Drop a WolfWave key onto a page, open its Property Inspector, and paste the
   **Stream Deck Control Token** from WolfWave: Settings → Stream Widgets.
4. Leave the port alone unless you changed it in WolfWave. The host is fixed to
   `127.0.0.1`; command transport is intentionally same-Mac only.

Settings are global, not per-key: one WolfWave install serves every key, so the
control token is entered once. Protocol-v1 installs must copy this new token
after upgrading; the former shared token remains read-only for overlays.

## Key states

The base class paints these centrally, so no individual key can forget one:

| Phase | Key shows | Meaning |
|---|---|---|
| `disconnected` | `Offline` | No socket. Retrying with capped backoff. |
| `unauthorized` | `Token?` | Control token missing or not 64 hex characters. Retrying won't help. |
| `outdated` | `Update` | WolfWave rejected the protocol version (`ack error:"protocol"`). |
| `connected` | per-key render | Live. |

## Protocol version

`PROTOCOL_VERSION` in `src/wolfwave/protocol.ts` must equal
`StreamDeckControl.protocolVersion` in the app. The action tokens in `ACTIONS`
are the raw values of the Swift `StreamDeckAction` enum, so renaming one is a
protocol change that requires bumping the version on both sides.
`tests/protocol.test.ts` pins the full v3 action set; it fails when the two
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

Announce song and the now-playing key both shipped in protocol v3. What is still
deferred from WW-45 is the *dial* form of now playing: an encoder with album art
and rotation-bound volume. That wants `setFeedback`/`setFeedbackLayout` and an
app-side volume seam, neither of which exists yet.
