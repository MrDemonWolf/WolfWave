# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

WolfWave is a native macOS menu bar app that bridges Apple Music with Twitch, Discord, and stream overlays. It tracks the currently playing song via ScriptingBridge and broadcasts it to Twitch chat via bot commands (EventSub + Helix API), shows "Listening to Apple Music" on Discord via Rich Presence, and streams now-playing data to overlays via WebSocket.

**Stack**: Swift 5.9+, SwiftUI, AppKit, macOS 26.0+, Xcode 16+. Minimal dependencies (Sparkle for auto-updates) — all other functionality uses native Apple frameworks.

**Monorepo**: bun workspaces + Turborepo. The root `package.json` defines workspaces (`apps/*`, `apps/marketing/*`) and Turbo orchestrates `dev`, `build`, and `clean` tasks across packages.

## Build & Development Commands

### Monorepo (bun + Turborepo)

```bash
bun install                              # Install all workspace dependencies
bun dev                                  # Start all dev servers via Turbo
bun run dev --filter docs                # Start docs dev server only
bun run dev --filter wolfwave-announcement  # Open Remotion studio only
bun run build --filter docs              # Build docs site
```

### Native App (Make)

```bash
make build          # Debug build via xcodebuild
make clean          # Clean build artifacts
make test           # Run unit tests (215 tests across 20 test files)
make update-deps    # Resolve SwiftPM dependencies
make open-xcode     # Open Xcode project
make ci             # CI-friendly build (alias for build)
make prod-build     # Release build → DMG in builds/
make prod-install   # Release build → install to /Applications
make notarize       # Notarize the DMG (requires Developer ID + env vars)
```

Xcode project is at `apps/native/wolfwave.xcodeproj` with scheme `WolfWave`. Build and run with Cmd+R in Xcode.

## Build Configuration

`Config.xcconfig` holds `TWITCH_CLIENT_ID` and `DISCORD_CLIENT_ID` and is **not committed** (gitignored). Copy from `Config.xcconfig.example` and fill in your keys. Values are expanded into `Info.plist` at build time.

`Info.plist` also contains `SUPublicEDKey` (Sparkle EdDSA public key) and `SUFeedURL` (appcast URL). These are committed and should not be modified unless rotating the Sparkle signing key.

## Architecture

**Pattern**: MVVM + Service-Oriented, with an NSApplicationDelegateAdaptor-based lifecycle.

### Core flow

`WolfWaveApp.swift` → AppDelegate manages the menu bar status item, initializes services (MusicPlaybackMonitor, TwitchChatService, DiscordRPCService, UpdateCheckerService), handles settings window lifecycle, and wires song info callbacks into the Twitch and Discord services. The system tray menu is dynamic (rebuilt via `NSMenuDelegate` on each open) with now-playing info, quick toggles, and conditional items.

### Source layout (`apps/native/wolfwave/`)

- **Core/** — `AppConstants.swift` (centralized config enums for keys, identifiers, timing), `KeychainService.swift` (macOS Security framework wrapper), `Logger.swift` (structured logging)
- **Monitors/** — `MusicPlaybackMonitor.swift` (ScriptingBridge + distributed notifications + 2s fallback polling, delegate pattern via `MusicPlaybackMonitorDelegate`)
- **Services/Twitch/** — `TwitchChatService.swift` (EventSub WebSocket + Helix chat API, thread-safe with NSLock, network path monitoring for reconnection, Twitch user ID redacted in logs), `TwitchDeviceAuth.swift` (OAuth Device Code flow)
- **Services/Twitch/Commands/** — `BotCommand` protocol (`triggers`, `description`, `execute(message:) -> String?`), concrete commands (`SongCommand`, `LastSongCommand`), `BotCommandDispatcher` for routing
- **Services/Discord/** — `DiscordRPCService.swift` (Discord Rich Presence via local IPC Unix domain socket, iTunes Search API artwork fetching with cache, auto-reconnect with backoff)
- **Services/UpdateChecker/** — `UpdateCheckerService.swift` (GitHub Releases API version checker, semantic version comparison, Homebrew/DMG install detection, 24h periodic checking), `SparkleUpdaterService.swift` (Sparkle framework wrapper for auto-updates, EdDSA-signed appcast verification, DEBUG mode allows manual check via dev-appcast.xml)
- **Views/** — SwiftUI settings with `NavigationSplitView` sidebar; sections: Music Monitor, App Visibility, Stream Overlay, Twitch, Discord, Advanced. `TwitchViewModel` is the main observable for auth/connection state.
- **Views/Onboarding/** — First-launch onboarding wizard (4-step: Welcome, Twitch, Discord, OBS Widget). Window size: 600x480.
- **Views/Shared/** — Shared UI components (e.g., `TwitchGlitchShape`)

### Key patterns

- **Credentials**: All tokens/secrets stored via `KeychainService` (never UserDefaults). Keys defined in `AppConstants.Keychain`.
- **Settings**: User preferences in `UserDefaults` via `@AppStorage`. Keys centralized in `AppConstants.UserDefaults`. Note: `currentSongCommandEnabled`, `lastSongCommandEnabled`, and `widgetHTTPEnabled` all default to `false`.
- **Notifications**: Loose coupling via `NotificationCenter` (e.g., `TrackingSettingChanged`, `DockVisibilityChanged`). Names in `AppConstants.Notifications`.
- **Thread safety**: `NSLock` for shared state mutations in `TwitchChatService`, `DiscordRPCService`, and `UpdateCheckerService`. Logger uses a serial `DispatchQueue` for thread-safe file I/O.
- **Bot commands**: Register new commands in `BotCommandDispatcher.registerDefaultCommands()`. Each command implements `BotCommand` protocol. Max response 500 chars, target <100ms execution.
- **Discord IPC**: Unix domain socket at `$TMPDIR/discord-ipc-{0..9}`. SBPL entitlements enable socket access within App Sandbox.
- **ADHD-friendly text**: All user-facing text should be short, punchy, and jargon-free.

## Testing

Unit tests live in `apps/native/WolfWaveTests/` and use XCTest with `@testable import WolfWave`. The test target is a hosted unit test bundle (`TEST_HOST` = WolfWave.app).

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
- Test files are auto-discovered via `PBXFileSystemSynchronizedRootGroup` — just add `.swift` files to `apps/native/WolfWaveTests/`
- Focus on pure logic (version comparison, command matching, state machines) — avoid tests that need AppDelegate, Keychain, or network

## CI/CD

- `.github/workflows/ci.yml` — Runs `xcodebuild test` on every push/PR to `main`. Creates placeholder `Config.xcconfig` for CI builds.
- `.github/workflows/release.yml` — Builds, signs, notarizes, and creates a GitHub Release on tag push (`v*`). Required secrets: `DEVELOPER_ID_CERT_P12`, `DEVELOPER_ID_CERT_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`, `TWITCH_CLIENT_ID`, `DISCORD_CLIENT_ID`, `SPARKLE_PRIVATE_KEY`.

### Sparkle Auto-Updates

Sparkle uses EdDSA (Ed25519) signing for update verification. The public key is in `Info.plist` as `SUPublicEDKey`. The private key is stored in the developer's macOS Keychain and as the `SPARKLE_PRIVATE_KEY` GitHub secret for CI.

- **DEBUG builds**: Sparkle initializes but automatic checks are disabled. Manual "Check Now" works and reads the bundled `dev-appcast.xml` (dummy v99.0.0 entry).
- **Release builds**: Sparkle checks the remote appcast at the `SUFeedURL` in Info.plist.
- **Homebrew installs**: Sparkle is fully disabled (updates managed by Homebrew).
- **Key management**: Run `generate_keys` from Sparkle's tools to view/export/import keys. The tool is at `SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys` in DerivedData.

## Documentation

Docs site built with Fumadocs (Next.js) at `apps/docs/`. Content in `apps/docs/content/docs/` as `.mdx` files. Sidebar defined in `apps/docs/content/docs/meta.json` with Guide/Developers sections. Deployed to GitHub Pages. Run with `bun run dev --filter docs` from root.

## Marketing

Remotion-based video projects live in `apps/marketing/`. Each subfolder is a standalone Remotion project (React + TypeScript) for producing announcement/promo videos.

- **wolfwave-announcement** — v1.0 launch announcement video. Run `bun run dev --filter wolfwave-announcement` from root to open the Remotion editor.

## Code Conventions

- Swift 5.9+ with async/await concurrency (no DispatchQueue for new async work)
- MARK sections organize every file (Properties, Public Methods, Private Helpers, etc.)
- DocC-style `///` comments on all public APIs
- No force unwrapping — use optionals and guard
- MVVM for views: ViewModels use `@Observable` macro (migrated from `ObservableObject`/`@Published`)
- Prefer structs for data models, classes for services
- camelCase for variables/functions, PascalCase for types
