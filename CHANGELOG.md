# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- **Unit Test Suite**: 124 unit tests across 7 test files covering bot commands, version comparison, onboarding navigation, Twitch view model state, and app constants integrity. Test target auto-discovers new `.swift` files.
- **CI Pipeline**: GitHub Actions workflow (`.github/workflows/ci.yml`) runs tests on every push and pull request to `main`.
- **Automatic Update Checker**: Checks GitHub Releases for new versions on launch and every 24 hours. Detects Homebrew vs DMG install method and shows appropriate update instructions. Software Update card in Advanced settings with "Check Now", auto-check toggle, and "Skip This Version".
- **Discord Onboarding Step**: 3rd onboarding step with a visual Rich Presence preview and enable toggle.
- **Now Playing Preview Card**: Apple Music-styled now-playing card in Music Monitor settings showing current track, artist, and album.
- **About Panel Credits**: Clickable links to Documentation, Privacy Policy, and Terms of Service in the About panel.
- **Privacy Policy**: Full privacy policy page at docs site covering data handling, third-party services, and security practices.
- **Terms of Service**: Terms of service page at docs site covering usage terms, disclaimers, and liability.
- **Privacy Manifest**: `PrivacyInfo.xcprivacy` for App Store compliance.

### Changed

- **Channel Validation**: Moved Twitch channel name validation from keystroke-triggered to connect-button-triggered. No more API calls while typing — validation happens when you click Connect.
- **Bot Command Toggles**: Fixed bug where disabling a command toggle didn't persist across app restarts. Commands now read their enabled state from UserDefaults at initialization.
- **Command Aliases in Settings**: Bot command toggle rows now show all trigger aliases (e.g., `!song · !currentsong · !nowplaying`).
- **Onboarding Welcome Step**: Updated to list all features (Music Monitoring, Twitch Chat Bot, Discord Rich Presence, Stream Overlays, Menu Bar) with brand-colored icons.
- **Onboarding Window**: Now centers on screen before showing to prevent flash at origin.
- **Menu Bar Simplified**: Removed now-playing display from the tray icon menu. Menu now contains only Settings, About, and Quit.
- **macOS System Colors**: UI uses system accent colors and semantic colors for automatic light/dark mode support.
- **Documentation**: Updated all docs for current features, added Legal section with PP and TOS.

### Removed

- Now-playing track display from the menu bar dropdown (moved to Music Monitor settings preview).

## [1.0.0]

### Added

- **Apple Music Monitoring**: Real-time "Now Playing" tracking via `MusicPlaybackMonitor.swift` utilizing ScriptingBridge and distributed notifications.
- **Twitch Integration**: Full support for OAuth Device Code flow (`TwitchDeviceAuth.swift`), EventSub WebSocket, and Helix chat services (`TwitchChatService.swift`).
- **Extensible Bot Commands**: Implementation of `BotCommand.swift`, `BotCommandDispatcher.swift`, and specific commands like `SongCommand.swift` and `LastSongCommand.swift`.
- **Twitch UI & Auth**: Connection management views including `TwitchViewModel.swift`, `DeviceCodeView.swift`, `TwitchReauthView.swift`, and `TwitchSettingsView.swift`.
- **WebSocket Broadcasting**: Ability to stream playback updates to overlays via `WebSocketSettingsView.swift` with Keychain-backed token support.
- **Settings UI**: Multi-panel interface via `SettingsView.swift` covering `AdvancedSettings`, `AppVisibility`, and `MusicMonitorSettings`.
- **Core Utilities**: Secure credential storage via `KeychainService.swift`, centralized categorized logging via `Logger.swift`, and application constants.
- **Platform Resources**: macOS entitlements for both production and development, `Info.plist` configurations, and high-resolution asset catalogs.

### Changed

- **Project Structure**: Finalized initial macOS application layout and architectural scaffold.

### Notes

- This release marks the first stable version of the macOS application.
