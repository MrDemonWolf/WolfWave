# WolfWave — Feature Ideas

Future feature ideas for WolfWave. These are not committed to any release — just a running list of things worth building.

## Progress

- [x] Song Request Queue
- [ ] Listening History & Stats
- [ ] Custom Bot Commands
- [x] Overlay Themes
- [ ] WebSocket Authentication
- [ ] Notification Center Integration
- [ ] Stream Deck Plugin
- [ ] Playlist Detection
- [ ] Chat Voting

**2 of 9 shipped.**

---

## Song Request Queue

Let Twitch viewers request songs via `!request <song name>` or `!sr <song name>`. Requests appear in a queue visible from the menu bar or a dedicated settings view. The streamer can approve, skip, or clear requests.

**URL Support**: Accepts Spotify track URLs (`open.spotify.com/track/...`) and YouTube URLs (`youtube.com/watch?v=...`) — resolves them to Apple Music via the song.link API so the streamer can play the right track.

**Apple Music Search**: Plain-text requests use the iTunes Search API to find the best match, with a confidence threshold to avoid bad guesses.

**Status**: ✅ Done
**Complexity**: Medium–High
**Builds on**: Existing `BotCommand` protocol, `TwitchChatService`, `ArtworkService` (already calls iTunes Search API)

---

## Listening History & Stats

Track play counts, listening time, and most-played artists/tracks locally in a SQLite database. Add a "Stats" section to the settings sidebar with SwiftUI Charts visualizations.

**Monthly Wrap**: Auto-generate a monthly summary (top tracks, top artists, total listening time, genre breakdown) — like a personal Spotify Unwrapped, but for your Apple Music library. Shareable as an image export.

**Twitch Integration**: New `!stats` bot command — e.g. "Most played today: Blinding Lights by The Weeknd (12 plays)".

**Status**: ⬜ Not started
**Complexity**: Medium–High
**Builds on**: `PlaybackSourceDelegate` callbacks, existing settings sidebar pattern, SwiftUI Charts framework

---

## Custom Bot Commands

Let users define their own Twitch bot command responses via the settings UI. For example: `!dj` → "DJ WolfWave in the house 🎧". Stored in UserDefaults as a key-value map.

**Status**: ⬜ Not started
**Complexity**: Low
**Builds on**: `BotCommand` protocol, `BotCommandDispatcher.registerDefaultCommands()`

---

## Overlay Themes

Ship multiple pre-built WebSocket overlay themes (minimal, retro, neon, glassmorphism). Users pick a theme in settings. Overlay clients receive the theme name and render accordingly.

**Status**: ✅ Done
**Complexity**: Medium
**Builds on**: Existing WebSocket server, browser source overlay

---

## WebSocket Authentication

Token-based authentication for widget connections — prevents unauthorized local processes from connecting to the WebSocket server. Configured in Settings → Now-Playing Widget (Advanced).

**Status**: ⬜ Not started
**Complexity**: Low–Medium
**Builds on**: Existing `WebSocketServerService`

---

## Notification Center Integration

Optional macOS notification when the song changes — shows track name, artist, and album art in the system notification. Toggled in Settings → App Visibility.

**Status**: ⬜ Not started
**Complexity**: Low
**Builds on**: `UserNotifications` framework (already imported in `WolfWaveApp.swift`)

---

## Stream Deck Plugin

An Elgato Stream Deck plugin to control WolfWave — toggle Music Sync, trigger song request approval, copy widget URL, etc. Communicates with WolfWave via a local HTTP API.

**Status**: ⬜ Not started
**Complexity**: High
**Approach**: Stream Deck SDK + a lightweight local HTTP server endpoint in WolfWave

---

## Playlist Detection

Show the current playlist name in Discord Rich Presence when playing from a named playlist. Displayed as a secondary line below the artist name.

**Status**: ⬜ Not started
**Complexity**: Low
**Builds on**: ScriptingBridge (Apple Music exposes current playlist via `currentPlaylist`)

---

## Chat Voting

Let Twitch chat vote on the next song from the request queue. Streamer posts the top 2–3 pending requests; chat types `!vote 1`, `!vote 2`, etc. Highest vote wins.

**Status**: ⬜ Not started
**Complexity**: Medium
**Builds on**: Song Request Queue feature, existing `TwitchChatService`
