# Stream Deck Control API (Phase A)

Groundwork for the Elgato Stream Deck plugin (WW-36). Makes the existing overlay
WebSocket **bidirectional**: it now accepts inbound command frames and pushes two
new state broadcasts, so a Stream Deck (or any authenticated local client) can
control WolfWave and reflect live state on physical keys.

This doc is the app side only. The plugin that consumes it lives in
[`apps/streamdeck/`](../../streamdeck/README.md) (WW-45, Phase B) — its
`src/wolfwave/protocol.ts` is the TypeScript mirror of this contract, so a change
here needs the matching change there. The plugin builds, carries its icons, and
packages into a `.streamDeckPlugin`; what is still outstanding is verification on
real hardware and the Marketplace submission itself.

## Transport & auth

Reuses `WebSocketServerService` (the overlay server). A client connects with the
`wolfwave.token.<hex>` subprotocol; the handshake already rejects anything
without the correct token, so a **connected client is already authenticated** and
its commands are trusted. There is deliberately no per-command token — that would
be dead weight (`StreamDeckCommand.swift`).

## Inbound command envelope

Text frame, JSON:

```json
{ "type": "command", "action": "skip", "protocol": 1, "args": {} }
```

- `type` must be `"command"`; anything else is ignored (no ack).
- `protocol` must equal `StreamDeckControl.protocolVersion` (currently `1`).
  A mismatch is rejected with `error:"protocol"` so an out-of-date plugin can show
  an "update" state. Bump the version on any breaking envelope change.
- `action` must be a known `StreamDeckAction`; unknown → `error:"unknown_action"`.
- `args` is optional (unused by v1 actions; reserved for future parameters).

Decoding is pure (`StreamDeckControl.parse`) and unit-tested
(`StreamDeckCommandTests`).

### Ack

Every command that runs (or is rejected) gets a reply on the same connection:

```json
{ "type": "ack", "action": "skip", "ok": true }
{ "type": "ack", "action": "skip", "ok": false, "error": "music" }
```

## v1 actions

| `action` | Effect | Fail `error` |
|---|---|---|
| `play_pause` | Apple Music play/pause | `unavailable` / `music` |
| `skip` | Skip to next track | `unavailable` / `music` |
| `hold_queue` / `resume_queue` | Song-request queue hold on/off | — |
| `approve_next` | Approve the first pending request | `empty` |
| `clear_queue` | Clear the request queue | — |
| `block_current` | Add current song title to the blocklist | `empty` |
| `overlay_toggle` | Hide/show playback cards while keeping the control connection alive | — |
| `discord_toggle` | Toggle Discord Rich Presence | — |
| `music_sync_toggle` | Toggle music tracking | — |
| `cycle_theme` | Advance the widget theme, wrapping | — |

Actions without a clean existing service seam (announce, dial/volume) are
deferred to Phase B.

## Outbound state broadcasts

Pushed to every connected client so counter/health keys render without polling:

```json
{ "type": "queue_state", "data": { "count": 3, "pending": 1, "held": false } }
{ "type": "health", "data": { "music": true, "twitch": true, "discord": false, "overlay": true } }
```

`held` reflects real hold state (`SongRequestService.isHoldEnabled`), so a hold
key renders from the app rather than tracking its own optimistic toggle — hold
is changeable from the tray, chat (`!hold`), and Settings, and a plugin-local
guess drifts the moment it's used from any of those.

Fired on: request-queue changes (`SongRequestQueueChanged`), hold changes
(`SongRequestHoldChanged`), Twitch connect/disconnect, a new client connecting,
and after any successful command. `discord` health is currently an is-enabled
proxy; the live IPC connection state is a later refinement.

Outbound broadcasts are additive-compatible: a client that doesn't know a field
ignores it, so adding one here does **not** require a `protocolVersion` bump.
The version gates the *inbound* command envelope only.

## Files

- `Services/WebSocket/StreamDeckCommand.swift` — `StreamDeckAction`,
  `StreamDeckCommand`, `CommandAck`, `StreamDeckControl.parse` (pure, tested).
- `Services/WebSocket/WebSocketServerService.swift` — `onCommand` handler +
  `setCommandHandler`, inbound decode/ack in `receiveMessage`,
  `broadcastQueueState` / `broadcastHealth`.
- `Core/AppDelegate+StreamDeck.swift` — `handleStreamDeckCommand` (action →
  service), `broadcastStreamDeckState`.
- `Core/AppDelegate+Services.swift` — installs the handler, wires broadcast
  triggers.
- `WolfWaveTests/StreamDeckCommandTests.swift` — parse + ack coverage.

## Manual end-to-end check

With the overlay server enabled and Music playing, connect a WebSocket client
using the `wolfwave.token.<hex>` subprotocol (copy the token from Stream Widgets
settings), send `{"type":"command","action":"skip","protocol":1}`, and confirm
the ack frame plus the track skipping. Watch for `queue_state` / `health` frames
on request-queue and connection changes.
