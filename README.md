<div align="center">
  <img src="assets/logo-256.png" alt="WolfWave" width="128" />
</div>

# WolfWave - Your Music, Everywhere on Stream

Stop telling chat what song is playing. WolfWave is a tiny native macOS
menu bar app that bridges Apple Music with Twitch chat, Discord Rich
Presence, and OBS stream overlays. Play something in Apple Music — your
Twitch chat, your Discord profile, and your stream overlay all update on
their own.

Free, open source, signed and notarized by Apple. Built for streamers
and creators on macOS.

## Features

- **Now Playing in Twitch Chat** — Viewers type `!song`, `!currentsong`, or `!nowplaying` and instantly see the track you're spinning.
- **Song Requests** — Viewers request songs with `!sr <track>`. Requests play through Apple Music without taking focus from OBS.
- **Channel Points & Bits** — WolfWave-managed "Request a Song" channel-point reward, plus bit cheers that boost the cheerer's queued track to the front.
- **Chat Vote-Skip** — Viewers vote off a song with `!voteskip` / `!vs`. Choose chat-tally mode or native Twitch Polls.
- **Hold-Mode Queue** — Mods can hold, resume, skip, and clear the request queue from chat or the menu bar.
- **Live Queue View** — See what's playing, what's next, and who requested each track right inside the app.
- **Fallback Playlist** — Configure an Apple Music playlist that takes over when the queue runs dry.
- **Listening History & Stats** — Opt-in, on-device log of what you actually play. Top artists, listening time, 7-day trend, and a listening-by-hour chart built on SwiftUI Charts.
- **Monthly Wrap** — A personal "wrapped"-style summary for any month, exportable as a shareable PNG.
- **`!stats` in Chat** — Viewers ask for today's top track; replies only while you're live.
- **Discord Rich Presence** — Shows "Listening to WolfWave" on your Discord profile with Apple Music album art, the active Apple Music playlist, and clickable open-in-Apple-Music + song.link buttons.
- **Stream Widgets** — Drop-in browser source overlay powered by a local WebSocket server with a per-install auth token, six themes (`Default`, `Dark`, `Light`, `Glass`, `Neon`, `WolfWave`), and three layouts (`Horizontal`, `Vertical`, `Compact`). Two-PC streamers can connect from a second machine on the LAN.
- **Streamer Mode** — One-tap tray toggle that masks the connected Twitch channel name, widget URLs, and auth token across the UI so the app is safe to show on camera.
- **Song-Change Notifications** — Opt-in macOS banner on every track change, with album art. The banner replaces in place instead of stacking.
- **On-Device Diagnostics** — Opt-in MetricKit diagnostics card with a share helper for attaching reports to a bug filing. Reports stay on-device.
- **macOS 26 Liquid Glass Design** — Refreshed onboarding, settings, and menu bar built for Tahoe.
- **Secure by Default** — Credentials live in the macOS Keychain, never plain text.
- **Automatic Updates** — Sparkle (DMG) or Homebrew (`brew upgrade --cask`).
- **Bug Report Flow** — One-click log export and pre-filled GitHub issue from Advanced settings.

## Getting Started

Full docs at [mrdemonwolf.github.io/wolfwave](https://mrdemonwolf.github.io/wolfwave).

### DMG Installer (recommended)

1. Grab the latest `.dmg` from [GitHub Releases](https://github.com/MrDemonWolf/WolfWave/releases).
2. Open the DMG and drag **WolfWave** to **Applications**.
3. Launch WolfWave and follow the onboarding wizard.

### Homebrew (for developers)

```bash
brew tap mrdemonwolf/den
brew install --cask wolfwave
```

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
| `!voteskip` `!vs` | Casts a vote to skip the current song |
| `!stats` | Shows today's top track (live only) |

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

### Stream Widgets

Enable in **Settings > Stream Widgets** to start a local WebSocket
server. Copy the widget URL (auth token auto-injected) and add it as a
Browser Source (500 x 120) in OBS. Two-PC streamers can reach the
overlay from a second computer or phone on the same network. Regenerate
the token from Settings to drop every active client.

## Tech Stack

| Layer | Technology |
| --- | --- |
| Language | Swift 5.9+ |
| UI | SwiftUI, AppKit |
| Platform | macOS 26.0+ (Tahoe), Apple Silicon, Apple Music app required |
| Music | ScriptingBridge, MusicKit, AppleScript |
| Twitch | EventSub WebSocket, Helix API |
| Discord | Rich Presence via local IPC Unix domain socket |
| Networking | URLSession, Network framework, NWListener (WebSocket overlay) |
| Updates | Sparkle (EdDSA-signed appcast) |
| Charts | SwiftUI Charts (History & Stats) |
| Diagnostics | MetricKit (opt-in) |
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
cp apps/native/WolfWave/Config.xcconfig.example apps/native/WolfWave/Config.xcconfig
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
- `make test` — Run the unit test suite (see CHANGELOG.md for current counts).
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
- Unit tests auto-discovered via Xcode synchronized groups under `apps/native/WolfWaveTests/`.

## Project Structure

```text
wolfwave/
├── apps/
│   ├── native/                 # Native macOS app (Swift, SwiftUI, AppKit)
│   │   ├── WolfWave/           # App source
│   │   ├── WolfWaveTests/      # Unit tests
│   │   └── WolfWave.xcodeproj  # Xcode project
│   ├── docs/                   # Fumadocs documentation site
│   └── marketing/              # Remotion-based promo videos
├── assets/                     # Brand assets, logos
├── CHANGELOG.md                # Release history
├── Makefile                    # Build, test, release targets
├── package.json                # bun workspaces root
└── turbo.json                  # Turborepo pipeline config
```

## License

[![GitHub license](https://img.shields.io/github/license/mrdemonwolf/wolfwave.svg?style=for-the-badge&logo=github)](https://github.com/mrdemonwolf)

WolfWave is released under the MIT License.

## Contact

Questions or feedback?

- Discord: [Join my server](https://mrdwolf.net/discord)
- Issues: [GitHub Issues](https://github.com/MrDemonWolf/WolfWave/issues)
- Docs: [mrdemonwolf.github.io/wolfwave](https://mrdemonwolf.github.io/wolfwave)

---

Made with love by [MrDemonWolf, Inc.](https://www.mrdemonwolf.com)
