# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- Apple Music — Real-time "Now Playing" monitoring via `MusicPlaybackMonitor.swift` (ScriptingBridge + distributed notifications).
- Twitch integration — OAuth Device Code flow (`TwitchDeviceAuth.swift`), EventSub WebSocket + Helix chat service (`TwitchChatService.swift`), and an extensible bot command system (`BotCommand.swift`, `BotCommandDispatcher.swift`, `SongCommand.swift`, `LastSongCommand.swift`).
- Twitch UI & auth — `TwitchViewModel.swift`, `DeviceCodeView.swift`, `TwitchReauthView.swift`, `TwitchSettingsView.swift` for sign-in and connection management.
- WebSocket broadcasting — optional overlay streaming support and auth handling (`WebSocketSettingsView.swift`, Keychain-backed tokens).
- Settings UI — primary `SettingsView.swift` and related panels (`AdvancedSettingsView.swift`, `AppVisibilitySettingsView.swift`, `MusicMonitorSettingsView.swift`) with toggles for tracking and bot commands.
- Core utilities — secure storage (`KeychainService.swift`), logging (`Logger.swift`), app constants (`AppConstants.swift`), and app entry (`WolfWaveApp.swift`).
- Platform & resources — macOS entitlements (`wolfwave.entitlements`, `wolfwave.dev.entitlements`), `Info.plist` entries, app icons, and asset catalogs.

### Changed

- Project scaffold and initial macOS app layout.

### Notes

- This changelog focuses exclusively on the macOS app (documentation site entries were intentionally omitted).
- To publish a release, replace `[Unreleased]` with a version (e.g. `v0.1.0`) and add the release date.
