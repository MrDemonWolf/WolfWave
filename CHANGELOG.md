# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- **OBS Stream Widget**: Browser-based overlay for OBS with real-time now-playing display via WebSocket. Supports album artwork with blur background, progress bar with elapsed/remaining time, and auto-hide when playback stops.
- **Widget Themes**: 8 theme presets — Default, Dark, Light, Transparent, Glass (Light), Glass (Dark), Neon, and Techy — each with unique colors, shadows, borders, and backdrop filters.
- **Widget Layouts**: 3 layout styles — Horizontal (500x100), Vertical (220x280), and Compact (350x56) — for different stream overlay placements.
- **Google Fonts Support**: 12 Google Fonts (Montserrat, Roboto, Open Sans, Lato, Poppins, Fira Code, JetBrains Mono, Oswald, Bebas Neue, Raleway, Press Start 2P, Permanent Marker) plus 4 built-in font stacks. All Google Fonts preloaded in a single request for instant switching.
- **Widget Appearance Settings**: Theme, layout, font, text color, and background color pickers in the OBS Widget settings panel. Changes broadcast instantly to connected overlays.
- **Open Widget in Browser**: Button to open the widget URL directly in the default browser for previewing.
- **Widget Auto-Hide on Disconnect**: Widget hides when the WebSocket connection drops and reappears on reconnect with new playback data.
- **WebSocket Server**: NWListener-based local server broadcasting now-playing data, progress updates, playback state changes, and widget config to connected browser sources.
- **Discord Rich Presence**: "Listening to Apple Music" on Discord profile via local IPC Unix domain socket. Shows track, artist, album, and progress bar with dynamic album artwork from iTunes Search API.
- **Artwork Service**: Shared artwork cache with iTunes Search API integration, 512x512 upscaling, and in-memory caching by artist/track key.
- **Bot Command Cooldowns**: Global and per-user cooldown enforcement for chat commands with moderator bypass. Configurable cooldown durations per command in settings.
- **Power State Monitor**: Detects Low Power Mode and thermal pressure to throttle polling intervals for music monitoring, Discord availability checks, and WebSocket progress broadcasts.
- **OBS Widget Onboarding Step**: 4th onboarding step with WebSocket server toggle and widget URL display.
- **Update Banner**: Dismissible in-app banner when a new version is available, with download button linking to the release page.
- **Log Export**: Export application logs to a file via save panel in Advanced settings.
- **Unit Test Suite**: 124+ unit tests across 8 test files covering bot commands, version comparison, onboarding navigation, Twitch view model state, WebSocket server, and app constants integrity.
- **CI Pipeline**: GitHub Actions workflow runs tests on every push and pull request to `main`.
- **Automatic Update Checker**: Checks GitHub Releases for new versions on launch and every 24 hours. Detects Homebrew vs DMG install method and shows appropriate update instructions. Software Update card in Advanced settings with "Check Now", auto-check toggle, and "Skip This Version".
- **Discord Onboarding Step**: 3rd onboarding step with a visual Rich Presence preview and enable toggle.
- **Now Playing Preview Card**: Apple Music-styled now-playing card in Music Monitor settings showing current track, artist, and album with live updates.
- **About Panel Credits**: Clickable links to Documentation, Privacy Policy, and Terms of Service in the About panel.
- **Privacy Policy**: Full privacy policy page at docs site covering data handling, third-party services, and security practices.
- **Terms of Service**: Terms of service page at docs site covering usage terms, disclaimers, and liability.
- **Privacy Manifest**: `PrivacyInfo.xcprivacy` for App Store compliance.
- **Shared View Modifiers**: Reusable SwiftUI modifiers — `pointerCursor()`, `cardStyle()`, `sectionHeader()`, `interactiveRow()`, and `Color(hex:)` initializer.

### Changed

- **Channel Validation**: Moved Twitch channel name validation from keystroke-triggered to connect-button-triggered. No more API calls while typing — validation happens when you click Connect.
- **Bot Command Toggles**: Fixed bug where disabling a command toggle didn't persist across app restarts. Commands now read their enabled state from UserDefaults at initialization.
- **Command Aliases in Settings**: Bot command toggle rows now show all trigger aliases (e.g., `!song · !currentsong · !nowplaying`).
- **Onboarding Welcome Step**: Updated to list all features (Music Monitoring, Twitch Chat Bot, Discord Rich Presence, Stream Overlays, Menu Bar) with brand-colored icons.
- **Onboarding Window**: Now centers on screen before showing to prevent flash at origin.
- **Menu Bar Simplified**: Removed now-playing display from the tray icon menu. Menu now contains only Settings, About, and Quit.
- **macOS System Colors**: UI uses system accent colors and semantic colors for automatic light/dark mode support.
- **Discord Auto-Reconnect**: Exponential backoff reconnection (5s base, doubles to 60s cap) with availability polling when Discord is not running.
- **Twitch Reconnection**: Network path monitoring with automatic reconnection on connectivity changes, capped at 5 retry cycles with 60s cooldown.
- **Documentation**: Updated all docs for current features, added Legal section with Privacy Policy and Terms of Service.

### Removed

- Now-playing track display from the menu bar dropdown (moved to Music Monitor settings preview).

## [1.0.0]

### Added

- **Apple Music Monitoring**: Real-time "Now Playing" tracking via ScriptingBridge and distributed notifications with 2-second fallback polling.
- **Twitch Integration**: OAuth Device Code flow, EventSub WebSocket, and Helix chat API with thread-safe state management.
- **Extensible Bot Commands**: `BotCommand` protocol with `SongCommand` (!song, !currentsong, !nowplaying) and `LastSongCommand` (!last, !lastsong, !prevsong).
- **Twitch Settings UI**: Connection management with device code auth dialog, channel ID input, and join/leave controls.
- **Settings UI**: Multi-panel NavigationSplitView interface covering Music Monitor, App Visibility, Twitch, Discord, OBS Widget, and Advanced sections.
- **Core Utilities**: Keychain-backed credential storage, structured logging with file rotation (5 MB cap), and centralized app constants.
- **App Visibility Modes**: Menu bar only, dock only, or both — configurable in settings.
- **Platform Resources**: macOS entitlements for production and development, Info.plist with build-time config expansion, and asset catalogs with app icon.

### Changed

- **Project Structure**: Finalized initial macOS application layout and architectural scaffold.

### Notes

- This release marks the first stable version of the macOS application.
