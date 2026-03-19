# Changelog

All notable changes to WolfWave will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-03-19

### Added

- Native macOS menu bar app for Apple Music integration
- Real-time now-playing detection via ScriptingBridge
- Twitch chat bot with `!song`, `!currentsong`, `!nowplaying`, `!lastsong`, `!last`, `!prevsong` commands
- Discord Rich Presence showing "Listening to Apple Music" with dynamic album art
- OBS stream widget via built-in WebSocket server (browser source overlay)
- Automatic updates via Sparkle (DMG) and Homebrew
- First-launch onboarding wizard (Welcome, Twitch, Discord, OBS Widget)
- macOS Keychain credential storage (no plain-text tokens)
- Twitch OAuth Device Code authentication flow
- Bot command cooldowns and broadcaster bypass
- Channel validation with Twitch Helix API
- Settings UI with NavigationSplitView sidebar
- Diagnostic log export
- Full reset / danger zone in Advanced settings

[1.0.0]: https://github.com/mrdemonwolf/wolfwave/releases/tag/v1.0.0
