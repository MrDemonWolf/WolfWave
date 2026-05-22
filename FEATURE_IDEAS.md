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

An Elgato Stream Deck plugin to control and monitor WolfWave from physical keys — the streamer's most-used WolfWave actions become one-press buttons that also reflect live state (track title, queue size, connection health).

**How it works**: A Stream Deck plugin is a standalone process bundled as a `.sdPlugin` folder and installed into Elgato's Stream Deck app. The Stream Deck app launches the plugin and exchanges JSON events with it over a WebSocket. Because the plugin runs on the same Mac as WolfWave, it talks to WolfWave over `localhost`. Built with Elgato's official TypeScript/Node SDK (`@elgato/streamdeck`); a `manifest.json` declares each Action, its icons/states, and an HTML Property Inspector for settings (WolfWave port + auth token).

**The control-API gap**: WolfWave's `WebSocketServerService` currently _broadcasts_ now-playing data but ignores inbound frames, and `WidgetHTTPService` is GET-only — there is no way to send commands _into_ the app. The recommended fix is to make the WebSocket **bidirectional**: handle inbound JSON command messages in `WebSocketServerService.receiveMessage`. The plugin then uses one connection for both the live now-playing feed and outbound commands. This should land alongside the **WebSocket Authentication** idea so a token gates who may issue commands.

**Action ideas**:

- **Now Playing** — display-only key showing scrolling track/artist with album art as the key image, driven by the existing `now_playing` broadcast.
- **Play / Pause** — toggle Apple Music playback; key reflects state.
- **Skip Song** — skip the current track / advance the request queue.
- **Music Sync toggle** — enable/disable playback tracking; on/off state on the key.
- **Hold / Resume Queue** — toggle song-request hold mode; key shows held vs. accepting.
- **Approve Next Request** — approve and play the next queued song request.
- **Clear Queue** — clear pending requests, guarded by a long-press confirmation.
- **Queue Counter** — key title shows the pending-request count; changes color when > 0.
- **Block Current Song** — add the playing track to the song-request blocklist.
- **Copy Widget URL** — copy the overlay URL to the clipboard with `showOk` feedback.
- **Toggle Overlay Server** — start/stop the WebSocket overlay server.
- **Discord Presence toggle** — enable/disable Discord Rich Presence.
- **Twitch Connection** — connect/disconnect the bot; key shows connected state.
- **Announce Song** — manually post the now-playing line to Twitch chat.
- **Cycle Widget Theme** — step through the 6 widget themes.
- **Stream Health** — one key aggregating Twitch + Discord + overlay status into a color-coded glance.

**Stream Deck + (dial) ideas**: a now-playing dial whose touchscreen shows album art and progress, with rotation bound to Apple Music volume.

**Distribution**: ship via the Elgato Marketplace for discoverability among streamers. The plugin is a separate TypeScript/Node codebase — likely a new `apps/streamdeck/` workspace in the monorepo, or its own repo. Version the WolfWave command protocol so the plugin and app can detect a mismatch.

**Implementation sketch** (for when this is picked up):

1. **App side — inbound command channel.** Make `WebSocketServerService.receiveMessage` parse inbound text frames instead of discarding them. Define a command envelope, e.g. `{ "type": "command", "action": "skip", "token": "...", "protocol": 1 }`. Reject frames whose token doesn't match (depends on the **WebSocket Authentication** idea) and unknown/incompatible `protocol` versions.
2. **App side — command router.** Add a small dispatcher that maps each `action` to existing services: `skip`/`playPause` → `AppleMusicController`, `hold`/`resume`/`clearQueue`/`approveNext` → `SongRequestService` / `SongRequestQueue`, `blockCurrent` → `SongBlocklist`, `toggleMusicSync` → playback tracking, `toggleDiscord` → `DiscordRPCService`, `toggleOverlay` → `setEnabled`, `cycleTheme` → widget theme `UserDefaults` + `broadcastWidgetConfig()`. Send a JSON ack back so the plugin can update key state.
3. **App side — state for keys.** The plugin already gets `now_playing` / `playback_state` / `progress`. Add broadcasts for queue size and connection health so the Queue Counter and Stream Health keys can render without polling.
4. **Plugin side — scaffold.** New `apps/streamdeck/` bun workspace; scaffold with the `@elgato/streamdeck` CLI. One Action class per idea above; `manifest.json` declares Actions, states, and icons.
5. **Plugin side — connection.** Plugin opens a WebSocket to WolfWave on the configured port, subscribes to the broadcast feed for key state, and sends command envelopes on `keyDown`. Handle WolfWave-not-running with a clear disconnected key state.
6. **Plugin side — Property Inspector.** HTML settings pane to enter the WolfWave WebSocket port and auth token.
7. **Distribution.** Package the `.sdPlugin`, submit to the Elgato Marketplace; document install in `apps/docs`.

**Status**: ⬜ Not started
**Complexity**: High
**Approach**: Elgato `@elgato/streamdeck` SDK + a bidirectional command channel on `WebSocketServerService` (handle inbound JSON in `receiveMessage`)
**Builds on**: Existing `WebSocketServerService` broadcast feed; pairs with the **WebSocket Authentication** idea for command auth

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
