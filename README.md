# WolfWave - Apple Music + Twitch Companion 🎵

![WolfWave Banner](banner.jpg)

WolfWave is a professional-grade macOS menu bar utility designed to connect Apple Music with your audience. Effortlessly broadcast real-time song data to overlays via WebSockets and interact with your Twitch community through secure, automated chat commands.

## Features

- **Real-time Now Playing** — Track Apple Music and broadcast instantly
- **Twitch Chat Bot** — `!song`, `!currentsong`, `!nowplaying` commands via EventSub + Helix
- **WebSocket Streaming** — Send now-playing data to overlays (ws:// or wss://)
- **Secure by Default** — All credentials stored in macOS Keychain

## Quick Start

```bash
# Clone the repo
git clone https://github.com/MrDemonWolf/WolfWave.git
cd WolfWave

# Configure Twitch Client ID
cp src/wolfwave/Config.xcconfig.example src/wolfwave/Config.xcconfig
# Edit Config.xcconfig with your Twitch Client ID

# Open in Xcode
make open-xcode

# Build and run (⌘R)
```

> Get a Twitch Client ID at [dev.twitch.tv/console/apps](https://dev.twitch.tv/console/apps)

## Documentation

For complete documentation, visit: **[wolfwave.mdwolf.net](https://wolfwave.mdwolf.net)**

- [Getting Started](https://wolfwave.mdwolf.net/docs/getting-started) — Installation and setup
- [Features](https://wolfwave.mdwolf.net/docs/features) — Complete feature list
- [Usage Guide](https://wolfwave.mdwolf.net/docs/usage) — How to use WolfWave
- [Bot Commands](https://wolfwave.mdwolf.net/docs/bot-commands) — Chat command system
- [Development](https://wolfwave.mdwolf.net/docs/development) — Contributing guide
- [Architecture](https://wolfwave.mdwolf.net/docs/architecture) — Project structure

## Development Commands

| Command                               | Description                  |
| ------------------------------------- | ---------------------------- |
| `make build`                          | Debug build                  |
| `make clean`                          | Clean build artifacts        |
| `make open-xcode`                     | Open Xcode project           |
| `make update-deps`                    | Resolve SwiftPM dependencies |
| `make prod-build TWITCH_CLIENT_ID=id` | Release build with DMG       |

## Requirements

- macOS 12.0+
- Xcode 15.0+
- Swift 5.9+

## License

![GitHub license](https://img.shields.io/github/license/MrDemonWolf/wolfwave.svg?style=for-the-badge&logo=github)

## Support

Questions or feedback? Join the Discord: [mdwolf.net/discord](https://mdwolf.net/discord)

---

Made with ❤️ by [MrDemonWolf, Inc.](https://www.mrdemonwolf.com)
