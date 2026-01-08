# PackTrack

A macOS application that monitors Apple Music playback and integrates with Twitch chat for streamers.

## Features

- **Music Tracking**: Monitor and display currently playing Apple Music tracks
- **WebSocket Reporting**: Send tracking data to remote servers
- **Twitch Chat Integration**: Full-featured Twitch chatbot with IRC support
- **Secure Credentials**: All tokens stored securely in macOS Keychain

## Configuration

### Settings Panel

The application provides a settings interface accessible from the menu bar with the following sections:

#### Music Tracking

- Enable/disable Apple Music monitoring
- Real-time track display

#### WebSocket

- Configure remote server URI (ws://, wss://, http://, https://)
- Secure JWT authentication token storage
- WebSocket-based tracking data relay

#### Twitch Bot

- Twitch bot username
- OAuth token (secure field)
- Link to [Twitch Token Generator](https://twitchtokengenerator.com/)
- All credentials stored securely in macOS Keychain

#### Bot Commands

- Enable/disable specific bot commands
- Current Song command responds to `!song`, `!currentsong`, and `!nowplaying`
- Commands are configurable through checkboxes

## Twitch Integration (TwitchService)

The `TwitchService` class provides a complete implementation of the Twitch IRC API for chatbot functionality.

### Initialization & Connection

```swift
let twitchService = TwitchService()
twitchService.connect()  // Connects using credentials from Keychain
twitchService.disconnect()  // Graceful disconnection
```

### Setting Up Command Callbacks

To enable bot commands that require app data (like the current song), set the callback before connecting:

```swift
twitchService.getCurrentSongInfo = {
    // Return the current track info from your music monitor
    return (track: "Song Name", artist: "Artist Name", album: "Album Name")
}
```

### Bot Commands

The bot supports configurable commands that are enabled through the settings panel:

#### Current Song Command

When enabled in settings, responds to `!song`, `!currentsong`, and `!nowplaying` with the currently playing track.

**Response format**: 🎵 Song Name by Artist Name from Album Name

**Example**:

```
User: !song
Bot: 🎵 Blinding Lights by The Weeknd from After Hours
```

To enable this command, you must:

1. Enable "Current Song" in the Bot Commands section of settings
2. Set the `getCurrentSongInfo` callback on the TwitchService instance

### Chat Messaging

#### Send Regular Messages

```swift
twitchService.sendMessage(to: "channelname", message: "Hello chat!")
```

#### Send Action Messages (/me)

```swift
twitchService.sendAction(to: "channelname", message: "does something cool")
```

#### Reply to Messages

```swift
twitchService.sendReply(to: "channelname", message: "Great point!", replyingTo: "message-uuid-here")
```

#### Mention Users

```swift
twitchService.sendMention(to: "username", message: "check this out")
```

### Community Commands

#### Shout-outs

```swift
twitchService.sendShoutout(in: "channelname", to: "otherstreamer")
```

#### Raids

```swift
twitchService.sendRaid(from: "channelname", to: "targetchannel")
```

#### Host

```swift
twitchService.sendHost(from: "channelname", to: "targetchannel")
```

### Moderation Commands

#### Ban Users

```swift
twitchService.sendBan(in: "channelname", username: "baduser", reason: "spam")
```

#### Timeout Users

```swift
twitchService.sendTimeout(in: "channelname", username: "user", duration: 600, reason: "timeout reason")
// duration: seconds (default 600)
```

#### Unban Users

```swift
twitchService.sendUnban(in: "channelname", username: "user")
```

### Channel Settings

#### Slow Mode

```swift
twitchService.sendSlowMode(in: "channelname", seconds: 10)
// Set to 0 to disable
```

#### Emote-Only Mode

```swift
twitchService.sendEmoteOnlyMode(in: "channelname", enabled: true)
```

#### Followers-Only Mode

```swift
twitchService.sendFollowersOnlyMode(in: "channelname", minutes: 0)
// Set to 0 to disable, otherwise minimum follow duration in minutes
```

#### Subscribers-Only Mode

```swift
twitchService.sendSubscribersOnlyMode(in: "channelname", enabled: true)
```

#### Unique Chat Mode (R9K)

```swift
twitchService.sendUniqueChatMode(in: "channelname", enabled: true)
```

#### Commercial

```swift
twitchService.sendCommercial(in: "channelname", length: 60)
// Valid lengths: 30, 60, or 90 seconds
```

### Channel Management

#### Join Channels

```swift
twitchService.joinChannels(["channel1", "channel2"])
```

#### Leave Channels

```swift
twitchService.leaveChannels(["channel1"])
```

### Receiving Chat Events

The service posts notifications for various chat events. Listen to them using `NotificationCenter`:

#### Chat Messages

```swift
NotificationCenter.default.addObserver(
    forName: TwitchService.chatMessageReceivedNotification,
    object: nil,
    queue: .main
) { notification in
    if let chatMessage = notification.userInfo?["message"] as? TwitchService.ChatMessage {
        print("Message from \(chatMessage.displayName): \(chatMessage.text)")
        print("Is mod: \(chatMessage.isMod)")
        print("Badges: \(chatMessage.badges)")
    }
}
```

#### User State Changes

```swift
NotificationCenter.default.addObserver(
    forName: TwitchService.userStateChangedNotification,
    object: nil,
    queue: .main
) { notification in
    if let userInfo = notification.userInfo as? [String: Any] {
        let displayName = userInfo["displayName"] as? String
        let isMod = userInfo["isMod"] as? Bool ?? false
    }
}
```

#### Room State Changes

```swift
NotificationCenter.default.addObserver(
    forName: TwitchService.roomStateChangedNotification,
    object: nil,
    queue: .main
) { notification in
    if let roomInfo = notification.userInfo as? [String: Any] {
        let slowMode = roomInfo["slowMode"] as? String
        let subsOnly = roomInfo["subsOnly"] as? Bool ?? false
    }
}
```

#### Connection State Changes

```swift
NotificationCenter.default.addObserver(
    forName: TwitchService.connectionStateChangedNotification,
    object: nil,
    queue: .main
) { notification in
    if let connected = notification.userInfo?["connected"] as? Bool {
        print("Connected: \(connected)")
    }
}
```

### ChatMessage Structure

Each chat message includes:

```swift
struct ChatMessage {
    let messageId: String              // Unique message ID
    let username: String               // Lowercase username
    let displayName: String            // Display name with proper casing
    let userId: String                 // Numeric user ID
    let channel: String                // Channel name (without #)
    let text: String                   // Message content
    let color: String                  // User's chat color (hex)
    let badges: [String: String]       // User badges (mod, subscriber, etc.)
    let isMod: Bool                    // Is the user a moderator
    let isSubscriber: Bool             // Is the user a subscriber
    let isBroadcaster: Bool            // Is the user the broadcaster
    let isVIP: Bool                    // Is the user a VIP
    let isTurbo: Bool                  // Does the user have Turbo
    let emotes: [String: [String]]     // Emotes in message with positions
    let firstMessage: Bool             // Is this user's first message
    let replyParentId: String?         // ID of message being replied to
    let replyParentUsername: String?   // Username of message being replied to
    let timestamp: Double              // Message timestamp (milliseconds)
}
```

## Security

All sensitive credentials are stored securely in macOS Keychain:

- WebSocket authentication tokens
- Twitch OAuth tokens
- Twitch bot usernames

Tokens are never stored in UserDefaults or written to disk in plain text.

## Documentation References

- [Twitch Chat Documentation](https://dev.twitch.tv/docs/chat/)
- [Twitch IRC API](https://dev.twitch.tv/docs/chat/irc/)
- [Twitch Send/Receive Messages](https://dev.twitch.tv/docs/chat/send-receive-messages/)
