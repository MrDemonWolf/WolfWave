# Stream Deck Control API

> Living reference. This is the current wire contract for protocol v3, not a plan.
> It is enforced by `apps/streamdeck/tests/protocol.test.ts` and the `streamdeck` CI job.

The WebSocket transport accepts role-authenticated command frames and pushes two
state broadcasts, so a same-Mac Stream Deck can control WolfWave and reflect live
state on physical keys. Originally shipped as WW-36.

This doc is the app side only. The plugin that consumes it lives in
[`apps/streamdeck/`](../../streamdeck/README.md) (WW-45); its
`src/wolfwave/protocol.ts` is the TypeScript mirror of this contract, so a change
here needs the matching change there, and `PROTOCOL_VERSION` must equal
`StreamDeckControl.protocolVersion` on the Swift side. CI fails the PR if they diverge.
The plugin builds, carries its icons, and packages into a `.streamDeckPlugin`; what is
still outstanding is verification on real hardware and the Marketplace submission itself.

## Transport & auth

Reuses `WebSocketServerService`, with a distinct role and credential at the
handshake. A control client presents `wolfwave.control.<hex>` using the **Stream
Deck Control Token** from Settings. The server accepts that role only from a
literal loopback IP (`127/8` or `::1`) and revalidates the selected subprotocol
before receiving frames. OBS uses a separate `wolfwave.overlay.<hex>` token that
may receive broadcasts over the LAN but can never run commands. There is no
per-command token (`StreamDeckCommand.swift`).

## Inbound command envelope

Text frame, JSON:

```json
{ "type": "command", "action": "skip", "protocol": 3, "args": {} }
```

- `type` must be `"command"`; anything else is ignored (no ack).
- `protocol` must equal `StreamDeckControl.protocolVersion` (currently `3`).
  A mismatch is rejected with `error:"protocol"` so an out-of-date plugin can show
  an "update" state. Bump the version on any breaking envelope change.
- `action` must be a known `StreamDeckAction`; unknown → `error:"unknown_action"`.
- `args` is optional (unused by v3 actions; reserved for future parameters).

Decoding is pure (`StreamDeckControl.parse`) and unit-tested
(`StreamDeckCommandTests`).

### Ack

Every command that runs (or is rejected) gets a reply on the same connection:

```json
{ "type": "ack", "action": "skip", "ok": true }
{ "type": "ack", "action": "skip", "ok": false, "error": "music" }
```

## v3 actions

| `action` | Effect | Fail `error` |
|---|---|---|
| `play_pause` | Apple Music play/pause | `unavailable` / `music` |
| `skip` | Skip to next track | `unavailable` / `music` |
| `hold_queue` / `resume_queue` | Song-request queue hold on/off | — |
| `approve_next` | Approve the first pending request | `empty` |
| `clear_queue` | Clear the request queue | — |
| `block_current` | Add current song title to the blocklist | `empty` |
| `overlay_toggle` | Hide/show playback cards while keeping the control connection alive | — |
| `announce_song` | Post the current track to Twitch chat | `twitch` / `empty` |
| `reject_current` | Drop the playing request and announce it | `unavailable` / `empty` |
| `block_requester` | Blocklist whoever requested the playing song | `unavailable` / `empty` |
| `cycle_audience` | Advance the request audience, wrapping | `unavailable` |

`clear_queue` and `block_requester` are the actions the plugin gates behind a hold. The wire
protocol is unchanged — the app runs whatever it receives — but the plugin
will not send them on a tap. Any other client is free to send them outright.

### Removed in v3

`discord_toggle`, `music_sync_toggle`, and `cycle_theme` were dropped. All three
flipped a set-once preference, and a deck slot is worth more than a key pressed
twice a year. A v2 plugin sending one now gets `error: "unknown_action"`, and a
v2 plugin at all gets `error: "protocol"` first.

Volume and other dial-shaped controls are still deferred: they want an encoder
surface (`setFeedback`) rather than a key, which this contract does not model.

## Outbound state broadcasts

Pushed to every connected client so counter/health keys render without polling:

```json
{ "type": "queue_state", "data": { "count": 3, "pending": 1, "held": false, "audience": "everyone" } }
{ "type": "health", "data": { "music": true, "twitch": true, "discord": false, "overlay": true } }
```

`audience` is the raw `RequestAudience` value (`everyone`, `subscribers`,
`vipsAndSubs`, `modsOnly`), in that order — the cycle key walks the list, so the
order is part of the contract. A client that doesn't recognise a value should
fall back to `everyone`.

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
- `Services/SongRequest/SongBlocklist.swift` — `isBlockedRequester`, backing
  `block_requester`; `Core/BlocklistItem.swift` carries the `.requester` type.
- `Services/SongRequest/SongRequestAccess.swift` — `RequestAudience.next`,
  backing `cycle_audience`.
- `WolfWaveTests/StreamDeckCommandTests.swift` — parse + ack coverage.
- `WolfWaveTests/RequesterBlocklistTests.swift` — requester blocking and the
  audience cycle.

## Manual end-to-end check

With the server enabled and Music playing, connect from the same Mac using the
`wolfwave.control.<hex>` subprotocol (copy the Stream Deck Control Token from
Stream Widgets settings), send
`{"type":"command","action":"skip","protocol":3}`, and confirm the ack frame
plus the track skipping. Watch for `queue_state` / `health` frames
on request-queue and connection changes.
