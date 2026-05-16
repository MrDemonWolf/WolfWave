# WolfWave - Your Music, Everywhere on Stream

WolfWave is a native macOS menu bar app that bridges Apple Music with
Twitch chat, Discord Rich Presence, and OBS stream overlays. Built for
streamers and creators on Apple Silicon, it surfaces what you're
listening to everywhere your audience already is — automatically.

Keep your music in sync. Keep your stream alive.

## Features

- **Now Playing in Twitch Chat** — Viewers type `!song`, `!currentsong`, or `!nowplaying` and instantly see the track you're spinning.
- **Song Requests** — Viewers request songs with `!sr <track>`. Requests play through Apple Music without taking focus from OBS.
- **Hold-Mode Queue** — Mods can hold, resume, skip, and clear the request queue from chat or the menu bar.
- **Live Queue View** — See what's playing, what's next, and who requested each track right inside the app.
- **Fallback Playlist** — Configure an Apple Music playlist that takes over when the queue runs dry.
- **Discord Rich Presence** — Shows "Listening to Apple Music" on your Discord profile with album art and clickable open-in-Apple-Music + song.link buttons.
- **OBS Stream Widget** — Drop-in browser source overlay powered by a local WebSocket server.
- **macOS 26 Liquid Glass Design** — Refreshed onboarding, settings, and menu bar built for Tahoe.
- **Secure by Default** — Credentials live in the macOS Keychain, never plain text.
- **Automatic Updates** — Sparkle (DMG) or Homebrew (`brew upgrade --cask`).
- **Bug Report Flow** — One-click log export and pre-filled GitHub issue from Advanced settings.

## Getting Started

Full docs at [mrdemonwolf.github.io/wolfwave](https://mrdemonwolf.github.io/wolfwave).

### Homebrew (recommended)

```bash
brew tap mrdemonwolf/den
brew install --cask wolfwave
```

### Manual Download

1. Grab the latest `.dmg` from [GitHub Releases](https://github.com/MrDemonWolf/WolfWave/releases).
2. Open the DMG and drag **WolfWave** to **Applications**.
3. Launch WolfWave and follow the onboarding wizard.

The app is signed and notarized by Apple — no Gatekeeper warnings.

## Usage

### Viewer Commands

| Command | What it does |
| --- | --- |
| `!song` `!currentsong` `!nowplaying` | Shows the current track |
| `!lastsong` `!last` `!prevsong` | Shows the previous track |
| `!sr <song>` | Requests a song for the queue |
| `!queue` | Shows the full request queue |
| `!myqueue` | Shows just your own requests |

### Mod and Broadcaster Commands

| Command | What it does |
| --- | --- |
| `!skip` `!next` | Skips the current request |
| `!hold` | Pauses the queue so you can curate before releasing |
| `!resume` `!unhold` | Resumes a held queue |
| `!clearqueue` | Wipes the queue (with in-app confirmation) |

### Discord Rich Presence

Enable in **Settings > Discord** to show what you're listening to on
your Discord profile. Album artwork is fetched automatically.

### OBS Stream Widget

Enable in **Settings > Now-Playing Widget** to start a local WebSocket
server. Copy the widget URL and add it as a Browser Source (500 x 120)
in OBS.

## Tech Stack

| Layer | Technology |
| --- | --- |
| Language | Swift 5.9+ |
| UI | SwiftUI, AppKit |
| Platform | macOS 26.0+ (Tahoe), Apple Silicon |
| Music | ScriptingBridge, MusicKit, AppleScript |
| Twitch | EventSub WebSocket, Helix API |
| Discord | Rich Presence via local IPC Unix domain socket |
| Networking | URLSession, Network framework, NWListener (WebSocket overlay) |
| Updates | Sparkle (EdDSA-signed appcast) |
| Security | macOS Keychain (Security framework) |
| Docs | Fumadocs (Next.js), bun, Turborepo |
| Marketing | Remotion |

## Development

### Prerequisites

- macOS 26.0+ (Tahoe)
- Apple Silicon (M1 or later)
- Xcode 16.0+
- Swift 5.9+
- [bun](https://bun.sh) for docs and marketing workspaces
- Command Line Tools: `xcode-select --install`

### Setup

```bash
git clone https://github.com/MrDemonWolf/WolfWave.git
cd WolfWave
```

```bash
cp apps/native/wolfwave/Config.xcconfig.example apps/native/wolfwave/Config.xcconfig
```

Edit `Config.xcconfig` with your Twitch Client ID and Discord
Application ID. Get a Twitch Client ID at
[dev.twitch.tv/console/apps](https://dev.twitch.tv/console/apps) and a
Discord Application ID at
[discord.com/developers/applications](https://discord.com/developers/applications).

```bash
make open-xcode
```

Then build and run with `Cmd+R` in Xcode.

### Development Scripts

Monorepo (bun + Turborepo):

- `bun install` — Install all workspace dependencies.
- `bun dev` — Start every dev server via Turbo.
- `bun run dev --filter docs` — Start the docs dev server only.
- `bun run build --filter docs` — Build the docs site.
- `bun run dev --filter wolfwave-announcement` — Open Remotion studio for the launch announcement video.

Native app (Make):

- `make build` — Debug build via `xcodebuild`.
- `make clean` — Clean build artifacts.
- `make test` — Run the unit test suite (879 tests across 26 files).
- `make update-deps` — Resolve SwiftPM dependencies.
- `make open-xcode` — Open the Xcode project.
- `make ci` — CI-friendly build.
- `make prod-build` — Release build + DMG in `builds/`.
- `make prod-install` — Release build + install to `/Applications`.
- `make notarize` — Notarize the DMG (requires Developer ID + env vars).

### Code Quality

- Swift 5.9+ with async/await concurrency (no `DispatchQueue` for new async work).
- MVVM with `@Observable` view models.
- MARK sections in every file; DocC-style `///` comments on all public APIs.
- No force unwrapping — optionals and `guard` only.
- Credentials always via `KeychainService`, never `UserDefaults`.
- Thread-safe service layer (NSLock, serial dispatch queues, MainActor isolation).
- 879 unit tests across 26 files, auto-discovered via Xcode synchronized groups.

## Project Structure

```text
wolfwave/
├── apps/
│   ├── native/                 # Native macOS app (Swift, SwiftUI, AppKit)
│   │   ├── wolfwave/           # App source
│   │   ├── WolfWaveTests/      # Unit tests
│   │   └── wolfwave.xcodeproj  # Xcode project
│   ├── docs/                   # Fumadocs documentation site
│   └── marketing/              # Remotion-based promo videos
├── assets/                     # Brand assets, logos
├── CHANGELOG.md                # Release history
├── Makefile                    # Build, test, release targets
├── package.json                # bun workspaces root
└── turbo.json                  # Turborepo pipeline config
```

## License

![GitHub license](https://img.shields.io/github/license/mrdemonwolf/wolfwave.svg?style=for-the-badge&logo=github)

## Contact

Questions or feedback?

- Discord: [Join my server](https://mrdwolf.net/discord)
- Issues: [GitHub Issues](https://github.com/MrDemonWolf/WolfWave/issues)
- Docs: [mrdemonwolf.github.io/wolfwave](https://mrdemonwolf.github.io/wolfwave)

---

Made with love by [MrDemonWolf, Inc.](https://www.mrdemonwolf.com)
