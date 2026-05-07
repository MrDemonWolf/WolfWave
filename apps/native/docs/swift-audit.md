# Swift Audit — Phase 2a: Concurrency

**Date:** 2026-05-07
**Scope:** `apps/native/wolfwave/{Services,Core,Monitors}/**/*.swift`
**Target:** Swift 6 + Approachable Concurrency (Swift 6.2 default-MainActor isolation, `-strict-concurrency=complete`) on macOS 26.0+

## Current build state

- `SWIFT_VERSION = 5.0` (xcodeproj 4 occurrences)
- No `SWIFT_STRICT_CONCURRENCY` flag set → minimal warnings
- ViewModels already migrated to `@Observable` / `@Bindable` ✅
- No `ObservableObject` / `@Published` leftovers ✅
- No deprecated `NavigationView` or two-param `onChange` ✅
- No `try!` or force-unwraps ✅

## Concurrency findings (HIGH severity)

### NSLock proliferation — actor candidates

`Services/Twitch/TwitchChatService.swift` (1834 LOC, 12 locks):
- :109 `webSocketLock`
- :130 `credentialsLock`
- :212 `connectionLock`
- :225 `disconnectLock`
- :230 `networkMonitorLock` + :231 `networkMonitorQueue` (DispatchQueue)
- :237 `networkReachableLock`
- :250 `reconnectionLock`
- :261 `sessionTimerLock`
- :292 `rateLimitLock`
- :297 `requestQueueLock`
- :302 `queueProcessingLock`
- :956 `pendingMessagesLock`
→ Refactor to **`actor TwitchChatService`** with isolated state. URLSessionWebSocket delegate callbacks bridge via `nonisolated` + `Task { await self.... }`.

`Services/Discord/DiscordRPCService.swift` (802 LOC):
- :89 `callbackLock`
- :103 `ipcQueue` (serial DispatchQueue)
- :124 `enabledLock`
→ **`actor DiscordRPCService`**. IPC socket reads via async `FileHandle` or wrap in `nonisolated` socket task feeding `AsyncStream`.

`Services/WebSocket/WebSocketServerService.swift` (519 LOC):
- :36 `connectionsLock`, :37 `serverQueue`, :42 `enabledLock`, :55 `playbackLock`
→ **`actor WebSocketServerService`**.

`Services/Twitch/Commands/CooldownManager.swift:29` `lock` → trivial `actor`.
`Services/Twitch/Commands/TrackInfoCommand.swift:22` `lock` → `actor` or `@MainActor`.
`Services/Twitch/Commands/BotCommandDispatcher.swift:16` `lock` → `actor`.
`Services/SongRequest/SongBlocklist.swift:16` `lock` → `actor`.
`Services/SongRequest/SongRequestQueue.swift:28` `lock` (also `@Observable`) → keep `@Observable`, mark `@MainActor` since it drives UI.
`Monitors/AppleMusicSource.swift:41` `trackingLock` + :45 `backgroundQueue` → `actor`.
`Core/Logger.swift:65,82` `osLoggerLock` + `fileQueue` → drop NSLock; `os.Logger` is already thread-safe; file writes go through `actor LogFileWriter` or just use async `FileHandle`.

### `@unchecked Sendable` — masks issues

- `Services/ArtworkService.swift:30`
- `Services/WebSocket/WebSocketServerService.swift:18`
- `Services/Discord/DiscordRPCService.swift:39`
- `Services/Twitch/TwitchChatService.swift:41`
→ Remove all four after actor migration. They are workarounds, not solutions.

### DispatchQueue.main.async / asyncAfter (30 occurrences)

Replace pattern with `Task { @MainActor in ... }` or, under default-MainActor isolation, just direct calls. Examples:
- `Services/Twitch/TwitchChatService.swift:854,929,1365`
- `Services/Discord/DiscordRPCService.swift:63,188,193,201,258`
- `Services/UpdateChecker/SparkleUpdaterService.swift:205,223`
- `Services/WebSocket/WebSocketServerService.swift:510`
- `Monitors/AppleMusicSource.swift:132,139`
- `Services/SongRequest/AppleMusicController.swift:309` (`asyncAfter` 0.15s) → `try await Task.sleep(for: .milliseconds(150))`

### `DispatchQueue.global().asyncAfter` → `Task.sleep`

- `TwitchChatService.swift:384,511,1065`

### Timer.scheduledTimer → Task loop

- `TwitchChatService.swift:1367` — wrap in `Task { while !Task.isCancelled { try await Task.sleep(...); ... } }`. Store handle for cancel.

### URLSession completion handlers → async

- `Services/ArtworkService.swift:128` (`dataTask`)
- `Services/Twitch/TwitchChatService.swift:1284, 1678` (`dataTask`)
- Public APIs with `completion: @escaping`: `ArtworkService.fetchArtworkURL`, `ArtworkService.fetchTrackLinks`, `DiscordRPCService.testConnection`, `TwitchChatService` request helper at :1244
→ Convert to `async throws -> T` using `URLSession.shared.data(for:)`.

### NotificationCenter selector-based observer

- `Monitors/AppleMusicSource.swift:187` `DistributedNotificationCenter.default().addObserver(self, selector:...)` → AsyncSequence:
```swift
let stream = DistributedNotificationCenter.default()
    .notifications(named: name)
observerTask = Task { for await note in stream { handle(note) } }
```
Drops the `@objc` shim and integrates with structured cancellation.

## Migration plan

1. **Flip language mode** — `SWIFT_VERSION = 6.0`, `SWIFT_STRICT_CONCURRENCY = complete`, opt into Swift 6.2 features: `SWIFT_UPCOMING_FEATURE_DEFAULT_ISOLATION_MAIN_ACTOR = YES` (or `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). Build will explode; that's the point.
2. **Trivial actors first** — CooldownManager, TrackInfoCommand, BotCommandDispatcher, SongBlocklist, AppleMusicSource. Each is small + self-contained.
3. **Logger** — drop NSLock + fileQueue; switch to actor for file I/O, keep `os.Logger` direct.
4. **Mid services** — WebSocketServerService, ArtworkService, SongRequestQueue.
5. **Big services** — DiscordRPCService, then TwitchChatService (last; biggest delegate-callback surface).
6. **API conversions** — completion-handler → async throughout.
7. **Remove all `@unchecked Sendable`**.
8. **Verify** — `make test` (215 tests) green; smoke-test app.

## PR slicing

Plan calls for one phase = one PR. Given the size, slice further:

- **PR-2a-1**: build flags flip + trivial actors (CooldownManager, TrackInfoCommand, BotCommandDispatcher, SongBlocklist, Logger fileQueue) + URLSession async migration in ArtworkService.
- **PR-2a-2**: AppleMusicSource actor + AsyncSequence notifications + DispatchQueue.main.async cleanups in monitors.
- **PR-2a-3**: WebSocketServerService actor + WidgetHTTPService cleanup.
- **PR-2a-4**: DiscordRPCService actor + completion → async.
- **PR-2a-5**: TwitchChatService actor (largest, dedicated PR).
- **PR-2a-6**: Remove all `@unchecked Sendable` once preceding PRs land cleanly under strict-concurrency complete.

Phases 2b (UI/Observation) + 2c (quality+security) follow on the new baseline.
