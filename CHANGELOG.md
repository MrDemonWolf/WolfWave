# Changelog

All notable changes to this project will be documented in this file.

## [2.0.0] - Unreleased

### Security

- **Stream Widgets auth token** — the overlay WebSocket and widget HTTP server now require a per-install authentication token. Connections without a matching `wolfwave.token.<hex>` subprotocol are rejected on the handshake before any playback data is sent. The token is minted on first launch, stored in the macOS Keychain, and auto-injected into the widget URL and served `widget.html` so existing OBS browser sources keep working without manual changes. Settings → Stream Widgets exposes the token behind an eye toggle (hidden by default), a Regenerate button, and a free-form edit field for streamers who want to supply their own value; regenerating or editing the token drops every active client until they reconnect with the new credential.

### Added

- **Streamer Mode** — new toggle in the tray menu (Streamer Quick Actions) that masks sensitive values across the WolfWave UI so the app is safe to show on camera. Hides the connected Twitch channel name in the menu and Settings, the overlay/widget URLs and WebSocket URI in Stream Widgets settings and onboarding, and force-hides + disables the WebSocket auth token controls. Copy/Open buttons next to masked values are disabled so screenshots can't reveal the underlying value via accessibility. UI-only redaction — the WebSocket broadcast payload, Discord Rich Presence, and Twitch chat output are unaffected.
- **Chat Vote-Skip** — viewers can vote to skip the current song with `!voteskip` / `!vs`. A passed vote skips the now-playing request, or advances the Apple Music track when the queue is idle. Chat-tally mode counts unique voters within a configurable window against a minimum-vote threshold; opt-in Twitch Polls mode (Affiliate/Partner) opens a native poll instead. Configurable minimum votes, vote window, cooldown, and subscriber-only voting in Settings → Song Requests → Chat Vote-Skip.
- **Listening History** — opt-in, on-device log of the tracks you play (append-only NDJSON, never uploaded). Off by default; turn it on in Settings → History & Stats or during onboarding. A track is recorded once it has played past half its length (or 4 minutes), so skips don't count.
- **Stats & Charts** — top artists, listening time, a 7-day play trend, and a listening-by-hour breakdown in the new History & Stats settings section, built on SwiftUI Charts. Requires Listening History.
- **Monthly Wrap** — a personal "wrapped"-style summary for any month, exportable as a shareable PNG.
- **`!stats` command** — viewers can ask for today's top track in Twitch chat; replies only while the stream is live (via `stream.online` / `stream.offline` EventSub).
- **Song Requests** — viewers can request songs in Twitch chat via `!sr <song>`; plays through Music.app via AppleScript with no focus-steal on the streamer's screen.
- **`!queue` / `!myqueue`** — show the full request queue or a viewer's own requests in chat.
- **`!skip` / `!next`** — mod/broadcaster-only command to skip the current request.
- **`!clearqueue`** — mod/broadcaster-only command to wipe the queue (with in-app confirmation dialog).
- **`!hold` / `!resume` / `!unhold`** — mod/broadcaster-only hold mode; new requests buffer without auto-playing so the streamer can curate before releasing the queue.
- **Hold controls** — Hold/Resume button in the Song Request Queue settings view and a toggle item in the menu bar dropdown.
- **Music.app closed buffering** — requests are saved when Music.app is closed and flushed automatically when it reopens (hold mode is respected).
- **Fallback playlist** — configure an Apple Music playlist to play when the request queue empties.
- **Song Request Queue UI** — full queue view with now-playing card, position badges, per-requester labels, and Skip / Hold / Clear controls.
- **Per-user and global request limits**, subscriber-only mode, per-command enable/disable toggles, and custom alias configuration.
- **Custom aliases for `!song`, `!last`, and `!stats`** — comma-separated alias fields in Settings → Twitch and Settings → History & Stats. Aliases honor the same enable, cooldown, and Twitch live-gate rules as the canonical command. Fixes a latent bug where aliases matched in the dispatcher but the command returned no reply.
- **Hold-queue toggle in Song Request settings** — flip the request queue between Hold and Playing directly from the Playback card; previously reachable only via the menu bar and queue view.
- **Recreate Reward button** — clears the stored Channel-Point reward ID and forces WolfWave to create a fresh "Request a Song" reward on Twitch. Use after manually deleting the reward on the Twitch dashboard. The managed reward ID renders below the cost picker (masked when Streamer Mode is on).
- **History retention picker** — pick how many days of listening history to keep (Forever / 7 / 30 / 90 / 180 / 365). Older entries are pruned at next launch.
- **macOS 26 Liquid Glass onboarding redesign** — full wizard rebuild with two new steps (Menu Bar Pointer + OBS Widget) to match Tahoe's design language (#26).
- **Apple Music onboarding step** — first-launch wizard authorizes MusicKit library access for song search with a graceful denied-state recovery path.
- **OBS Widget onboarding step** — overlay URL preview and HTTP widget toggle wired directly into onboarding so streamers can copy the overlay link before completing setup (d62b8ac).
- **macOS 26 Liquid Glass redesign foundation** — refreshed settings + menu bar chrome with native Liquid Glass materials and Music permission flow (#22, #26).
- **LAN IP cache** — `NetworkInfoService` caches the local IP for the overlay/widget URL surface so settings views no longer block on lookup (#34).
- **Diagnostics + bug report flow** — Advanced settings gains Export Logs and Clear Logs actions plus a one-click "Report a Bug" flow that pre-fills a GitHub issue with redacted log context (#50).
- **Branded About panel** — replaced the default `NSAboutPanelOptionKey` sheet with a native SwiftUI About window built around WolfWave's identity (#55).
- **Apple Music logo on Music access row** — granted-state row now shows the Apple Music brand mark instead of a generic icon (#38).
- **Widget themes** — six selectable overlay-widget themes (`Default`, `Dark`, `Light`, `Glass`, `Neon`, `WolfWave`) and three layouts (`Horizontal`, `Vertical`, `Compact`), served to `widget.html` via `window.WW_TOKENS` (#76).
- **Discord presence polish** — friendlier presence buttons, a live presence preview in Discord settings, and cleaner connection-state handling (#73).
- **Song-change notifications** — opt-in macOS notification on every track change, with track name, artist, and album art; reuses a stable identifier so a new song replaces the previous banner instead of stacking. Off by default; enable in Settings → General → Notifications (#83).
- **Skip-vote notifications** — opt-in macOS notifications when a chat skip-vote starts and when it passes. The "started" banner is silent and reports the vote threshold (or points at the open Twitch poll); the "passed" banner names the skipped track and plays the default system sound. Both off by default in Settings → Notifications, where they stay disabled until Chat Vote-Skip is turned on. The onboarding Permissions step also lets you pick which alerts you want.
- **On-device diagnostics** — opt-in MetricKit diagnostics report card in Advanced settings. Reports stay on-device; a share card lets you attach the payload to a bug report manually. Off by default (#85).
- **Discord playlist presence** — Discord Rich Presence now surfaces the current Apple Music playlist name alongside the track when one is active.
- **WolfMark branding** — new WolfMark album-art placeholder replaces the generic music icon in the now-playing card and overlay widget; branded download page, repo `README.md`, and `SECURITY.md` shipped alongside.
- **OBS widget transitions** — the now-playing overlay now slides in with a subtle bounce when a song starts and slides + blurs out calmly when playback stops, with the progress bar draining smoothly to zero. Skipping a track while the widget is visible crossfades the inner artwork + metadata instead of re-triggering the entrance, so rapid skips no longer strobe the stream. Pause behavior is unchanged — the card stays mounted while music is paused.

### Changed

- **Music playback via AppleScript + focus preservation** — Music.app never steals focus from OBS or other streaming tools; the previously active app is restored 150 ms after each command.
- **MusicKit used exclusively for search/resolve**, not playback — no in-app audio session.
- **Settings views decomposed** — split the monolithic `SettingsView` into per-section files (`GeneralSettingsView`, `MusicMonitorSettingsView`, `AppVisibilitySettingsView`, `TwitchSettingsView`, `DiscordSettingsView`, `WebSocketSettingsView`, `SongRequestSettingsView`, `AdvancedSettingsView`) for sharper redraws and easier editing (#34).
- **Onboarding flow polish** — dropped redundant success rows, tightened Apple Music permission step copy, stable button + step sizing to eliminate UI shift (#21, #25, #28).
- **Notifications toggle** — disables itself once permission is authorized and unifies the denied state across the wizard (#29).
- **Onboarding permissions consolidated** — the Apple Music access step, the notification-permission ask, and the per-alert notification toggles now live together in a single "Permissions" step instead of separate screens.
- **`PillButton`** — replaced `Capsule` with the macOS-standard rounded rectangle to match system button geometry (#30).
- **Menu bar preview tray icon** — loads via `NSImage` for crisp rendering at every density (#32).
- **Settings window sizing** — minimum and ideal dimensions tuned to fit cleanly on 720p and 1080p displays without clipping (#33).
- **Music permission row** — actionable + self-healing; tapping it re-requests or deep-links to System Settings depending on authorization state (#31).
- **OBS step copy** — onboarding OBS Widget step collapsed to a single toggle with the overlay URL promoted to first-class status (#36).
- **OBS branding in settings** — swapped the bespoke OBS logo for the `tv.badge.wifi` SF Symbol so the chip respects template tinting (#46).
- **AdvancedSettingsView** — refactored to use the shared `cardStyle()` helper for consistent material + corner radii (#52).
- **User-facing wording** — tightened copy across onboarding, settings, and the menu bar for fewer words and clearer verbs (#47).
- **Test suite consolidation** — merged `SongCommandTests` + `LastSongCommandTests` into a single parameterised `TrackInfoCommandTests`; renamed `MusicPlaybackMonitorTests` → `AppleMusicSourceTests` to match the post-refactor class names. 408 tests across 30 files, all passing.
- **Design-token migration completed** — settings views now read from `DSFont` and `DSSpace` across every view file; no hardcoded `.font(.system(size:))` or `.padding(N)` literals remain in `apps/native/WolfWave/Views/`. Added missing tokens (`x9/x15/x16/x18/x24/x26/x28/x36` font sizes, `s0/s10/s11` space) to `design-system/tokens.json`.
- **Concurrency polish** — replaced stray `DispatchQueue.main.async` sites in `AppDelegate+MenuBar`, `DiscordSettingsView`, and `AppleMusicController` with structured `Task { @MainActor }` for Swift 6 cleanliness; matches the project rule that new async work uses async/await, not `DispatchQueue`.
- **Logger regex literals** — `Logger.swift` PII-redaction patterns now use compile-checked `#/.../#` literals instead of `try! Regex(...)`, dropping the SwiftLint `force_unwrapping` warnings.
- **Liquid Glass onboarding surface** — the wizard content panel now renders on a `.glassEffect(.regular)` material, matching the glass convention used by settings cards and the now-playing card (#198).
- **Streamer Mode Twitch account masking** — the signed-in Twitch account name in Settings is now masked when Streamer Mode is on, matching the existing channel-ID rows and menu bar (#198).
- **Onboarding step accessibility** — VoiceOver now announces the current step by name ("Step 3 of 7: Twitch") via `accessibilityHint` and `accessibilityValue` on the progress dots (#198).

### Performance

- **Timer wakeup coalescing** — periodic timers (fallback poll, WebSocket progress tick, Discord availability poll, song-request auto-advance) now carry leeway/tolerance so macOS can batch their wakeups together, cutting idle energy use for an all-day menu bar app. Real-time track changes still arrive via distributed notifications; polling behavior is otherwise unchanged (#199).
- **Settings page switch latency** — eliminated jank when navigating between settings sections (#51).
- **Font enumeration deferred off main** — Widget Setup network row no longer blocks the main thread on first paint (#54).
- **Now-Playing Server row** — renders instantly thanks to the cached LAN IP lookup (#39).

### Developer

> Developer-facing changes — not visible to end users.

- **Unified design system** — a single `design-system/tokens.json` source feeds `generate.ts`, which emits four platform outputs (Swift `Tokens.generated.swift`, docs CSS, widget JS, and marketing TS). A Turbo `tokens` task runs as a build prerequisite (#72, #76).
- **Component catalog** — `design-system/components/` gains one markdown entry per reusable view, tracked against a shared template (#76).
- **DEBUG-only Debug settings tab** — a developer tooling tab (inspectors, service controls, log/event views, UI previews) plus What's New preview controls, available only in DEBUG builds (#66, #69).
- **Expanded design-token roster** — `font.size` gains explicit slots for the 9/15/16/18/24/26/28/36 px sizes that appear across views; `space` gains `s0` (2 px), `s10` (32 px), and `s11` (44 px). All additions are token-only (no visual change) so the migration could swap each call site cleanly.
- **Sparkle delegate hardening** — implemented `allowedSystemProfileKeys(for:)` returning an empty array, opting WolfWave out of Sparkle's system-profile telemetry beam (OS version, CPU arch, bundle metadata never leave the user's machine on update checks). Documented the `automaticallyDownloadsUpdates = false` rationale: explicit user consent is required before bytes touch the disk.
- **WebSocket security-model documentation** — added a `## Security model` doc block to `WebSocketServerService.swift` explaining the current loopback-only contract and matching it against `NSLocalNetworkUsageDescription`. Token-based auth + origin validation tracked as a follow-up.
- **New unit tests** — `SongBlocklistTests`, `HistoryFormattingTests`, `LaunchAtLoginServiceTests` cover three previously-untested services. `AppleMusicController` builder tests and `TwitchChannelPointsService` Helix payload tests tracked as follow-ups.
- **OBS widget build pipeline** — the overlay widget source moved out of the hand-edited `apps/native/WolfWave/Resources/widget.html` into a new `apps/widget/` Tailwind + TypeScript workspace. The bundled HTML is now a generated, fully inlined artifact (compiled CSS + design tokens + JS runtime in one file, no external `<link>`/`<script src>`). Xcode rebuilds it via a pre-build Run Script phase (`Build OBS Widget (Tailwind → inline)`); CI rebuilds it before every `xcodebuild` invocation in `test.yml` and `build_release.yml`. Manual rebuild is `bun run --filter widget build`. The WebSocket payload contract, widget URL, and theme/layout URL params are unchanged. Source files are heavily commented top-to-bottom with banner sections and per-function explanations so the runtime can be read end-to-end.
- **Inside-out release signing** — `build_release.yml` now signs nested bundles deepest-first before the app shell, dropping `--deep --force` which stripped per-bundle entitlements. The pipeline is XPC-ready for any future sandbox helper (#199).
- **Typed NotificationCenter payload helpers** — `Core/NotificationPayloads.swift` centralizes all notification payload post/observe pairs so send and receive sides share the same keys and types, removing ~38 hand-decoded `userInfo` sites (#198).
- **HelixClient** — shared HTTP wrapper for all Helix API calls, replacing per-service `send()` helpers. Maps 401, 429, and structured Helix error payloads uniformly; covered by `HelixClientTests` (#197).
- **Preferences typed accessor** — `Core/Preferences.swift` centralizes UserDefaults reads/writes for non-bool keys, replacing scattered `UserDefaults.standard.{string,integer,bool}(forKey:)` calls across AppDelegate and WolfWaveApp (#197).
- **Actor adoption** — `SongBlocklist` and `SkipVoteManager` converted from `final class + NSLock` to actors; `BotCommandContext` marked `nonisolated + Sendable`. Combine fully removed from the app target, with the last publisher replaced by a `.task` loop (#197).

### Fixed

- **Twitch bot silent after relaunch** — the EventSub connection used to stay idle on launch until the user reopened Twitch settings and clicked Connect again, which is why chat commands silently no-op'd after toggling them on. The app now auto-reconnects to the saved channel after `validateTwitchTokenOnBoot` succeeds, using the stored Keychain channel name. The auto-reconnect is silent — no "online" chat ping fires unless the user explicitly clicks Connect.
- **Keychain duplicate-item self-heal** — `KeychainService.upsertItem` now recovers from `errSecDuplicateItem` (OSStatus -25299), which previously appeared after onboarding finished and the WebSocket auth token tried to mint into a slot that held a legacy entry with a different `kSecAttrAccessible` value. The collision deleted the stale entry and retried the add once.
- **Twitch auth UI layout shifts** — the Twitch settings card no longer resizes between the "Not signed in", "Authorizing", and "Error" states. A reserved minHeight anchors the pre-connected content, transitions are symmetric (opacity + slide-from-top in *and* out), and `TwitchReauthView` (a separate, never-referenced re-auth screen) was deleted — re-auth surfaces inline in the same card.
- **Onboarding step centering** — step content (Welcome, Discord, Twitch, etc.) is now vertically centered in the wizard window instead of pinned to the top with empty space below. The surrounding `ScrollView` previously gave step views unbounded height, collapsing their `Spacer()`s; the scroll view is now constrained to the viewport height so the existing centering layout works. The reserved extras slot introduced for cross-step icon stability is now center-aligned instead of top-aligned, so compact extras (Discord toggle, Preferences toggles) no longer sit at the top of the reserved area with dead space below.
- **Two-PC stream widget** — the overlay WebSocket and widget HTTP server now bind to all interfaces (previously loopback only) and the bundled `widget.html` connects to `location.hostname` instead of a hardcoded `localhost`. Streamers can open `http://<lan-ip>:7780` from a second computer or phone on the same network and the widget loads. The Network Address URL in Settings → Stream Widgets now actually works.
- **GitHub URL config plumbing** — `GITHUB_REPO_OWNER` and `GITHUB_REPO_NAME` from `Config.xcconfig` now flow through `Info.plist` into the bundle, so Report a Bug / releases URLs resolve from config instead of always falling back to the hardcoded defaults.
- **Intel Homebrew cask detection** — Intel Macs using Homebrew now correctly trigger the Homebrew code path (Sparkle disabled, Homebrew update card shown, bug reports tagged `Homebrew`). Previously the path matcher checked `/usr/local/Cellar/` only, missing the `/usr/local/Caskroom/` location used by casks.
- Native build warnings, SwiftUI layout reentrancy, and duplicate log emission cleaned up (#22).
- Onboarding URL bug, permissions correctness, and layout stability polished (#28).
- **Export Logs crash** — Advanced settings no longer crashes when exporting empty or large logs (#50).
- **Settings / About window show** — deferred past the AppKit layout pass to silence `layoutSubtreeIfNeeded` recursion warnings (#53).
- **Music access icon** — adapts to light/dark mode and kills the top scroll fade that clipped the section header (#48).
- **PillButton width shift** — pinned button geometry across state changes so it no longer jumps mid-animation (#49).
- **Apple Music logo** — trimmed to the glyph so template rendering picks up the system tint (#37).
- **OBS logo** — trimmed to the glyph for matching template rendering (#45).
- **Menu bar pointer arrow** — anchored to the `TrayIcon` center in the onboarding preview (#41).
- **Brand icons in menu bar** — render as templates with refreshed logo SVGs (#40).
- **CI** — skip `TrackInfoCommandTests` on the `macos-26` runner where MusicKit isn't available (#42).
- **Settings window sidebar toggle** — removed the duplicate titlebar toggle, restored the toolbar sidebar toggle, and eliminated the floating `>>` reveal control (#59, #61, #77).
- **About panel** — removed the spacer that left a gap between the legal links and the footer (#60).
- **Brand icon cutouts** — app icon logo cutouts preserved by switching to the `evenodd` fill-rule (#62).
- **Apple Music control under sandbox** — granted the Apple Events entitlement so the sandboxed app can actually drive Music.app; before this fix the "WolfWave wants to control Music" prompt never appeared and ScriptingBridge silently no-op'd (#124).
- **Now-playing survives ScriptingBridge drift** — the `playerState` parser now accepts every bridge type Music.app returns (NSNumber, Int, UInt32, type-code descriptor, 4-byte string), instead of collapsing unexpected types to `NOT_PLAYING` and silently blanking the now-playing card, Discord Rich Presence, and overlay while music is actively playing (#134, #135, #136).
- **Recheck + Sync toggle** — both now force a fresh now-playing read instead of waiting for the next track change, so the UI catches up immediately after granting permission or flipping playback tracking (#125).
- **Apple Music permission Recheck button** — visibly responds when tapped (previously it ran the check but gave no feedback, making it look broken) (#141).
- **Stats card layout** — fixed jumping card sizes in History & Stats and added an Apple Music permission gate so the section doesn't render half-empty when access is denied (#118).
- **Settings window sizing** — enlarged the default window and tightened `StatusChip` so integration rows fit without horizontal scroll (#114).
- **About panel Check for Updates** — the button now actually invokes Sparkle; the Release Notes link now points at the docs changelog instead of an empty popover (#150).
- **Onboarding Preferences step** — no longer overlaps the nav bar on shorter window heights (#94).
- **Onboarding step header** — anchored so icons stop drifting between steps (#145).
- **Vote-skip window timer race** — a timer that outlasted a fast-passing vote could clear a newer session when session cooldown is 0. The timer now captures a session token at spawn and bails if a different session has since opened (#198).

### Removed

- **`WallpaperBloomBackground`** — dropped in favour of native macOS chrome (#24).
- **Redundant onboarding success rows** — removed for a tighter, less repetitive wizard (#21).

## [1.2.0] - 2026-04-04

### Added

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

