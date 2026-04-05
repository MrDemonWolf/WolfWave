# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [1.2.0] - 2026-04-04

### Added

- **Docs landing page** — redesigned as a dark, streamer-focused marketing page with brand identity.
- **Theme-aware favicon** — docs site SVG favicon automatically switches between light and dark variants based on system appearance.
- **Shared UI components** — extracted reusable `ConnectionTestButton`, `SectionHeaderWithStatus`, `InfoRow`, and `ConfigRequiredBanner` for consistent settings UI across sections.

### Changed

- **Music playback architecture** — refactored to a pluggable source system (`PlaybackSourceManager` + `PlaybackSource` protocol), laying the groundwork for future music source support beyond Apple Music.
- **AppDelegate decomposed** — split monolithic delegate into focused extensions (`+MenuBar`, `+Services`, `+Windows`) for maintainability.
- **Logger format** — streamlined to local time (`HH:mm:ss.SSS`) with emoji prefixes for faster scanning in Xcode console.
- **Widget appearance settings** — reorganized into a compact 2-per-row layout; dropdown pickers now auto-size to content.
- **Discord & Twitch settings** — unified section headers and connection test buttons using shared components.
- **Code quality** — added MARK sections and DocC comments across 12+ files for better Xcode navigation; added `Color` hex initializer and `NotificationCenter` posting helper.

### Fixed

- Settings window not appearing on screen when opened from the menu bar while in menu-bar-only mode — deferred window show to next run-loop tick after activation policy switch.
- `@MainActor` isolation for `getCurrentSongInfo()` / `getLastSongInfo()` Twitch bot callbacks — replaced `DispatchQueue.main.sync` with `MainActor.assumeIsolated` to satisfy Swift strict concurrency.
- 4 Xcode build warnings — actor isolation annotations in `Logger.swift` and unreachable code in `SparkleUpdaterService.swift`.
- Widget favicon broken reference path.

## [1.1.0] - 2026-03-31

### Added

- **Discord buttons** — Rich Presence now shows two clickable buttons: **Open in Apple Music** (direct track link) and **song.link** (opens on Spotify, YouTube Music, Tidal, and more). Buttons appear whenever a track link resolves, even if artwork isn't available.
- **Launch at Login** — new toggle in Settings → App Visibility. Uses `SMAppService` so it appears in System Settings → General → Login Items. Enabling it automatically switches "Dock Only" mode to "Dock and Menu Bar" so the app is always reachable.
- **Custom DMG background** — installer window now has a polished dark background with the WolfWave brand colors and a drag-to-Applications arrow.
- **Homebrew auto-update** — a GitHub Actions workflow now automatically opens a pull request on the Homebrew tap whenever a new release is published.

### Fixed

- iTunes Search API URL encoding — track and artist names containing `&`, `+`, or `=` no longer produce broken artwork/link lookups (switched to `URLComponents` + `URLQueryItem`).
- Launch at Login toggle now reverts if `SMAppService` registration fails, preventing a mismatch between the UI and actual system state.

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

