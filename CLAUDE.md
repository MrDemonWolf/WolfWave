# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

WolfWave is a native macOS menu bar app that bridges Apple Music with Twitch, Discord, and stream overlays. It tracks the currently playing song via ScriptingBridge and broadcasts it to Twitch chat via bot commands (EventSub + Helix API), shows "Listening to Apple Music" on Discord via Rich Presence, and streams now-playing data to overlays via WebSocket.

**Stack**: Swift 5.9+, SwiftUI, AppKit, macOS 15.0+, Xcode 16+. Minimal dependencies (Sparkle for auto-updates) — all other functionality uses native Apple frameworks.

## Build & Development Commands

```bash
make build          # Debug build via xcodebuild
make clean          # Clean build artifacts
make test           # Run unit tests (210 tests across 16 test files)
make update-deps    # Resolve SwiftPM dependencies
make open-xcode     # Open Xcode project
make ci             # CI-friendly build (alias for build)
make prod-build     # Release build → DMG in builds/
make prod-install   # Release build → install to /Applications
make notarize       # Notarize the DMG (requires Developer ID + env vars)
```

Xcode project is at `src/wolfwave.xcodeproj` with scheme `WolfWave`. Build and run with Cmd+R in Xcode.

## Build Configuration

`Config.xcconfig` holds `TWITCH_CLIENT_ID` and `DISCORD_CLIENT_ID` and is **not committed** (gitignored). Copy from `Config.xcconfig.example` and fill in your keys. Values are expanded into `Info.plist` at build time.

## Architecture

**Pattern**: MVVM + Service-Oriented, with an NSApplicationDelegateAdaptor-based lifecycle.

### Core flow

`WolfWaveApp.swift` → AppDelegate manages the menu bar status item, initializes services (MusicPlaybackMonitor, TwitchChatService, DiscordRPCService, UpdateCheckerService), handles settings window lifecycle, and wires song info callbacks into the Twitch and Discord services.

### Source layout (`src/wolfwave/`)

- **Core/** — `AppConstants.swift` (centralized config enums for keys, identifiers, timing), `KeychainService.swift` (macOS Security framework wrapper), `Logger.swift` (structured logging)
- **Monitors/** — `MusicPlaybackMonitor.swift` (ScriptingBridge + distributed notifications + 2s fallback polling, delegate pattern via `MusicPlaybackMonitorDelegate`)
- **Services/Twitch/** — `TwitchChatService.swift` (EventSub WebSocket + Helix chat API, thread-safe with NSLock, network path monitoring for reconnection), `TwitchDeviceAuth.swift` (OAuth Device Code flow)
- **Services/Twitch/Commands/** — `BotCommand` protocol (`triggers`, `description`, `execute(message:) -> String?`), concrete commands (`SongCommand`, `LastSongCommand`), `BotCommandDispatcher` for routing
- **Services/Discord/** — `DiscordRPCService.swift` (Discord Rich Presence via local IPC Unix domain socket, iTunes Search API artwork fetching with cache, auto-reconnect with backoff)
- **Services/UpdateChecker/** — `UpdateCheckerService.swift` (GitHub Releases API version checker, semantic version comparison, Homebrew/DMG install detection, 24h periodic checking)
- **Views/** — SwiftUI settings with `NavigationSplitView` sidebar; sections: Music Monitor, App Visibility, WebSocket, Twitch, Discord, Advanced. `TwitchViewModel` is the main observable for auth/connection state.
- **Views/Onboarding/** — First-launch onboarding wizard (3-step: Welcome, Twitch, Discord)
- **Views/Shared/** — Shared UI components (e.g., `TwitchGlitchShape`)

### Key patterns

- **Credentials**: All tokens/secrets stored via `KeychainService` (never UserDefaults). Keys defined in `AppConstants.Keychain`.
- **Settings**: User preferences in `UserDefaults` via `@AppStorage`. Keys centralized in `AppConstants.UserDefaults`.
- **Notifications**: Loose coupling via `NotificationCenter` (e.g., `TrackingSettingChanged`, `DockVisibilityChanged`). Names in `AppConstants.Notifications`.
- **Thread safety**: `NSLock` for shared state mutations in `TwitchChatService`, `DiscordRPCService`, and `UpdateCheckerService`.
- **Bot commands**: Register new commands in `BotCommandDispatcher.registerDefaultCommands()`. Each command implements `BotCommand` protocol. Max response 500 chars, target <100ms execution.
- **Discord IPC**: Unix domain socket at `$TMPDIR/discord-ipc-{0..9}`. SBPL entitlements enable socket access within App Sandbox.

## Testing

Unit tests live in `src/WolfWaveTests/` and use XCTest with `@testable import WolfWave`. The test target is a hosted unit test bundle (`TEST_HOST` = WolfWave.app).

### Test files

- `UpdateCheckerServiceTests.swift` — Version comparison (semver edge cases), install method detection
- `SongCommandTests.swift` — Trigger matching, case insensitivity, enable/disable, response truncation
- `LastSongCommandTests.swift` — Same patterns for `!last`/`!lastsong`/`!prevsong` triggers
- `BotCommandDispatcherTests.swift` — Message routing, callback wiring, length guards, whitespace handling
- `OnboardingViewModelTests.swift` — Step navigation, boundary conditions, UserDefaults persistence
- `TwitchViewModelTests.swift` — AuthState/IntegrationState enums, computed properties, cancelOAuth
- `AppConstantsTests.swift` — Constant values, URL validity, dimension bounds, cross-references

### Writing tests

- Use `@testable import WolfWave` (module name matches `PRODUCT_NAME`)
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` applies to test classes too — XCTest runs on main thread
- Test files are auto-discovered via `PBXFileSystemSynchronizedRootGroup` — just add `.swift` files to `src/WolfWaveTests/`
- Focus on pure logic (version comparison, command matching, state machines) — avoid tests that need AppDelegate, Keychain, or network

## CI/CD

- `.github/workflows/ci.yml` — Runs `xcodebuild test` on every push/PR to `main`. Creates placeholder `Config.xcconfig` for CI builds.
- `.github/workflows/release.yml` — Builds, signs, notarizes, and creates a GitHub Release on tag push (`v*`). Required secrets: `DEVELOPER_ID_CERT_P12`, `DEVELOPER_ID_CERT_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`, `TWITCH_CLIENT_ID`, `DISCORD_CLIENT_ID`.

## Documentation

Docs site built with Fumadocs (Next.js) at `docs/`. Content in `docs/content/docs/` as `.mdx` files. Sidebar defined in `docs/content/docs/meta.json` with Guide/Developers sections. Deployed to GitHub Pages.

## Code Conventions

- Swift 5.9+ with async/await concurrency (no DispatchQueue for new async work)
- MARK sections organize every file (Properties, Public Methods, Private Helpers, etc.)
- DocC-style `///` comments on all public APIs
- No force unwrapping — use optionals and guard
- MVVM for views: ViewModels as `ObservableObject` with `@Published` properties
- Prefer structs for data models, classes for services
- camelCase for variables/functions, PascalCase for types
