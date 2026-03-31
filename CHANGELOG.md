# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [1.0.2] - 2026-03-31

### Fixed

- App icon missing in CI-built releases (added pre-built .icns fallback for Xcode 16 runners)
- Sparkle updater unable to detect new versions (build number now incremented per release)
- Sparkle initialization race condition (restored synchronous init instead of deferred async)

## [1.0.1] - 2026-03-30

### Changed

- Dropped Intel (x86_64) support — Apple Silicon only
- Raised minimum macOS version to 26.0 (Tahoe)
- Logger: replaced NSLock with serial DispatchQueue for thread-safe file I/O
- TwitchChatService/DiscordRPCService: documented thread safety patterns
- KeychainService: added error logging for all Keychain operations
- AppConstants: cached GitHub repo resolution (no longer recomputes on every access)
- Migrated TwitchViewModel and OnboardingViewModel to @Observable macro
- WhatsNewView: dynamic version string, native button style, v1.0.1 feature highlights
- Narrowed entitlements file exception path
- Added Twitch user ID redaction to log output
- NotificationCenter observers now properly cleaned up on app termination
- Windows (Settings, Onboarding, What's New) properly released on close
- Deferred Sparkle/onboarding init past initial layout to fix layoutSubtreeIfNeeded warning
- Removed duplicate "up to date" alert (Sparkle handles it natively)
- Added VoiceOver accessibility labels across all settings and onboarding views

## [1.0.0] - 2026-03-30

### Added

- Native macOS menu bar app for Apple Music integration
- Real-time now-playing detection via ScriptingBridge and distributed notifications with 2-second fallback polling
- Twitch chat bot with `!song`, `!currentsong`, `!nowplaying`, `!lastsong`, `!last`, `!prevsong` commands
- Discord Rich Presence showing "Listening to Apple Music" with dynamic album art
- OBS stream widget via built-in WebSocket server (browser source overlay)
- Automatic updates via Sparkle for DMG installs; Homebrew Cask installs are updated separately via `brew upgrade --cask wolfwave`
- First-launch onboarding wizard (Welcome, Twitch, Discord, OBS Widget)
- macOS Keychain credential storage (no plain-text tokens)
- Twitch OAuth Device Code authentication flow
- Bot command cooldowns (global + per-user, default 15s) and broadcaster bypass
- Channel validation with Twitch Helix API
- Settings UI with NavigationSplitView sidebar (Music Monitor, App Visibility, Twitch, Discord, OBS Widget, Advanced)
- Unified Music Monitoring panel with integration status indicators
- App visibility modes: menu bar only, dock only, or both
- Diagnostic log export
- Full reset / danger zone in Advanced settings
- CI pipeline with Developer ID certificate import, code signing, notarization via `notarytool`, stapling, and keychain cleanup

### Changed

- **Channel Validation**: Moved Twitch channel name validation from keystroke-triggered to connect-button-triggered. No more API calls while typing — validation happens when you click Connect.
- **Bot Command Toggles**: Fixed bug where disabling a command toggle didn't persist across app restarts. Commands now read their enabled state from UserDefaults at initialization.
- **Command Aliases in Settings**: Bot command toggle rows now show all trigger aliases (e.g., `!song · !currentsong · !nowplaying`).
- **Onboarding Welcome Step**: Updated to list all features (Music Sync, Twitch Chat Bot, Discord Rich Presence, Stream Overlays, Menu Bar) with brand-colored icons.
- **Onboarding Window**: Now centers on screen before showing to prevent flash at origin.
- **Menu Bar Simplified**: Removed now-playing display from the tray icon menu. Menu now contains only Settings, About, and Quit.
- **macOS System Colors**: UI uses system accent colors and semantic colors for automatic light/dark mode support.
- **Discord Auto-Reconnect**: Exponential backoff reconnection (5s base, doubles to 60s cap) with availability polling when Discord is not running.
- **Twitch Reconnection**: Network path monitoring with automatic reconnection on connectivity changes, capped at 5 retry cycles with 60s cooldown.
- **Documentation**: Updated all docs for current features, added Legal section with Privacy Policy and Terms of Service.
- **UX Wording**: Unified feature naming (Music Sync, Now-Playing Widget), standardized empty states, shortened descriptions for ADHD-friendliness
- **Typography Hierarchy**: Established H1/H2/H3 heading system across all settings views
- **Thread Safety**: Fixed MainActor.assumeIsolated crash risks, added lock coverage for Twitch service properties
- **Sparkle Updates**: Completely disabled in DEBUG builds, fixed appcast Ed25519 signing
- **Dev Bundle**: Separate .dev bundle ID for side-by-side development testing

### Removed

- Now-playing track display from the menu bar dropdown (moved to Music Monitor settings preview).

