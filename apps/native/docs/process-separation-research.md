# Process Separation Research — WolfWave Integrations

Status: research / recommendation. No code changed yet.
Date: 2026-05-28.

## Question

Can we split integrations (Twitch, Discord, WebSocket/overlay, Apple Music) into
their own processes to (a) lower resource use and (b) let some pieces run in the
background?

## Short answer

**Process separation will not lower resource use. It raises total memory.** Each
extra process loads its own Swift runtime + Foundation + Network.framework
(tens of MB each), and the actual CPU work is unchanged. So if the goal is "use
fewer resources", splitting is the wrong lever — see [In-process wins](#what-actually-lowers-resource-use) below.

What separation *does* buy:

1. **Crash isolation** — a crash in the Discord IPC parser or Twitch WebSocket
   stops taking down the menu bar / now-playing card with it.
2. **Sandbox hardening** — each helper gets a tighter, single-purpose entitlement
   set instead of one process holding apple-events + network.server +
   network.client + the Discord socket exception all at once.
3. **Idle reclamation** — an XPC service launchd kills when idle frees 100% of its
   memory. But this only helps for *bursty* work, not always-on connections.

"Run in the background": WolfWave already is a background app (LSUIElement menu
bar) and already launches at login via `SMAppService.mainApp` (LaunchAtLoginService).
There is no work today that needs a process living *beyond* the app's own
lifetime, so a true login daemon/agent is not warranted.

## Current state (what we have)

WolfWave is **one process**. Services are Swift `actor`s / `@MainActor` types
driven by async/await on background QoS — they already do **not** block the UI
thread. Threads are not processes; we already have good concurrency isolation.

Distribution: **sandboxed**, but shipped via **DMG + Homebrew + Developer ID
notarization** (not the Mac App Store). This matters: we may use XPC services,
SMAppService agents, and temporary-exception entitlements — MAS-only
restrictions do not apply.

Wiring lives in `AppDelegate+Services.swift`. Services already start lazily
behind feature flags and throttle on battery via `PowerStateMonitor`
(`powerStateChanged`), which is the right resource posture.

| Service | Work | Entitlements it needs | Coupling to rest of app |
|---|---|---|---|
| `WebSocketServerService` + `WidgetHTTPService` | Inbound WS + static HTTP server on a LAN port | `network.server` only | Low — one-way `updateNowPlaying`/`updateArtworkURL` pushes |
| `DiscordRPCService` | Local Unix-socket IPC, framing, reconnect backoff | `temporary-exception.sbpl` (discord-ipc socket) only | Low — receives presence pushes, emits state stream |
| `TwitchChatService` | Long-lived EventSub WebSocket + Helix HTTP | `network.client` only | **High** — song-request providers, skip-vote, polls, channel-points/bits callbacks |
| `AppleMusicSource` | ScriptingBridge + apple-events, 2s poll | `automation.apple-events` + Music scripting-targets | **High** — the data source everything else consumes |

## Apple mechanisms considered

### XPC Service (the right tool here)
Bundled at `WolfWave.app/Contents/XPCServices/Foo.xpc`. launchd-managed, launched
on first `NSXPCConnection` message, **SIGKILL'd when idle or under memory
pressure**. The connection stays valid and transparently relaunches the service
on next use. Apple's guidance: an XPC service must hold **minimal/ideally zero
persistent state** because it can die at any moment.

> **Gotcha for WolfWave:** EventSub, Discord IPC, and the WS server are
> *always-on while their feature is enabled*. To keep those connections alive in
> an XPC service you must keep the service busy, which defeats idle reclamation.
> For these, the benefit is **crash isolation + sandbox hardening, not memory
> savings**. State (e.g. reconnect/backoff, queue) must survive service restarts —
> either re-establish from the app side on `interruptionHandler`, or persist.

`interruptionHandler` (service crashed/was killed) and `invalidationHandler`
(connection torn down) are the crash-recovery hooks — the whole point: the main
app respawns the service and re-pushes state instead of crashing with it.

### SMAppService agent / daemon (macOS 13+)
For helpers that run at login or outlive the app. Overkill: nothing here needs
to run when the app is closed, and the integrations are per-user-session
(Music.app, Discord, the streamer's machine). Skip.

### BGTaskScheduler / NSBackgroundActivityScheduler
For deferrable periodic work, not persistent connections. Not a fit for live
chat/overlay. (Could fit a future "nightly stats rollup" for ListeningHistory.)

### In-process actors (status quo)
Already gives concurrency isolation with the lowest memory. Best default unless a
service is genuinely crash-prone or its entitlement is worth quarantining.

## Recommendation

If the real goal is **resource use**: do **not** split. Pursue in-process wins
([below](#what-actually-lowers-resource-use)).

If the goal is **stability + sandbox hardening**, split in this order — and only
when the benefit clears the IPC re-architecture cost:

1. **WebSocket + Widget HTTP server → XPC service.** Highest payoff, lowest cost.
   It is the only component that accepts *inbound* connections (largest attack
   surface), couples loosely (one-way pushes), and would run under a lean
   `network.server`-only sandbox. A crash in connection/HTTP handling would no
   longer risk the menu bar.
2. **Discord IPC → XPC service.** Talks an external protocol over a Unix socket
   (parser/framing is the classic "isolate untrusted parsing" case) and carries
   only the `sbpl` socket exception. Medium payoff.
3. **Leave Twitch + Apple Music in-process.** Twitch is deeply wired into the
   song-request/skip-vote/polls pipeline — the NSXPC protocol surface and
   Sendable/`NSSecureCoding` payload conversions would be large and fragile.
   Apple Music is the latency-sensitive data source on a 2s poll; per-poll XPC
   round-trips add overhead for little gain.

### Cost / risk of splitting
- **IPC boundary rewrite.** Today's callback/`AsyncStream` wiring (song providers,
  artwork stream, skip-poll results) must become `@objc` XPC protocols with
  reply blocks; all crossing types must be `NSSecureCoding`/Sendable.
- **Notarization.** Each nested `.xpc` must be signed **inside-out** (sign nested
  bundles first, then the app) with **hardened runtime** (`codesign -o runtime`).
  **Do not** use `--deep --force` — it invalidates nested signatures and the app
  will crash post-notarization. Update `build_release.yml` accordingly.
- **Each `.xpc` needs its own Info.plist + entitlements** and its own container.
- **More memory, not less** (see top).

## What actually lowers resource use

These are cheaper than re-architecting and target the real goal:

- Already good: lazy service start behind feature flags; `PowerStateMonitor`
  reduced poll/broadcast intervals on battery. Keep and extend.
- Fully tear down a service's connections when its feature is toggled off (verify
  EventSub/WS/Discord sockets actually close, not just pause).
- Coalesce/extend timers; prefer event-driven over polling where Music.app's
  distributed notifications already cover it (the 2s poll is a fallback).
- Let App Nap apply when no stream is live (avoid unnecessary
  `ProcessInfo.beginActivity`/sleep assertions unless actively streaming).
- Audit retained artwork/image caches (`ArtworkService`) for eviction pressure.

## Verdict

Process separation is a **stability/security** investment for WolfWave, not a
resource-savings one. The single clear win is isolating the **WebSocket + Widget
HTTP server** as an XPC service. Everything else is either too coupled (Twitch),
latency-sensitive (Apple Music), or better addressed by in-process tuning.

## Sources

- [Creating XPC Services — Apple](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html)
- [XPC · objc.io](https://www.objc.io/issues/14-mac/xpc/)
- [macOS distribution: code signing, notarization (sign inside-out, avoid --deep --force)](https://gist.github.com/rsms/929c9c2fec231f0cf843a1a746a416f5)
