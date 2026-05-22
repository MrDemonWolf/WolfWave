# 🐺 WolfWave

**A macOS menu bar app that bridges Apple Music to Twitch, Discord, and stream widgets.**

[![Swift 6](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey.svg)](https://www.apple.com/macos)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

---

## ✨ Features

### 🎵 **Apple Music Integration**
- Real-time now-playing tracking
- Album artwork fetching
- Playback state monitoring
- MusicKit catalog search

### 💬 **Twitch Chat Bot**
- OAuth Device Code Flow authentication
- EventSub WebSocket for chat messages
- Customizable commands (`!song`, `!last`, `!sr`)
- Cooldown management (global & per-user)
- Song request queue with auto-advance

### 🎮 **Discord Rich Presence**
- "Listening to Apple Music" status
- Album artwork display
- Playback progress bar
- Customizable buttons (Apple Music + song.link)
- Auto-reconnection when Discord restarts

### 📺 **Stream Widgets**
- WebSocket server for OBS browser sources
- HTTP server for widget overlays
- Real-time now-playing updates
- Album artwork streaming
- Multiple theme support

### 🎶 **Song Requests**
- Apple Music catalog search
- Spotify/YouTube URL resolution via oEmbed
- Queue management (skip, clear, hold)
- Per-user request limits
- Subscriber-only mode
- Blocklist support
- Fallback playlist when queue empty

### ⚙️ **Power Management**
- Low Power Mode detection
- Thermal pressure monitoring
- Reduced polling in power-saving modes

### 🔄 **Automatic Updates**
- Sparkle framework integration
- GitHub Releases monitoring
- Delta updates support
- Homebrew install detection

---

## 🚀 Quick Start

### Prerequisites

- **macOS 13.0+** (Ventura or later)
- **Xcode 16.0+** (for building from source)
- **Swift 6.0+**

### Installation

#### Option 1: Homebrew (Recommended)

```bash
brew tap mrdemonwolf/wolfwave
brew install --cask wolfwave
```

#### Option 2: Download from Releases

1. Download the latest `.dmg` from [Releases](https://github.com/mrdemonwolf/wolfwave/releases)
2. Open the `.dmg` and drag WolfWave to `/Applications`
3. Launch WolfWave from Applications

#### Option 3: Build from Source

1. **Clone the repository:**
   ```bash
   git clone https://github.com/mrdemonwolf/wolfwave.git
   cd wolfwave
   ```

2. **Set up configuration:**
   ```bash
   cp Config.xcconfig.example Config.xcconfig
   ```

3. **Edit `Config.xcconfig`** with your API keys:
   - **Twitch Client ID**: https://dev.twitch.tv/console/apps
   - **Discord Application ID**: https://discord.com/developers/applications

4. **Open in Xcode:**
   ```bash
   open wolfwave.xcodeproj
   ```

5. **Build and run** (⌘R)

---

## 🔧 Configuration

### First Launch

WolfWave includes an onboarding wizard that guides you through:

1. **Discord Rich Presence** — Enable "Listening to Apple Music" status
2. **Twitch Authentication** — Connect your Twitch account for chat bot
3. **Stream Widgets** — Set up OBS browser source overlays
4. **Preferences** — Launch at login, dock visibility
5. **Apple Music Access** — Grant MusicKit permissions
6. **Menu Bar Pointer** — Locates the menu bar icon

### Settings

Access Settings from the menu bar icon (⚙️) or with **⌘,**

#### **General**
- Enable/disable music tracking
- Dock visibility modes (menu only, dock only, both)
- Launch at login

#### **Song Requests**
- Enable song request system
- Configure queue limits (max size, per-user)
- Subscriber-only mode
- Auto-advance settings
- Fallback playlist
- Command aliases
- Cooldown timers

#### **Stream Widgets**
- WebSocket server enable/port
- Widget HTTP server enable/port
- Theme selection
- Layout (horizontal, vertical, compact)
- Colors and fonts

#### **Twitch**
- OAuth authentication
- Channel connection
- Bot commands (`!song`, `!last`)
- Command aliases
- Cooldown settings

#### **Discord**
- Rich Presence enable/disable
- Button labels and URLs
- Connection status

#### **Advanced**
- Software updates (manual check, auto-check)
- Reset onboarding
- Reset all settings
- Diagnostics (logs, export)

---

## 🎯 Usage

### Twitch Bot Commands

Default commands (customizable aliases in Settings):

| Command | Description | Aliases |
|---------|-------------|---------|
| `!song` | Shows currently playing track | `!currentsong`, `!nowplaying` |
| `!last` | Shows previously played track | `!lastsong`, `!prevsong` |
| `!sr <query>` | Request a song | `!songrequest` |
| `!queue` | Shows full request queue | `!q` |
| `!myqueue` | Shows your requests in queue | `!mq` |
| `!skip` | Skip current request (mod/broadcaster) | — |
| `!clearqueue` | Clear all requests (mod/broadcaster) | `!cq` |

### Song Request Syntax

```
!sr Rick Astley Never Gonna Give You Up
!sr https://open.spotify.com/track/4PTG3Z6ehGkBFwjybzWkR8
!sr https://music.apple.com/us/album/never-gonna-give-you-up/1558533900?i=1558534040
!sr https://www.youtube.com/watch?v=dQw4w9WgXcQ
```

### OBS Browser Source

1. Enable **Stream Widgets** in Settings
2. Copy the widget URL: `http://localhost:8766`
3. In OBS:
   - Add **Browser** source
   - Paste the URL
   - Set dimensions: **500 × 120** (recommended)
   - Check **Shutdown source when not visible**
   - Check **Refresh browser when scene becomes active**

---

## 🛠️ Development

### Project Structure

```
wolfwave/
├── WolfWaveApp.swift              # App entry point
├── AppDelegate+MenuBar.swift       # Menu bar UI
├── AppDelegate+Windows.swift       # Window management
├── AppDelegate+Services.swift      # Service setup
├── AppConstants.swift              # Centralized constants
├── Services/
│   ├── TwitchChatService.swift        # Twitch EventSub WebSocket
│   ├── DiscordRPCService.swift        # Discord IPC
│   ├── WebSocketServerService.swift   # Stream widget server
│   ├── SparkleUpdaterService.swift    # Auto-updates
│   ├── SongRequestService.swift       # Song request queue
│   ├── AppleMusicController.swift     # Music.app control
│   ├── PlaybackSourceManager.swift    # Now-playing monitor
│   └── ...
├── Views/
│   ├── OnboardingView.swift           # First-launch wizard
│   ├── SettingsView.swift             # Settings UI
│   ├── GeneralSettingsView.swift      # General tab
│   ├── TwitchSettingsView.swift       # Twitch tab
│   ├── DiscordSettingsView.swift      # Discord tab
│   ├── SongRequestSettingsView.swift  # Song requests tab
│   ├── WebSocketSettingsView.swift    # Stream widgets tab
│   └── ...
├── ViewModels/
│   ├── OnboardingViewModel.swift
│   ├── TwitchViewModel.swift
│   └── ...
├── Models/
│   ├── SongRequestQueue.swift
│   ├── SongBlocklist.swift
│   └── ...
└── Config.xcconfig                 # API keys (gitignored)
```

### Running Tests

```bash
# Run all tests
xcodebuild test -scheme wolfwave -destination 'platform=macOS'

# Run specific test
xcodebuild test -scheme wolfwave -destination 'platform=macOS' -only-testing:wolfwaveTests/TwitchChatServiceTests
```

### Code Style

- **Swift 6.0** with strict concurrency checking
- **SwiftUI** for UI (no UIKit/AppKit in views)
- **Async/await** over Dispatch/Combine
- **AppKit** for menu bar, windows, AppleScript
- **Protocols** for testability
- **MARK comments** for organization
- **Inline docs** for public APIs

### Thread Safety

- Services use manual locking (`NSLock`) where Swift Concurrency isn't suitable
- `@unchecked Sendable` with clear lock documentation
- Lock ownership documented inline (see `DiscordRPCService`, `TwitchChatService`)

---

## 🔐 Security

### API Keys

**NEVER commit `Config.xcconfig` with real API keys.**

- Use `Config.xcconfig.example` as a template
- Store real keys only in local `Config.xcconfig` (gitignored)
- Rotate keys immediately if exposed

See [SECURITY.md](SECURITY.md) for full security guidelines.

### Keychain

OAuth tokens are stored securely in macOS Keychain:
- **Service**: `com.mrdemonwolf.wolfwave`
- **Access**: Protected by Keychain Access Control
- **Cleared**: On sign-out or settings reset

### App Sandbox

WolfWave runs in the macOS App Sandbox with minimal entitlements:
- ✅ Network (Client)
- ✅ MusicKit
- ✅ User Selected Files (Read/Write, for log export)

---

## 📝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Copy `Config.xcconfig.example` to `Config.xcconfig` and fill in your keys
4. Make your changes
5. Run tests (`xcodebuild test`)
6. Commit with clear messages (`git commit -m 'Add amazing feature'`)
7. Push to your fork (`git push origin feature/amazing-feature`)
8. Open a Pull Request

### Code Review Checklist

- [ ] No API keys in source files
- [ ] Tests pass
- [ ] Documentation updated
- [ ] MARK comments added
- [ ] Accessibility labels on UI elements
- [ ] Thread safety documented

---

## 📄 License

WolfWave is licensed under the **MIT License**. See [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgments

### Dependencies

- [Sparkle](https://sparkle-project.org/) — Software updates
- [MusicKit](https://developer.apple.com/documentation/musickit) — Apple Music integration
- [SwiftUI](https://developer.apple.com/xcode/swiftui/) — User interface

### Inspiration

- Snip (now-playing overlay tool)
- Pretzel Rocks (song request systems)
- Discord RPC projects

---

## 📧 Support

- **Issues**: [GitHub Issues](https://github.com/mrdemonwolf/wolfwave/issues)
- **Discussions**: [GitHub Discussions](https://github.com/mrdemonwolf/wolfwave/discussions)
- **Documentation**: [https://mrdemonwolf.github.io/wolfwave](https://mrdemonwolf.github.io/wolfwave)
- **Email**: [your-email@domain.com]

---

## 🗓️ Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.

---

**Made with ❤️ for streamers by [@mrdemonwolf](https://github.com/mrdemonwolf)**
