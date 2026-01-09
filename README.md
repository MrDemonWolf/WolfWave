# WolfWave

WolfWave is a macOS menu bar app that:

- Tracks the currently playing song from Apple Music.
- Can push “now playing” data to a WebSocket endpoint.
- Runs a Twitch chat bot (EventSub + Helix) that can answer chat commands like `!song`.
- Stores all credentials securely in the macOS Keychain.

## Settings Overview

- **Music Tracking**: Enable/disable Apple Music monitoring; shows real-time track info in the app.
- **WebSocket**: Enter a ws:// or wss:// URL and (optionally) a JWT token to stream “now playing” data to an overlay/server.
- **Twitch Bot**: Save Twitch OAuth token and bot username; credentials live in Keychain.
- **Bot Commands**: Toggle the Current Song command (`!song`, `!currentsong`, `!nowplaying`).

## Twitch Chat Bot

The bot is implemented with `TwitchChatService` using Twitch Helix + EventSub (no IRC).

- Connect with saved credentials: `joinChannel(broadcasterID:botID:token:clientID:)` or `connectToChannel(channelName:token:clientID:)`.
- Send chat messages via Helix: `sendMessage(_:)` or `sendMessage(_:replyTo:)`.
- Supply current track info for commands: set `getCurrentSongInfo` on the service.
- Commands can be toggled in Settings (“Bot Commands” → “Current Song”).
- The service respects `commandsEnabled` so you can disable all commands from Settings.

### Bot Command Architecture

- Commands live under `Services/Twitch/Commands`.
- `BotCommand` protocol defines `triggers`, `description`, and `execute(message:)`.
- `SongCommand` handles `!song`, `!currentsong`, and `!nowplaying` and calls the injected `getCurrentSongInfo` closure.
- `BotCommandDispatcher` wires commands together and is used inside `TwitchChatService`.

#### Adding a New Command (example)

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

Register it (for now) in `BotCommandDispatcher.registerDefaultCommands()` by instantiating and calling `register(_:)`, and add any needed settings toggle before enabling it by default.

## Security

- WebSocket tokens, Twitch OAuth tokens, and Twitch bot usernames are stored in Keychain.
- Tokens are not written to UserDefaults or disk in plain text.

## Links

- [Twitch EventSub](https://dev.twitch.tv/docs/eventsub/)
- [Twitch Helix Chat/Send Message](https://dev.twitch.tv/docs/api/reference/#send-chat-message)
