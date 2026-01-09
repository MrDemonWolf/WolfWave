# WolfWave - Apple Music + Twitch Companion 🎵

![WolfWave Banner](banner.jpg)

Your Stream's Now Playing Companion! WolfWave makes it easy to share what you're listening to with your community. Show real-time "now playing" info, let your chat ask for the current song, and keep everything secure and lightweight.

Whether you're streaming, recording, or just vibing, WolfWave helps your audience connect with your music. Keep things simple, fast, and privacy-friendly.

Start your stream with a song, or let your chat discover new music with `!song`. Let's make sharing your soundtrack effortless!

## Features

- **Real-time Now Playing**: Tracks the current Apple Music song and updates instantly.
- **Twitch Chat Integration**: Responds to `!song`, `!currentsong`, and `!nowplaying` using modern EventSub + Helix (no IRC).
- **WebSocket Streaming**: Broadcast now-playing data to your overlay or tools (ws:// or wss://).
- **Secure by Default**: Credentials are stored in macOS Keychain; no plain-text tokens.

## Getting Started

To use WolfWave on macOS, follow these simple steps:

1. Clone the repository:

   ```bash
   git clone https://github.com/MrDemonWolf/WolfWave.git
   cd WolfWave
   ```

2. Open the project:

   ```bash
   make open-xcode
   # or
   open wolfwave.xcodeproj
   ```

3. Resolve dependencies:

   ```bash
   make update-deps
   ```

4. Build and run from Xcode (⌘R) 🎉

## Usage

WolfWave is user-friendly and runs from your macOS menu bar. Here's a quick guide to the basic features:

- Menu bar icon shows your current track.
- Toggle Apple Music tracking on/off.
- Configure WebSocket streaming (endpoint + optional JWT).
- Connect your Twitch bot via secure device auth.
- Chat commands supported: `!song`, `!currentsong`, `!nowplaying`.

# Change Log

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
2. Open the project: `make open-xcode`
3. Resolve dependencies: `make update-deps`

### Development Commands

- `make build` — Build the app
- `make clean` — Clean build artifacts
- `make test` — Run tests (if configured)
- `make update-deps` — Resolve SwiftPM dependencies
- `make open-xcode` — Open the Xcode project
- `make env-check` — Check required environment configuration
- `make ci` — CI-friendly build

### Code Quality

This project follows Swift best practices:

- Swift 5.9+ with modern concurrency (async/await)
- SwiftUI for user interfaces
- Separation of concerns across Core/Services/Views
- Secure credential storage via Keychain
- Robust error handling

### Project Structure

```
wolfwave/
├── Core/                    # Core utilities and services
│   ├── KeychainService.swift
│   └── Logger.swift
├── Monitors/                # Music playback monitoring
│   └── MusicPlaybackMonitor.swift
├── Services/                # External service integrations
│   └── Twitch/
│       ├── TwitchChatService.swift
│       ├── TwitchDeviceAuth.swift
│       └── Commands/
├── Views/                   # SwiftUI views
│   ├── SettingsView.swift
│   └── Twitch/
└── Resources/              # Assets and resources
```

### Twitch Chat Bot

The bot is implemented with `TwitchChatService` using Twitch Helix + EventSub (no IRC).

- Connect with saved credentials: `joinChannel(broadcasterID:botID:token:clientID:)` or `connectToChannel(channelName:token:clientID:)`.
- Send chat messages via Helix: `sendMessage(_:)` or `sendMessage(_:replyTo:)`.
- Supply current track info for commands: set `getCurrentSongInfo` on the service.
- Commands can be toggled in Settings ("Bot Commands" → "Current Song").
- The service respects `commandsEnabled` so you can disable all commands from Settings.

### Bot Command Architecture

- Commands live under `Services/Twitch/Commands`.
- `BotCommand` protocol defines `triggers`, `description`, and `execute(message:)`.
- `SongCommand` handles `!song`, `!currentsong`, and `!nowplaying` and calls the injected `getCurrentSongInfo` closure.
- `BotCommandDispatcher` wires commands together and is used inside `TwitchChatService`.

### Adding a New Command (example)

```swift
final class HelloCommand: BotCommand {
    let triggers = ["!hello"]
    let description = "Greets the chatter"

    func execute(message: String) -> String? {
        let trimmed = message.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed.hasPrefix("!hello") ? "Hello, chat!" : nil
    }
}
```

Register it in `BotCommandDispatcher.registerDefaultCommands()` by instantiating and calling `register(_:)`. Add any Settings toggle before enabling it by default.

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
