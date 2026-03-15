# WolfWave — Gemini CLI Context

This file provides essential context, architecture overview, and development guidelines for the WolfWave project.

## Project Overview

WolfWave is a native macOS menu bar application that bridges Apple Music with Twitch, Discord, and stream overlays. It uses native Apple frameworks (ScriptingBridge, AppKit, SwiftUI) to provide real-time music integration without external dependencies.

- **Primary Stack**: Swift 5.9+, SwiftUI, AppKit
- **Target OS**: macOS 15.0+
- **IDE**: Xcode 16+
- **Architecture**: MVVM + Service-Oriented with an `NSApplicationDelegateAdaptor` lifecycle.

## Core Architecture

### App Lifecycle (`WolfWaveApp.swift`)
The `AppDelegate` (via `@NSApplicationDelegateAdaptor`) acts as the central orchestrator. It:
- Manages the `NSStatusItem` (menu bar icon).
- Initializes and owns all core services.
- Handles window management (Settings, Onboarding).
- Forwards track updates from `MusicPlaybackMonitor` to Twitch, Discord, and WebSocket services.

### Key Services (`src/wolfwave/Services/`)
- **MusicPlaybackMonitor**: Tracks Apple Music via ScriptingBridge and distributed notifications.
- **TwitchChatService**: Manages Twitch EventSub WebSocket and Helix API for bot commands.
- **DiscordRPCService**: Handles Discord Rich Presence via local IPC Unix domain sockets.
- **WebSocketServerService**: Runs a local server (default port 8765) to power OBS browser source widgets.
- **UpdateCheckerService**: Periodically checks GitHub Releases for updates.
- **KeychainService**: Securely stores API tokens in the macOS Keychain.

### Data Flow
1. `MusicPlaybackMonitor` detects a track change in Apple Music.
2. `AppDelegate` receives the update via delegate pattern.
3. `AppDelegate` pushes the data to:
    - `TwitchChatService` (for `!song` responses).
    - `DiscordRPCService` (for Rich Presence status).
    - `WebSocketServerService` (for OBS widget updates).
    - `ArtworkService` (to fetch album art via iTunes Search API).

## Development Commands

| Command | Description |
| :--- | :--- |
| `make build` | Debug build via `xcodebuild` |
| `make test` | Run unit tests (XCTest) |
| `make prod-build` | Release build + DMG packaging |
| `make open-xcode` | Open the project in Xcode |
| `make update-deps` | Resolve Swift Package Manager dependencies |
| `make clean` | Remove build artifacts |

## Build Configuration

- **API Keys**: All API keys (Twitch Client ID, Discord Client ID) are managed in `src/wolfwave/Config.xcconfig`.
- **Setup**: Copy `Config.xcconfig.example` to `Config.xcconfig` and fill in the required IDs. This file is gitignored.
- **Entitlements**: The app uses App Sandbox with specific entitlements for Apple Music ScriptingBridge and Network/IPC access.

## Coding Conventions

- **Organization**: Use `// MARK: -` sections to organize properties, methods, and delegate extensions.
- **Concurrency**: Prefer `async/await` and `Task` over `DispatchQueue` for new code.
- **Safety**: Avoid force unwrapping (`!`). Use `guard let` or `if let`.
- **UI**: Use SwiftUI for all views. ViewModels should be `ObservableObject` with `@Published` properties.
- **Constants**: All strings, keys, and timing values must be centralized in `AppConstants.swift`.
- **Documentation**: Use DocC-style `///` comments for all public methods and properties.

## Security & Privacy

- **No Secrets in Code**: Never commit API keys or tokens.
- **Keychain**: All sensitive data (Twitch tokens, etc.) must be stored via `KeychainService`.
- **Privacy**: The app includes a `PrivacyInfo.xcprivacy` manifest for Apple's privacy requirements.

## Testing

- **Location**: Tests live in `src/WolfWaveTests/`.
- **Style**: Use `@testable import WolfWave`.
- **Focus**: Prioritize testing pure logic (Bot command parsing, version comparison, state machines).
- **Mocking**: Mock network and system services to keep tests fast and reliable.
