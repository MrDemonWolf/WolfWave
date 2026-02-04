# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

WolfWave is a macOS menu bar app that connects Apple Music with Twitch. It tracks the currently playing song via ScriptingBridge and broadcasts it to Twitch chat via bot commands (EventSub + Helix API), with optional WebSocket streaming to external overlays.

**Stack**: Swift 5.9+, SwiftUI, AppKit, macOS 12.0+, Xcode 15+. Zero external dependencies — all functionality uses native Apple frameworks.

## Build & Development Commands

```bash
make build          # Debug build via xcodebuild
make clean          # Clean build artifacts
make test           # Run tests (if test target exists)
make update-deps    # Resolve SwiftPM dependencies
make open-xcode     # Open Xcode project
make ci             # CI-friendly build (alias for build)
make prod-build     # Release build → DMG in builds/
make prod-install   # Release build → install to /Applications
make env-check      # Check required environment configuration
```

Xcode project is at `src/wolfwave.xcodeproj` with scheme `WolfWave`. Build and run with Cmd+R in Xcode.

## Build Configuration

`Config.xcconfig` holds `TWITCH_CLIENT_ID` and is **not committed** (gitignored). Copy from `Config.xcconfig.example` and fill in your Twitch Client ID. The value is expanded into `Info.plist` at build time via `$(TWITCH_CLIENT_ID)`.

## Architecture

**Pattern**: MVVM + Service-Oriented, with an NSApplicationDelegateAdaptor-based lifecycle.

### Core flow

`WolfWaveApp.swift` → AppDelegate manages the menu bar status item, initializes services (MusicPlaybackMonitor, TwitchChatService), handles settings window lifecycle, and wires song info callbacks into the Twitch service.

### Source layout (`src/wolfwave/`)

- **Core/** — `AppConstants.swift` (centralized config enums for keys, identifiers, timing), `KeychainService.swift` (macOS Security framework wrapper), `Logger.swift` (structured logging)
- **Monitors/** — `MusicPlaybackMonitor.swift` (ScriptingBridge + distributed notifications + 2s fallback polling, delegate pattern via `MusicPlaybackMonitorDelegate`)
- **Services/Twitch/** — `TwitchChatService.swift` (EventSub WebSocket + Helix chat API, thread-safe with NSLock, network path monitoring for reconnection), `TwitchDeviceAuth.swift` (OAuth Device Code flow)
- **Services/Twitch/Commands/** — `BotCommand` protocol (`triggers`, `description`, `execute(message:) -> String?`), concrete commands (`SongCommand`, `LastSongCommand`), `BotCommandDispatcher` for routing
- **Views/** — SwiftUI settings with `NavigationSplitView` sidebar; sections: Music Monitor, App Visibility, WebSocket, Twitch, Advanced. `TwitchViewModel` is the main observable for auth/connection state.

### Key patterns

- **Credentials**: All tokens/secrets stored via `KeychainService` (never UserDefaults). Keys defined in `AppConstants.Keychain`.
- **Settings**: User preferences in `UserDefaults` via `@AppStorage`. Keys centralized in `AppConstants.UserDefaults`.
- **Notifications**: Loose coupling via `NotificationCenter` (e.g., `TrackingSettingChanged`, `DockVisibilityChanged`). Names in `AppConstants.Notifications`.
- **Thread safety**: `NSLock` for shared state mutations in `TwitchChatService`.
- **Bot commands**: Register new commands in `BotCommandDispatcher.registerDefaultCommands()`. Each command implements `BotCommand` protocol. Max response 500 chars, target <100ms execution.

## Code Conventions

- Swift 5.9+ with async/await concurrency (no DispatchQueue for new async work)
- MARK sections organize every file (Properties, Public Methods, Private Helpers, etc.)
- DocC-style `///` comments on all public APIs
- No force unwrapping — use optionals and guard
- MVVM for views: ViewModels as `ObservableObject` with `@Published` properties
- Prefer structs for data models, classes for services
- camelCase for variables/functions, PascalCase for types
