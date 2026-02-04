# WolfWave - Apple Music + Twitch Companion 🎵

![WolfWave Banner](banner.jpg)

WolfWave is a professional-grade macOS menu bar utility designed to connect Apple Music with your audience. Effortlessly broadcast real-time song data to overlays via WebSockets and interact with your Twitch community through secure, automated chat commands.

## Features

- **Real-time Now Playing**: Tracks the current Apple Music song and updates instantly using ScriptingBridge.
- **Twitch Chat Integration**: Responds to `!song`, `!currentsong`, and `!nowplaying` using modern EventSub + Helix (no IRC).
- **WebSocket Streaming**: Broadcast now-playing data to your overlay or tools (ws:// or wss://).
- **Secure by Default**: All credentials stored in macOS Keychain; no plain-text tokens.
- **Professional Codebase**: Comprehensive documentation, MARK sections, and clean architecture throughout.

## Getting Started

To use WolfWave on macOS, follow these simple steps:

1. Clone the repository:

   ```bash
   git clone https://github.com/MrDemonWolf/WolfWave.git
   cd WolfWave
   ```

2. Configure your Twitch Client ID:

   ```bash
   cp src/wolfwave/Config.xcconfig.example src/wolfwave/Config.xcconfig
   ```

   Open `src/wolfwave/Config.xcconfig` and set your Twitch Client ID:

   ```
   TWITCH_CLIENT_ID = your_client_id_here
   ```

   Create a Twitch application at [dev.twitch.tv/console/apps](https://dev.twitch.tv/console/apps) to get a Client ID. This is a public identifier (not a secret) that gets baked into the app at build time via `Info.plist`.

   > `Config.xcconfig` is gitignored — each contributor uses their own.

3. Open the project:

   ```bash
   make open-xcode
   # or
   open src/wolfwave.xcodeproj
   ```

4. Build and run from Xcode (⌘R)

## Usage

WolfWave is user-friendly and runs from your macOS menu bar. Here's a quick guide to the basic features:

- Menu bar icon shows your current track.
- Toggle Apple Music tracking on/off.
- Configure WebSocket streaming (endpoint + optional JWT).
- Connect your Twitch bot via secure device auth.
- Chat commands supported: `!song`, `!currentsong`, `!nowplaying`.

## Change Log

See Releases for updates and changes:

- https://github.com/MrDemonWolf/WolfWave/releases

## Development

### Prerequisites

- macOS 12.0+
- Xcode 15.0+
- Swift 5.9+
- Command Line Tools: `xcode-select --install`

### Setup

1. Fork and clone the repository
2. Copy `src/wolfwave/Config.xcconfig.example` to `src/wolfwave/Config.xcconfig` and set your Twitch Client ID
3. Open the project: `make open-xcode`
4. Resolve dependencies: `make update-deps`

### Development Commands

- `make build` — Debug build
- `make clean` — Clean build artifacts
- `make test` — Run tests (if configured)
- `make update-deps` — Resolve SwiftPM dependencies
- `make open-xcode` — Open the Xcode project
- `make ci` — CI-friendly build
- `make prod-build TWITCH_CLIENT_ID=your_id` — Release build with DMG in `builds/`
- `make prod-install TWITCH_CLIENT_ID=your_id` — Release build and install to `/Applications`

### Code Quality

This project follows Swift best practices with professional-grade documentation:

- **Swift 5.9+** with modern concurrency (async/await)
- **SwiftUI** for user interfaces
- **Comprehensive Documentation**: DocC-style comments throughout with usage examples
- **MARK Sections**: All files organized with clear section markers for easy navigation
- **Separation of Concerns**: Clean architecture across Core/Services/Views/Monitors
- **Secure Credential Storage**: macOS Keychain for all sensitive data
- **ScriptingBridge Integration**: Direct Apple Music communication without spawning subprocesses
- **Robust Error Handling**: Typed errors with localized descriptions
- **Type Safety**: Strongly typed models for all data structures

### Project Structure

```
wolfwave/
├── Core/                    # Core utilities and services
│   ├── KeychainService.swift    # Secure credential storage (Keychain API)
│   └── Logger.swift             # Centralized logging with categories
├── Monitors/                # Music playback monitoring
│   └── MusicPlaybackMonitor.swift  # ScriptingBridge-based Apple Music integration
├── Services/                # External service integrations
│   └── Twitch/
│       ├── TwitchChatService.swift     # EventSub WebSocket + Helix API
│       ├── TwitchDeviceAuth.swift      # OAuth Device Code flow
│       └── Commands/                   # Bot command system
│           ├── BotCommand.swift        # Command protocol
│           ├── BotCommandDispatcher.swift  # Command routing
│           └── SongCommand.swift       # !song command implementation
├── Views/                   # SwiftUI views
│   ├── SettingsView.swift       # Main settings interface
│   └── Twitch/
│       ├── TwitchSettingsView.swift   # Twitch bot configuration UI
│       └── TwitchViewModel.swift      # Twitch state management
└── Resources/              # Assets and resources
    └── Assets.xcassets/
```

**Architecture Highlights:**

- **MARK Sections**: Every file uses clear section markers (Properties, Public Methods, Private Helpers, etc.)
- **Documentation**: Comprehensive DocC-style comments with parameter/return documentation
- **Delegation Pattern**: `MusicPlaybackMonitorDelegate` for track updates
- **MVVM**: ViewModels separate UI logic from business logic
- **Async/Await**: Modern Swift concurrency throughout

### Twitch Chat Bot

The bot is implemented with `TwitchChatService` using Twitch Helix + EventSub (no IRC).

**Features:**

- **EventSub WebSocket**: Real-time chat message notifications
- **OAuth Device Code Flow**: Secure authentication via `TwitchDeviceAuth`
- **Token Validation**: Automatic token validation on app launch
- **Command System**: Extensible bot command architecture

**Usage:**

- Connect with saved credentials: `joinChannel(broadcasterID:botID:token:clientID:)` or `connectToChannel(channelName:token:clientID:)`.
- Send chat messages via Helix: `sendMessage(_:)` or `sendMessage(_:replyTo:)`.
- Supply current track info for commands: set `getCurrentSongInfo` on the service.
- Commands can be toggled in Settings ("Bot Commands" → "Current Song").
- The service respects `commandsEnabled` so you can disable all commands from Settings.

**Documentation:**

- Comprehensive MARK sections organize the 700+ line service file
- DocC-style comments document all public methods
- Typed errors with localized descriptions (`ConnectionError`)
- Models for chat messages, badges, and replies

### Bot Command Architecture

Commands live under `Services/Twitch/Commands` with a clean, extensible design:

- **`BotCommand` protocol** defines `triggers`, `description`, and `execute(message:)`.
- **`SongCommand`** handles `!song`, `!currentsong`, and `!nowplaying` and calls the injected `getCurrentSongInfo` closure.
- **`BotCommandDispatcher`** wires commands together and is used inside `TwitchChatService`.

**Code Organization:**

- Each command file is fully documented with usage examples
- Clear separation between command logic and service integration
- Type-safe message processing with optional return values

### Adding a New Command (example)

```swift
/// Command that greets users in chat.
///
/// Triggers: !hello, !hi
final class HelloCommand: BotCommand {
    let triggers = ["!hello", "!hi"]
    let description = "Greets the chatter"

    func execute(message: String) -> String? {
        let trimmed = message.trimmingCharacters(in: .whitespaces).lowercased()

        for trigger in triggers {
            if trimmed.hasPrefix(trigger) {
                return "Hello, chat! 👋"
            }
        }

        return nil
    }
}
```

Register it in `BotCommandDispatcher.registerDefaultCommands()`:

```swift
private func registerDefaultCommands() {
    register(SongCommand())
    register(HelloCommand())  // Add your new command
}
```

Add a Settings toggle if you want user control over enabling/disabling the command.

### Security

- WebSocket tokens, Twitch OAuth tokens, and Twitch bot usernames are stored in Keychain
- Tokens are not written to UserDefaults or disk in plain text

## License

![GitHub license](https://img.shields.io/github/license/MrDemonWolf/wolfwave.svg?style=for-the-badge&logo=github)

## Contact

If you have any questions, suggestions, or feedback, reach out on Discord!

- Discord: [Join my server](https://mrdwolf.com/discord)

Thank you for choosing WolfWave to share your music with your community!

Made with ❤️ by <a href="https://www.mrdemonwolf.com">MrDemonWolf, Inc.</a>
