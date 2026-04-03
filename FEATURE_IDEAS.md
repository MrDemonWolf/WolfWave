# WolfWave — Feature Ideas

Future feature ideas for WolfWave. These are not committed to any release — just a running list of things worth building.

---

## Song Request Queue

Let Twitch viewers request songs via `!request <song name>`. Requests appear in a queue visible from the menu bar. Streamer can approve, skip, or clear.

**Complexity**: Medium
**Builds on**: Existing `BotCommand` protocol, `TwitchChatService`

---

## Listening History & Stats

Track play counts, listening time, and most-played artists locally. Store in a lightweight SQLite database. Add a "Stats" section to the settings sidebar.

**Complexity**: Medium
**Builds on**: `MusicPlaybackMonitor` delegate callbacks, existing settings sidebar pattern

---

## Custom Bot Commands

Let users define their own Twitch bot command responses via the settings UI. For example: `!dj` → "DJ WolfWave in the house 🎧". Stored in UserDefaults as a key-value map.

**Complexity**: Low
**Builds on**: `BotCommand` protocol, `BotCommandDispatcher.registerDefaultCommands()`

---

## Overlay Themes

Ship multiple pre-built WebSocket overlay themes (minimal, retro, neon, glassmorphism). Users pick a theme in settings. Overlay clients receive the theme name and render accordingly.

**Complexity**: Medium
**Builds on**: Existing WebSocket server, browser source overlay

---

## Global Hotkeys

Global keyboard shortcuts to toggle tracking, skip song, or show/hide the overlay — even when WolfWave is in the background.

**Complexity**: Low–Medium
**Approach**: `CGEvent` tap or a lightweight hotkey library

---

## Last.fm Scrobbling

Optional Last.fm integration to automatically scrobble tracks as they play. Uses Last.fm API with OAuth device flow (same pattern as Twitch auth).

**Complexity**: Medium
**Builds on**: `TwitchDeviceAuth` OAuth pattern, `KeychainService`

---

## Menu Bar Now-Playing Ticker

Optionally scroll the current track name in the macOS menu bar status item, like a marquee. Configurable max width. Falls back to static icon when nothing is playing.

**Complexity**: Low
**Builds on**: Existing `NSStatusItem` setup in `AppDelegate`

---

## Multi-Platform Chat Support

Extend the bot beyond Twitch to YouTube Live chat and Kick. Same `BotCommand` protocol, different transport layer per platform.

**Complexity**: High
**Builds on**: `BotCommand` protocol, `BotCommandDispatcher`
