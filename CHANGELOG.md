# Changelog

All notable changes to this project will be documented in this file.

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
