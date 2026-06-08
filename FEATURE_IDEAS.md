# WolfWave: Feature Ideas

Future feature ideas for WolfWave. These are not committed to any release. Just a running list of things worth building.

## Pending

- [ ] Custom Bot Commands
- [ ] Stream Deck Plugin

> Shipped ideas previously tracked here (Song Request Queue, Listening History & Stats, Overlay/Widget Themes, Chat Voting, WebSocket Authentication, Notification Center Integration, Playlist Detection) landed in the v2.0.0 release and have been removed from this list. See [`CHANGELOG.md`](CHANGELOG.md) for details.

---

## Custom Bot Commands

Let users define their own Twitch bot command responses via the settings UI. For example: `!dj` → "DJ WolfWave in the house 🎧". Stored in UserDefaults as a key-value map.

**Status**: ⬜ Not started
**Complexity**: Low
**Builds on**: `BotCommand` protocol, `BotCommandDispatcher.registerDefaultCommands()`

---

## Stream Deck Plugin

An Elgato Stream Deck plugin to control and monitor WolfWave from physical keys. The streamer's most-used WolfWave actions become one-press buttons that also reflect live state (track title, queue size, connection health).

**How it works**: A Stream Deck plugin is a standalone process bundled as a `.sdPlugin` folder and installed into Elgato's Stream Deck app. The Stream Deck app launches the plugin and exchanges JSON events with it over a WebSocket. Because the plugin runs on the same Mac as WolfWave, it talks to WolfWave over `localhost`. Built with Elgato's official TypeScript/Node SDK (`@elgato/streamdeck`); a `manifest.json` declares each Action, its icons/states, and an HTML Property Inspector for settings (WolfWave port + auth token).

**The control-API gap**: WolfWave's `WebSocketServerService` currently _broadcasts_ now-playing data but ignores inbound frames, and `WidgetHTTPService` is GET-only, so there is no way to send commands _into_ the app. The recommended fix is to make the WebSocket **bidirectional**: handle inbound JSON command messages in `WebSocketServerService.receiveMessage`. The plugin then uses one connection for both the live now-playing feed and outbound commands. The existing v2.0.0 widget auth token already gates who may issue commands.

**Action ideas**:

- **Now Playing**: display-only key showing scrolling track/artist with album art as the key image, driven by the existing `now_playing` broadcast.
- **Play / Pause**: toggle Apple Music playback; key reflects state.
- **Skip Song**: skip the current track / advance the request queue.
- **Music Sync toggle**: enable/disable playback tracking; on/off state on the key.
- **Hold / Resume Queue**: toggle song-request hold mode; key shows held vs. accepting.
- **Approve Next Request**: approve and play the next queued song request.
- **Clear Queue**: clear pending requests, guarded by a long-press confirmation.
- **Queue Counter**: key title shows the pending-request count; changes color when > 0.
- **Block Current Song**: add the playing track to the song-request blocklist.
- **Copy Widget URL**: copy the overlay URL to the clipboard with `showOk` feedback.
- **Toggle Overlay Server**: start/stop the WebSocket overlay server.
- **Discord Presence toggle**: enable/disable Discord Rich Presence.
- **Twitch Connection**: connect/disconnect the bot; key shows connected state.
- **Announce Song**: manually post the now-playing line to Twitch chat.
- **Cycle Widget Theme**: step through the 6 widget themes.
- **Stream Health**: one key aggregating Twitch + Discord + overlay status into a color-coded glance.

**Stream Deck + (dial) ideas**: a now-playing dial whose touchscreen shows album art and progress, with rotation bound to Apple Music volume.

**Distribution**: ship via the Elgato Marketplace for discoverability among streamers. The plugin is a separate TypeScript/Node codebase (likely a new `apps/streamdeck/` workspace in the monorepo, or its own repo). Version the WolfWave command protocol so the plugin and app can detect a mismatch.

**Implementation sketch** (for when this is picked up):

1. **App side: inbound command channel.** Make `WebSocketServerService.receiveMessage` parse inbound text frames instead of discarding them. Define a command envelope, e.g. `{ "type": "command", "action": "skip", "token": "...", "protocol": 1 }`. Reject frames whose token doesn't match the widget auth token and unknown/incompatible `protocol` versions.
2. **App side: command router.** Add a small dispatcher that maps each `action` to existing services: `skip`/`playPause` → `AppleMusicController`, `hold`/`resume`/`clearQueue`/`approveNext` → `SongRequestService` / `SongRequestQueue`, `blockCurrent` → `SongBlocklist`, `toggleMusicSync` → playback tracking, `toggleDiscord` → `DiscordRPCService`, `toggleOverlay` → `setEnabled`, `cycleTheme` → widget theme `UserDefaults` + `broadcastWidgetConfig()`. Send a JSON ack back so the plugin can update key state.
3. **App side: state for keys.** The plugin already gets `now_playing` / `playback_state` / `progress`. Add broadcasts for queue size and connection health so the Queue Counter and Stream Health keys can render without polling.
4. **Plugin side: scaffold.** New `apps/streamdeck/` bun workspace; scaffold with the `@elgato/streamdeck` CLI. One Action class per idea above; `manifest.json` declares Actions, states, and icons.
5. **Plugin side: connection.** Plugin opens a WebSocket to WolfWave on the configured port, subscribes to the broadcast feed for key state, and sends command envelopes on `keyDown`. Handle WolfWave-not-running with a clear disconnected key state.
6. **Plugin side: Property Inspector.** HTML settings pane to enter the WolfWave WebSocket port and auth token.
7. **Distribution.** Package the `.sdPlugin`, submit to the Elgato Marketplace; document install in `apps/docs`.

**Status**: ⬜ Not started
**Complexity**: High
**Approach**: Elgato `@elgato/streamdeck` SDK + a bidirectional command channel on `WebSocketServerService` (handle inbound JSON in `receiveMessage`)
**Builds on**: Existing `WebSocketServerService` broadcast feed; the v2.0.0 widget auth token gates inbound commands
