# Changelog

All notable changes to WolfWave are documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-03-19

### Added

#### Apple Music Integration
- Real-time now-playing monitoring via ScriptingBridge and distributed notifications
- 2-second fallback polling for reliability
- Delegate-based architecture (`MusicPlaybackMonitorDelegate`) for loose coupling

#### Twitch Chat Bot
- OAuth Device Code flow for secure, browser-based authentication
- `!song` command — displays the currently playing track in chat
- `!last` / `!lastsong` / `!prevsong` commands — displays the previously played track
- Per-command cooldowns and enable/disable toggles (opt-in by default)
- EventSub WebSocket for real-time chat events with Helix API message delivery
- Automatic reconnection with network path monitoring
- 500-character response limit with truncation guards

#### Discord Rich Presence
- "Listening to Apple Music" status via local IPC (Unix domain socket)
- Album artwork fetched from iTunes Search API with in-memory cache
- Auto-reconnect with exponential backoff

#### OBS Stream Overlay
- Local WebSocket + HTTP server for OBS browser source integration
- 5 visual themes and 3 layout options
- System font support for native look
- Widget HTTP server (opt-in by default)

#### Auto-Updates
- Sparkle framework integration for seamless in-app updates
- Appcast XML feed hosted alongside GitHub Releases

#### Onboarding Wizard
- 4-step first-launch flow: Welcome, Twitch setup, Discord setup, OBS Widget setup
- ADHD-friendly instructional text — clear, concise, and action-oriented

#### Power Management
- Low Power Mode detection — reduces polling frequency to conserve battery
- Thermal throttling awareness — backs off background work under thermal pressure

#### App Experience
- Dynamic system tray menu with contextual actions
- Settings window with `NavigationSplitView` sidebar (Music, Twitch, Discord, WebSocket, Advanced)
- Opt-in defaults for bot commands and widget HTTP server
- Keychain-backed credential storage (tokens never touch UserDefaults)
- Structured logging via unified `Logger`
- 210 unit tests across 16 test files
