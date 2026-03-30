# WolfWave — Gemini CLI Context

This file provides essential context, architecture overview, and development guidelines for the WolfWave project.

## Project Overview

WolfWave is a native macOS menu bar utility that bridges Apple Music with Twitch, Discord, and stream overlays. It uses native Apple frameworks (ScriptingBridge, AppKit, SwiftUI) to provide real-time music integration without external dependencies.

- **Primary Stack**: Swift 5.9+, SwiftUI, AppKit, macOS 15.0+
- **IDE**: Xcode 16+
- **Architecture**: MVVM + Service-Oriented with an `NSApplicationDelegateAdaptor` lifecycle.
- **Project Structure**: Monorepo managed with Turborepo and Bun.

## Monorepo Structure

- `apps/native`: The core macOS application (Swift/SwiftUI).
- `apps/docs`: The documentation website (Next.js/Fumadocs).
- `apps/marketing/wolfwave-announcement`: Remotion-based marketing and announcement assets.

## Core Architecture (apps/native)

### App Lifecycle (`WolfWaveApp.swift`)
The `AppDelegate` (via `@NSApplicationDelegateAdaptor`) acts as the central orchestrator. It:
- Manages the `NSStatusItem` (menu bar icon).
- Initializes and owns all core services.
- Handles window management (Settings, Onboarding).
- Forwards track updates from `MusicPlaybackMonitor` to Twitch, Discord, and WebSocket services.
- Rebuilds the system tray menu dynamically via `NSMenuDelegate` with real-time state.

### Source Layout (`apps/native/wolfwave/`)

- **Core/**: 
    - `AppConstants.swift`: Centralized config enums for keys, identifiers, and timing.
    - `KeychainService.swift`: macOS Security framework wrapper for secure token storage.
    - `Logger.swift`: Structured logging with emoji prefixes, file rotation (5MB cap), and PII redaction.
    - `PowerStateMonitor.swift`: Adapts polling intervals based on system power mode and thermal pressure.
- **Monitors/**:
    - `MusicPlaybackMonitor.swift`: Tracks Apple Music via ScriptingBridge, distributed notifications, and fallback polling (**Sync Music**).
- **Services/**:
    - `Twitch/`: `TwitchChatService.swift` (EventSub WebSocket + Helix chat API) and `TwitchDeviceAuth.swift` (OAuth Device Code flow).
    - `Twitch/Commands/`: `BotCommand` protocol and concrete implementations like `SongCommand` and `LastSongCommand`.
    - `Discord/`: `DiscordRPCService.swift` (**Discord Status** via local IPC Unix domain socket, iTunes Search API artwork fetching).
    - `WebSocket/`: `WebSocketServerService.swift` (port 8765) and `WidgetHTTPService.swift` (port 8766) for **Stream Widgets**.
    - `UpdateChecker/`: `SparkleUpdaterService.swift` (Sparkle framework wrapper for auto-updates) and `UpdateCheckerService.swift` (GitHub Releases API version checker).
    - `ArtworkService.swift`: Shared utility for fetching high-quality album art via iTunes API.
- **Views/**: SwiftUI settings with `NavigationSplitView` sidebar and card-based sections.
- **Views/Onboarding/**: 4-step guided setup wizard (Welcome, Twitch, Discord, OBS Widget).

### Data Flow
1. `MusicPlaybackMonitor` detects a track change in Apple Music.
2. `AppDelegate` receives the update via delegate pattern.
3. `AppDelegate` pushes the data to:
    - `TwitchChatService` (for `!song` chat responses).
    - `DiscordRPCService` (for Discord Status updates).
    - `WebSocketServerService` (for Stream Widget overlays).
    - `ArtworkService` (to fetch album art for widgets and Discord).

## User Experience Guidelines

- **Tone**: Use friendly, non-technical language. Avoid jargon like "IPC", "WebSocket", "Rich Presence", or "Listener".
- **Terminology**: 
    - Use **Sync Music** instead of "Music Tracking".
    - Use **Discord Status** instead of "Discord Presence".
    - Use **Stream Widgets** instead of "Stream Overlay" or "WebSocket Server".
- **Clarity**: Use distinct, benefit-driven headers.
- **Accessibility**: Ensure all UI elements have `accessibilityLabel` and `accessibilityIdentifier` for UI testing.
- **Onboarding**: The app is designed to be "dummy-friendly". Onboarding and empty states should guide the user clearly.

## Development Commands

### Monorepo (Bun + Turbo)
| Command | Description |
| :--- | :--- |
| `bun install` | Install all workspace dependencies |
| `bun dev` | Start all dev servers via Turbo |
| `bun run build` | Build all apps in the monorepo |
| `bun run dev --filter docs` | Start docs dev server only |
| `bun run dev --filter wolfwave-announcement` | Open Remotion studio for marketing videos |

### Native App (Make)
| Command | Description |
| :--- | :--- |
| `make build` | Debug build of the macOS app |
| `make clean` | Remove build artifacts |
| `make test` | Run unit tests (XCTest) |
| `make test-verbose` | Run tests with full output |
| `make test-ci` | Run tests in CI mode (no signing) |
| `make open-xcode` | Open the Xcode project |
| `make prod-build` | Release build + DMG packaging (`builds/`) |
| `make notarize` | Notarize the production DMG (requires env vars) |

## Build Configuration

- **API Keys**: All API keys (Twitch Client ID, Discord Client ID) are managed in `apps/native/wolfwave/Config.xcconfig`.
- **Setup**: Copy `Config.xcconfig.example` to `Config.xcconfig` and fill in the required IDs. This file is gitignored.
- **Entitlements**: The app uses App Sandbox with specific entitlements for Apple Music ScriptingBridge and Network/IPC access.
- **Sparkle**: EdDSA (Ed25519) signing for update verification. Public key in `Info.plist` as `SUPublicEDKey`.

## Documentation Website (`apps/docs/`)

- **Tech Stack**: Fumadocs (Next.js).
- **Asset Utility**: `apps/docs/lib/utils.ts` contains `getAssetPath` for base-path compatibility on GitHub Pages.
- **Service Worker**: A dummy `sw.js` in `apps/docs/public` prevents 404 errors.

## Marketing Assets (`apps/marketing/`)

- **Remotion**: React-based video generation for launch announcements.
- **SEO**: Marketing copy in `Marketing.md` is optimized for terms like "Apple Music Twitch Bot" and "Discord Status Apple Music".

## Testing

- **Location**: `apps/native/WolfWaveTests/`.
- **Style**: Use `@testable import WolfWave`.
- **Focus**: Prioritize testing pure logic (Bot command parsing, version comparison, state machines).
- **Mocking**: Mock network and system services to keep tests fast and reliable.
