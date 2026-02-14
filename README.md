<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="logo-dark.png" />
    <source media="(prefers-color-scheme: light)" srcset="logo-light.png" />
    <img src="logo-light.png" alt="WolfWave" width="200" />
  </picture>
</p>

<h1 align="center">WolfWave - Your Music, Everywhere</h1>

<!-- ![WolfWave Banner](banner.jpg) -->

A native macOS menu bar app that bridges Apple Music with Twitch, Discord, and your stream overlays. Real-time now playing detection, automated chat commands, Discord Rich Presence with dynamic album art, and WebSocket streaming — all from your menu bar.

## Features

- **Real-time Now Playing** — Track Apple Music and broadcast instantly via ScriptingBridge
- **Twitch Chat Bot** — `!song`, `!currentsong`, `!nowplaying`, `!lastsong` via EventSub + Helix
- **Discord Rich Presence** — Show "Listening to Apple Music" on your Discord profile with dynamic album art and playback progress
- **WebSocket Streaming** — Send now-playing data to overlays (ws:// or wss://)
- **Automatic Updates** — Checks GitHub Releases for new versions with Homebrew and DMG support
- **Secure by Default** — All credentials stored in macOS Keychain; no plain-text tokens
- **First-Launch Onboarding** — Guided 3-step setup wizard (Welcome, Twitch, Discord)

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
| `make test`        | Run unit tests (124 tests)               |
| `make open-xcode`  | Open Xcode project                       |
| `make update-deps` | Resolve SwiftPM dependencies             |

## Releasing

### 1. Build the DMG

```bash
make prod-build
```

This builds a Release `.app`, re-signs it with your Developer ID certificate, and packages it into `builds/WolfWave-<VERSION>-arm64.dmg`.

### 2. Notarize

```bash
APPLE_ID=you@example.com \
APPLE_TEAM_ID=XXXXXXXXXX \
APPLE_APP_PASSWORD=xxxx-xxxx-xxxx-xxxx \
make notarize
```

This signs the DMG, submits it to Apple's notary service, waits for approval, and staples the ticket.

> Generate an app-specific password at [appleid.apple.com](https://appleid.apple.com) under **Sign-In and Security > App-Specific Passwords**.

### 3. Tag and release

```bash
git tag v1.0.0
git push origin v1.0.0
```

Pushing a tag triggers CI which builds the DMG and creates a GitHub Release automatically. You can then replace the CI-built DMG with your locally notarized one, or upload it manually.

## Testing

Run the full test suite with:

```bash
make test
```

Or in Xcode with **Cmd+U**. Tests cover bot commands, version comparison, onboarding navigation, Twitch view model state, and app constants integrity. The CI pipeline runs tests automatically on every push and pull request to `main`.

## Documentation

For complete documentation, visit: **[mrdemonwolf.github.io/wolfwave](https://mrdemonwolf.github.io/wolfwave)**

- [Features](https://mrdemonwolf.github.io/wolfwave/docs/features) — Complete feature list
- [Installation](https://mrdemonwolf.github.io/wolfwave/docs/installation) — Download and setup
- [Usage Guide](https://mrdemonwolf.github.io/wolfwave/docs/usage) — How to use WolfWave
- [Bot Commands](https://mrdemonwolf.github.io/wolfwave/docs/bot-commands) — Chat command reference
- [Development](https://mrdemonwolf.github.io/wolfwave/docs/development) — Contributing guide
- [Architecture](https://mrdemonwolf.github.io/wolfwave/docs/architecture) — Project structure
- [Privacy Policy](https://mrdemonwolf.github.io/wolfwave/docs/privacy-policy) — Privacy practices
- [Terms of Service](https://mrdemonwolf.github.io/wolfwave/docs/terms-of-service) — Usage terms

## License

![GitHub license](https://img.shields.io/github/license/MrDemonWolf/wolfwave.svg?style=for-the-badge&logo=github)

## Support

Questions or feedback? Join the Discord: [mrdwolf.net/discord](https://mrdwolf.net/discord)

---

Made with ❤️ by [MrDemonWolf, Inc.](https://www.mrdemonwolf.com)
