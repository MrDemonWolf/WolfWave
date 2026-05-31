# Process Separation Research — WolfWave Integrations

Status: decided. The app stays **single-process**; the energy work below shipped.
Date: 2026-05-29.

## Question

Can we split integrations (Twitch, Discord, WebSocket/overlay, Apple Music) into
their own processes to (a) lower resource use and (b) let some pieces run in the
background?

## Short answer

**Process separation will not lower resource use. It raises total memory.** Each
extra process loads its own Swift runtime + Foundation + Network.framework
(tens of MB each), and the actual CPU work is unchanged. So for the goal of using
*fewer* resources, splitting is the wrong lever.

"Run in the background" is already handled: WolfWave is a background app
(LSUIElement menu bar) and launches at login via `SMAppService.mainApp`
(`LaunchAtLoginService`). No work today needs a process living *beyond* the app's
own lifetime, so a login daemon/agent is not warranted either.

Decision: keep everything in one process and tune it (below).

## Current state

WolfWave is **one process**. Services are Swift `actor`s / `@MainActor` types
driven by async/await on background QoS — they already do **not** block the UI
thread. Threads are not processes; we already have good concurrency isolation.

Wiring lives in `AppDelegate+Services.swift`. Services start lazily behind feature
flags and throttle on battery via `PowerStateMonitor` (`powerStateChanged`).

## What we did (resource saving)

A teardown audit found no leaks (connections, timers, tasks, and observers are all
released on disable; the `ArtworkService` cache is bounded; no sleep/App-Nap
assertions are held). The real idle-energy lever was **timer-wakeup coalescing**,
which lets macOS batch wakeups instead of firing each on its own schedule:

- `AppleMusicSource`: 20% `leeway` on the fallback poll timer (the always-on one;
  real-time track changes still arrive via the distributed notification).
- WebSocket progress loop: `tolerance` + skip the broadcast when no clients.
- Discord availability poll, song-request auto-advance poll: `tolerance`.
- Twitch reconnect / message-retry backoff + device-code poll: `tolerance`
  (poll tolerance only ever *delays*, so it can't trip Twitch `slow_down`).

Behavior-invisible; backoff/poll cadence is unchanged except for coalescing jitter.

A companion **inside-out signing** fix to `build_release.yml` replaced
`codesign --deep --force` (which strips per-bundle entitlements from nested
bundles) with deepest-first signing + `--preserve-metadata=entitlements`. That is
correct hygiene independent of any process split.

## If a background process is ever genuinely needed

It would be for *new* work that must outlive the app or run with a tighter sandbox
— not the current integrations. Mechanisms, for reference:

- **XPC Service** — bundled `.xpc`, launchd-managed, SIGKILL'd when idle (must be
  near-stateless). Good for crash isolation / privilege separation of *bursty*
  work; a poor fit for always-on connections (keeping them alive defeats idle
  reclamation). Note: nested `.xpc` bundles must be signed **inside-out** with
  hardened runtime — the signing fix above already prepares the pipeline.
- **SMAppService agent/daemon** — for login/outlive-the-app work.
- **BGTaskScheduler / NSBackgroundActivityScheduler** — deferrable periodic work
  (e.g. a future nightly ListeningHistory rollup).

## Verdict

Stay single-process. Resource savings come from in-process tuning (shipped:
timer coalescing), not from spawning helper processes — which would cost more
memory for no resource benefit.

## Sources

- [Creating XPC Services — Apple](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html)
- [XPC · objc.io](https://www.objc.io/issues/14-mac/xpc/)
- [macOS distribution: code signing, notarization (sign inside-out, avoid --deep --force)](https://gist.github.com/rsms/929c9c2fec231f0cf843a1a746a416f5)
