<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="logo-dark.png" />
    <source media="(prefers-color-scheme: light)" srcset="logo-light.png" />
    <img src="logo-light.png" alt="WolfWave" width="200" />
  </picture>
</p>

<h1 align="center">WolfWave - Your Music, Everywhere</h1>

<!-- ![WolfWave Banner](banner.jpg) -->

WolfWave is a professional-grade macOS menu bar utility that bridges Apple Music with the platforms you use. Effortlessly broadcast real-time song data to stream overlays via WebSockets, interact with your Twitch community through automated chat commands, and show what you're listening to on Discord.

## Features

- **Real-time Now Playing** — Track Apple Music and broadcast instantly via ScriptingBridge
- **Twitch Chat Bot** — `!song`, `!currentsong`, `!nowplaying`, `!lastsong` via EventSub + Helix
- **Discord Rich Presence** — Show "Listening to Apple Music" on your Discord profile with dynamic album art
- **WebSocket Streaming** — Send now-playing data to overlays (ws:// or wss://)
- **Secure by Default** — All credentials stored in macOS Keychain; no plain-text tokens
- **First-Launch Onboarding** — Guided setup wizard for new users

## Getting Started

1. Download the latest DMG from the [GitHub Releases](https://github.com/MrDemonWolf/WolfWave/releases) page
2. Open the DMG and drag **WolfWave** to your **Applications** folder
3. Launch WolfWave and follow the onboarding wizard

> The app is signed and notarized by Apple — no Gatekeeper warnings.

## Usage

### Chat Commands

| Command        | Description              |
| -------------- | ------------------------ |
| `!song`        | Current playing song     |
| `!currentsong` | Current playing song     |
| `!nowplaying`  | Current playing song     |
| `!lastsong`    | Previously played song   |
| `!last`        | Previously played song   |
| `!prevsong`    | Previously played song   |

### Discord Rich Presence

Enable in **Settings > Discord** to show what you're listening to on your Discord profile. Album artwork is fetched automatically from the iTunes Search API — no manual setup needed.

### WebSocket Streaming

Configure in **Settings > WebSocket** to broadcast now-playing data to your stream overlays in real-time.

## Development

### Prerequisites

- macOS 15.0+
- Xcode 16.0+
- Swift 5.9+
- Command Line Tools: `xcode-select --install`

### Setup

```bash
git clone https://github.com/MrDemonWolf/WolfWave.git
cd WolfWave

# Configure API keys
cp src/wolfwave/Config.xcconfig.example src/wolfwave/Config.xcconfig
# Edit Config.xcconfig with your Twitch Client ID and Discord Application ID

# Open in Xcode and run (Cmd+R)
make open-xcode
```

> Get a Twitch Client ID at [dev.twitch.tv/console/apps](https://dev.twitch.tv/console/apps)
>
> Get a Discord Application ID at [discord.com/developers/applications](https://discord.com/developers/applications)

### Development Scripts

| Command            | Description                              |
| ------------------ | ---------------------------------------- |
| `make build`       | Debug build                              |
| `make clean`       | Clean build artifacts                    |
| `make prod-build`  | Release build + DMG                      |
| `make notarize`    | Notarize the DMG (requires Developer ID) |
| `make test`        | Run tests                                |
| `make open-xcode`  | Open Xcode project                       |
| `make update-deps` | Resolve SwiftPM dependencies             |

## Releasing

Pushing a version tag triggers the CI/CD pipeline which builds, notarizes, and creates a GitHub Release:

```bash
git tag v1.0.0
git push origin v1.0.0
```

See [Releasing & Notarization](/docs/content/docs/getting-started.mdx) in the docs for full CI/CD setup instructions.

## Documentation

For complete documentation, visit: **[mrdemonwolf.github.io/wolfwave](https://mrdemonwolf.github.io/wolfwave)**

- [Features](https://mrdemonwolf.github.io/wolfwave/docs/features) — Complete feature list
- [Installation](https://mrdemonwolf.github.io/wolfwave/docs/installation) — Download and setup
- [Usage Guide](https://mrdemonwolf.github.io/wolfwave/docs/usage) — How to use WolfWave
- [Bot Commands](https://mrdemonwolf.github.io/wolfwave/docs/bot-commands) — Chat command reference
- [Development](https://mrdemonwolf.github.io/wolfwave/docs/development) — Contributing guide
- [Architecture](https://mrdemonwolf.github.io/wolfwave/docs/architecture) — Project structure

## License

![GitHub license](https://img.shields.io/github/license/MrDemonWolf/wolfwave.svg?style=for-the-badge&logo=github)

## Support

Questions or feedback? Join the Discord: [mrdwolf.net/discord](https://mrdwolf.net/discord)

---

Made with ❤️ by [MrDemonWolf, Inc.](https://www.mrdemonwolf.com)
