# Changelog

All notable changes to this project will be documented in this file.

## [2.0.0] - Unreleased

### Security

- **Stream Widgets now need an access token.** Your overlay link carries a private token, and the widget server turns away any connection that doesn't have it, so nobody else on your network can pull up your now-playing feed. The token is created on first launch and kept in the macOS Keychain. Existing OBS browser sources keep working with no changes, because WolfWave adds the token to the URL and the served `widget.html` for you. Settings → Stream Widgets lets you reveal it (hidden by default), regenerate it, or paste in your own. Regenerating or editing the token disconnects every widget until it reconnects with the new one.
- **Streamer Mode.** A new tray-menu toggle (Streamer Quick Actions) hides anything you would not want on camera: your connected Twitch channel name, the overlay and widget URLs, the WebSocket address, and the Stream Widgets access token. The Copy and Open buttons next to hidden values are switched off, so a screenshot can't leak them either. It only changes what's on screen. Your overlay feed, Discord Rich Presence, and Twitch chat output are untouched.

### Added

- **Live widget preview.** Settings → Stream Widgets now shows your overlay right under the Widget Appearance controls. Change the theme, layout, font, or colors and the preview updates as you go, so you can dial in the look before copying the URL into OBS.
- **Back up and restore your settings.** Export your preferences to a plain JSON file from Settings → Advanced, then bring them back on another Mac or after a reinstall. Accounts and secrets are never in the file (your Twitch token, user and channel IDs, and the Stream Widgets token stay in the Keychain). On import you decide, per account, whether to reconnect Twitch. Say no and that account is skipped while the rest of your settings come back. The file only holds portable settings, so you can open and read it yourself.
- **Light, Dark, or System appearance.** Pick one in Settings → General. System follows macOS (including the light/dark schedule); Light and Dark override it for the whole app, menu bar menu included. The picker shows System Settings-style preview thumbnails (#243). Settings cards now sit on a solid macOS surface, so they no longer glow too bright in dark mode or wash out in light mode (#242), and the Advanced log buttons line up in a tidy 2-up grid.
- **Discord idle and pause controls.** A new "When not playing" section in Settings → Discord. _Show idle status_ keeps a "Listening to WolfWave · Idle" marker on your profile when nothing's playing instead of clearing it; _Hide track while paused_ clears your profile when you pause instead of leaving the paused song up. Both are off by default. The Discord preview card now matches real behavior: it shows the live track only while playing or paused, and switches to a matching empty or idle state when playback stops, Apple Music is closed, or Discord isn't running.
- **Chat Vote-Skip.** Viewers can vote to skip the current song with `!voteskip` or `!vs`. A passing vote skips the current request, or moves to the next Apple Music track when the queue is empty. Chat-tally mode counts unique voters within a time window against a minimum number of votes; opt-in Twitch Polls mode (Affiliate/Partner) opens a native poll instead. Set the minimum votes, vote window, cooldown, and subscriber-only voting in Settings → Song Requests → Chat Vote-Skip.
- **Listening History.** An opt-in, on-device log of the tracks you play. It stays on your Mac and is never uploaded. Off by default; turn it on in Settings → History & Stats or during onboarding. A track only counts once it has played past its halfway point (or 4 minutes), so skips don't pollute your history.
- **Stats and Charts.** Top artists, listening time, a 7-day play trend, and a listening-by-hour breakdown in the new History & Stats section, drawn with SwiftUI Charts. Needs Listening History turned on. Laid out as a two-column dashboard that drops to one column on a narrow window: the summary tiles sit beside a today's-top-track highlight, the two charts sit side by side, and one Top card switches between artists, tracks, and albums.
- **Monthly Wrap.** A personal "wrapped"-style summary for any month. Save the card as a PNG, or send it straight to Messages, Mail, AirDrop, and more through the macOS share sheet.
- **`!stats` command.** Viewers can ask for today's top track in Twitch chat. It only replies while your stream is live (via `stream.online` / `stream.offline` events).
- **`!wolfwave` command.** A one-tap chat shoutout for the app. Viewers run `!wolfwave` and the bot replies with what WolfWave is, who makes it, and where to get it. Off by default. Pick from four reply styles (credit + maker, viewer how-to, open-source pitch, or short) in Settings → Twitch → Bot Commands, with the same cooldowns, mod bypass, and custom aliases as `!song`.
- **Song Requests.** Viewers can request songs in Twitch chat with `!sr <song>`. Requests play through Apple Music without stealing focus from your stream.
- **`!queue` / `!myqueue`.** Show the whole request queue, or just a viewer's own requests, in chat.
- **`!skip` / `!next`.** Mods and the broadcaster can skip the current request.
- **`!clearqueue`.** Mods and the broadcaster can wipe the queue (with an in-app confirmation first).
- **`!hold` / `!resume` / `!unhold`.** Mods and the broadcaster can pause the queue. New requests pile up without auto-playing, so you can line them up before releasing them.
- **Hold controls in the app.** A Hold/Resume button in the Song Request Queue view and a matching toggle in the menu bar.
- **Requests wait while Apple Music is closed.** They're saved when Music is closed and play once it reopens (hold mode is respected).
- **Fallback playlist.** Pick an Apple Music playlist to play whenever the request queue runs dry.
- **Song Request Queue view.** A full queue with a now-playing card, position badges, who requested each track, and Skip / Hold / Clear controls.
- **Per-user and global request limits**, subscriber-only mode, per-command on/off toggles, and custom command aliases.
- **Custom aliases for `!song`, `!last`, and `!stats`.** Comma-separated alias fields in Settings → Twitch and Settings → History & Stats. Aliases follow the same on/off, cooldown, and live-only rules as the original command. Fixes a bug where an alias matched but the command sent no reply.
- **Hold-queue toggle in Song Request settings.** Flip the queue between Hold and Playing right from the Playback card; before this it was only reachable from the menu bar and the queue view.
- **Recreate Reward button.** Clears the saved Channel-Point reward and makes WolfWave build a fresh "Request a Song" reward on Twitch. Use it if you delete the reward by hand on the Twitch dashboard. The reward ID shows below the cost picker (hidden when Streamer Mode is on).
- **History retention picker.** Choose how long to keep your listening history (Forever / 7 / 30 / 90 / 180 / 365 days). Older entries are cleared at the next launch.
- **macOS 26 Liquid Glass onboarding.** A full rebuild of the first-launch wizard with two new steps (Menu Bar Pointer and OBS Widget) to match Tahoe's look (#26).
- **Apple Music onboarding step.** The first-launch wizard now asks for Apple Music library access for song search, with a clear path back if you decline.
- **OBS Widget onboarding step.** Preview the overlay URL and flip on the HTTP widget during setup, so you can grab your overlay link before you finish (d62b8ac).
- **macOS 26 Liquid Glass redesign.** Refreshed settings and menu bar chrome using native Liquid Glass materials, plus the Apple Music permission flow (#22, #26).
- **Faster overlay URLs.** WolfWave caches your local IP so settings views no longer pause while looking it up (#34).
- **Diagnostics and bug reporting.** Advanced settings gains Export Logs and Clear Logs, plus a one-click "Report a Bug" that opens a pre-filled GitHub issue with sensitive details already redacted (#50).
- **Branded About window.** A native WolfWave About window replaces the default macOS panel (#55).
- **Apple Music logo on the Music access row.** Once access is granted, the row shows the Apple Music mark instead of a generic icon (#38).
- **Widget themes.** Six overlay-widget themes (Default, Dark, Light, Glass, Neon, WolfWave) and three layouts (Horizontal, Vertical, Compact) (#76).
- **Discord presence polish.** Friendlier presence buttons, a live preview in Discord settings, and cleaner connection handling (#73).
- **Song-change notifications.** An opt-in macOS notification on every track change, with the track name, artist, and album art. A new banner replaces the last one instead of stacking up. Off by default; turn it on in Settings → General → Notifications (#83).
- **Skip-vote notifications.** Opt-in macOS notifications when a chat skip-vote starts and when it passes. The "started" banner is silent and shows the vote target (or points at the open Twitch poll); the "passed" banner names the skipped track and plays the default sound. Both are off by default in Settings → Notifications and stay off until Chat Vote-Skip is on. The onboarding Permissions step lets you choose which alerts you want.
- **On-device diagnostics.** An opt-in MetricKit report in Advanced settings. Reports stay on your Mac; a share card lets you attach one to a bug report by hand. Off by default (#85).
- **Discord playlist in your presence.** Discord Rich Presence now shows the current Apple Music playlist name next to the track when one is playing.
- **WolfMark branding.** A new WolfMark placeholder replaces the generic music icon in the now-playing card and overlay widget, alongside a branded download page, repo `README.md`, and `SECURITY.md`.
- **Smoother OBS widget.** The now-playing overlay slides in with a small bounce when a song starts and slides and blurs out calmly when playback stops, with the progress bar draining to zero. Skipping a track while the widget is up crossfades the artwork and text instead of replaying the entrance, so fast skips no longer strobe your stream. Pausing keeps the card up, as before.

### Changed

- **Clearer settings headings.** Every settings pane now has one big title, with section titles a clear step below it, so the page reads top to bottom at a glance. Pane titles, section titles, and card labels are now distinct sizes (they used to sit almost on top of each other), and VoiceOver can jump between them by heading. The Twitch sign-in card no longer showed its title smaller than its own subtitle. Onboarding and the now-playing card pick up the same tidied-up text sizes.
- **Calmer destructive buttons.** Reset All Settings, Clear Logs, and Clear Artwork Cache no longer show up as a loud red bar. Each is a neutral button with a red label, and the Danger Zone card swaps its red wash for a clean card with a red heading. The red stays where it means something: the label, the heading, and the final confirm.
- **Type RESET to wipe everything.** The Reset All Settings confirmation now spells out exactly what it erases and makes you type RESET before the button unlocks, so a stray click can't reset the app by accident.
- **Redesigned Settings sidebar.** The sidebar moves to a VoiceInk-style layout: a branded header (WolfWave mark, app name, version), grouped rows with round icon chips, and a solid accent-colored selection pill with a hover highlight. Keyboard navigation, click selection, and VoiceOver work the same, and the Integrations / On Stream / Insights / App grouping is unchanged.
- **Apple Music playback keeps your focus.** Music never steals focus from OBS or other streaming tools; the app you were in is brought back about 150 ms after each command.
- **MusicKit is only used for search**, never for playback, so there's no in-app audio session.
- **Settings split into per-section files** (`GeneralSettingsView`, `MusicMonitorSettingsView`, `AppVisibilitySettingsView`, `TwitchSettingsView`, `DiscordSettingsView`, `WebSocketSettingsView`, `SongRequestSettingsView`, `AdvancedSettingsView`) for snappier redraws and easier editing (#34).
- **Onboarding polish.** Dropped repeated success rows, tightened the Apple Music permission copy, and pinned button and step sizes so nothing jumps around (#21, #25, #28).
- **Notifications toggle** switches itself off once permission is granted, and the denied state now reads the same across the wizard (#29).
- **Permissions live in one onboarding step.** Apple Music access, the notification prompt, and the per-alert toggles are now in a single "Permissions" step instead of separate screens.
- **`PillButton`** now uses the macOS-standard rounded rectangle instead of a `Capsule`, to match system buttons (#30).
- **Menu bar preview icon** renders crisply at every screen density via `NSImage` (#32).
- **Settings window sizing** is tuned to fit cleanly on 720p and 1080p displays without clipping (#33).
- **Music permission row is actionable.** Tapping it re-requests access or jumps you to System Settings, depending on the current state (#31).
- **OBS onboarding step** collapses to a single toggle, with the overlay URL promoted to the top (#36).
- **OBS branding in settings** uses the `tv.badge.wifi` SF Symbol so the chip tints correctly (#46).
- **Advanced settings** uses the shared `cardStyle()` helper for consistent materials and corners (#52).
- **Tighter wording** across onboarding, settings, and the menu bar: fewer words, clearer verbs (#47).
- **Test suite tidied up.** Merged `SongCommandTests` and `LastSongCommandTests` into one `TrackInfoCommandTests`, and renamed `MusicPlaybackMonitorTests` to `AppleMusicSourceTests`. The suite is now more than 2,200 tests across 90 files.
- **Design tokens everywhere.** Settings views now read sizes and spacing from `DSFont` and `DSSpace` instead of hardcoded numbers, for consistent typography and spacing across every tab. Added the missing tokens to `design-system/tokens.json`.
- **Concurrency cleanup.** Replaced leftover `DispatchQueue.main.async` calls in `AppDelegate+MenuBar`, `DiscordSettingsView`, and `AppleMusicController` with structured `Task { @MainActor }`, matching the project's async/await rule.
- **Steadier under stress.** A process-wide safety net now catches the rare hard crash. If WolfWave does go down, it shows a one-time "Recovered from a crash" notice in Advanced with a one-click bug report. A misbehaving service at launch degrades on its own instead of taking the whole app down with it (#255, #264).
- **Logger regex literals.** `Logger.swift`'s redaction patterns use compile-checked `#/.../#` literals instead of `try! Regex(...)`, clearing the SwiftLint force-unwrap warnings.
- **Liquid Glass onboarding surface.** The wizard panel now renders on a `.glassEffect(.regular)` material, matching the settings cards and now-playing card (#198).
- **Streamer Mode hides your Twitch account name** in Settings too, matching the channel-ID rows and the menu bar (#198).
- **Onboarding accessibility.** VoiceOver now announces each step by name ("Step 3 of 7: Twitch") via the progress dots (#198).
- **Sidebar grouped by purpose** (#239). Sections are grouped by what they're for, and the App group is ordered by how often you reach for it. App Visibility is now a single-column picker for showing WolfWave in the menu bar, the Dock, or both (#241), and the General tab lays Startup and Display Mode side by side (#235).

### Performance

- **Lower idle energy use.** WolfWave's periodic timers (fallback poll, WebSocket progress tick, Discord availability poll, song-request auto-advance) now let macOS batch their wakeups together, which saves power for an all-day menu bar app. Real-time track changes still arrive instantly; only the background polling changed (#199).
- **No more jank** when switching between settings sections (#51).
- **Faster first paint.** Font lookup moved off the main thread so the Widget Setup row no longer blocks it (#54).
- **Instant Now-Playing Server row** thanks to the cached local IP lookup (#39).

### Developer

> Developer-facing changes. Not visible to end users.

- **Unified design system.** A single `design-system/tokens.json` feeds `generate.ts`, which emits four platform outputs (Swift `Tokens.generated.swift`, docs CSS, widget JS, marketing TS). A Turbo `tokens` task runs as a build prerequisite (#72, #76).
- **Component catalog.** `design-system/components/` gains one markdown entry per reusable view, tracked against a shared template (#76).
- **DEBUG-only Debug tab.** A developer tooling tab (inspectors, service controls, log/event views, UI previews) plus What's New preview controls, only in DEBUG builds (#66, #69).
- **Expanded design-token roster.** `font.size` gains the 9/15/16/18/24/26/28/36 px slots used across views; `space` gains `s0` (2 px), `s10` (32 px), and `s11` (44 px). Token-only additions with no visual change.
- **Sparkle delegate hardening.** Implemented `allowedSystemProfileKeys(for:)` returning an empty array, opting WolfWave out of Sparkle's system-profile telemetry (OS version, CPU arch, and bundle metadata never leave the user's machine on update checks). Documented why `automaticallyDownloadsUpdates = false`: explicit consent is required before bytes touch the disk.
- **WebSocket security-model docs.** Added a `## Security model` block to `WebSocketServerService.swift` describing the loopback-only contract.
- **New unit tests.** `SongBlocklistTests`, `HistoryFormattingTests`, and `LaunchAtLoginServiceTests` cover three previously-untested services.
- **OBS widget build pipeline.** The overlay source moved out of the hand-edited `apps/native/WolfWave/Resources/widget.html` into a new `apps/widget/` Tailwind + TypeScript workspace. The bundled HTML is now a generated, fully inlined artifact (compiled CSS, design tokens, and JS runtime in one file, no external `<link>` or `<script src>`). Xcode rebuilds it via a pre-build Run Script phase; CI rebuilds it before every `xcodebuild` run in `test.yml` and `build_release.yml`. Manual rebuild is `bun run --filter widget build`. The WebSocket payload, widget URL, and theme/layout params are unchanged. Source files are heavily commented so the runtime can be read end to end.
- **Inside-out release signing.** `build_release.yml` now signs nested bundles deepest-first before the app shell, dropping `--deep --force`, which stripped per-bundle entitlements. The pipeline is XPC-ready for a future sandbox helper (#199).
- **Typed NotificationCenter payload helpers.** `Core/NotificationPayloads.swift` centralizes every notification payload post/observe pair so both sides share the same keys and types, removing about 38 hand-decoded `userInfo` sites (#198).
- **HelixClient.** A shared HTTP wrapper for all Helix API calls, replacing per-service `send()` helpers. Maps 401, 429, and structured Helix errors uniformly; covered by `HelixClientTests` (#197).
- **Preferences typed accessor.** `Core/Preferences.swift` centralizes UserDefaults reads and writes for non-bool keys across AppDelegate and WolfWaveApp (#197).
- **Actor adoption.** `SongBlocklist` and `SkipVoteManager` move from `final class + NSLock` to actors; `BotCommandContext` is marked `nonisolated + Sendable`. Combine is fully removed from the app target, with the last publisher replaced by a `.task` loop (#197).
- **Sparkle release notes.** The release pipeline now turns each version's CHANGELOG section into styled HTML (`scripts/release-notes.mjs`) and embeds it in the appcast, so the in-app update dialog shows what's new with a link out to the full changelog.
- **Crash safety net.** `CrashReporter` installs an uncaught-exception handler plus `sigaction` for SIGABRT/ILL/SEGV/FPE/BUS/TRAP (async-signal-safe write path), records a breadcrumb, flushes the log, and chains the previous handler so the OS crash report and MetricKit diagnostics still fire. `guardedStart()` isolates a synchronous service-setup failure, the three `JSONSerialization.data(withJSONObject:)` sites are fronted by `isValidJSONObject`, and a blocking `swiftlint-crash-safety` CI gate runs force-unwrap/try/cast at error severity across production source (#255, #264).
- **Shared helpers, less copy-paste.** Extracted `StringFormatting.truncatedWithEllipsis` (chat-reply truncation), a generic `Atomic<Value>` box in `ThreadSafeStorage.swift` that replaces the hand-rolled `AtomicBool` and Discord state-snapshot locks, `FeatureFlags.songRequestHoldEnabled`, and a Discord button-key resolver, so the duplicated logic lives in one tested place.

### Fixed

- **One recovery card for denied Music access.** Settings → General no longer stacks the same "Music access denied" warning in three spots. A single card now owns the explanation and the Open System Settings button, the Sync Music card hides its duplicate row while access is denied, and the now-playing card reads a calm orange "Paused" instead of a red "Denied". "Try again" shows a spinner and a "still off" hint instead of feeling like a dead button (#240).
- **Twitch bot no longer goes silent after a relaunch.** It used to sit idle on launch until you reopened Twitch settings and clicked Connect again, which is why chat commands quietly did nothing. WolfWave now reconnects to your saved channel on its own once the token check passes. The reconnect is silent, so no "online" chat ping fires unless you click Connect yourself.
- **Keychain self-heals a duplicate item.** `KeychainService.upsertItem` now recovers from `errSecDuplicateItem` (OSStatus -25299), which used to appear after onboarding when the Stream Widgets token tried to write into a slot holding an older entry. It clears the stale entry and retries once.
- **Twitch settings card stops jumping.** It no longer resizes between the "Not signed in", "Authorizing", and "Error" states. A reserved height anchors the content, transitions are symmetric, and the unused `TwitchReauthView` was deleted so re-auth shows up inline in the same card.
- **Onboarding steps are centered again.** Step content sat pinned to the top with empty space below because the scroll view gave it unbounded height; it's now constrained to the window so the centering layout works. The reserved icon slot is center-aligned too, so compact steps (the Discord and Preferences toggles) no longer leave dead space below them.
- **Two-PC stream widget works.** The overlay WebSocket and widget HTTP server now listen on every network interface (not just loopback), and the bundled `widget.html` connects to its own hostname instead of a hardcoded `localhost`. Open `http://<your-lan-ip>:7780` from a second computer or your phone on the same network and the widget loads. The Network Address URL in Settings → Stream Widgets now actually works (and is gated by the new access token).
- **GitHub URL config plumbing.** `GITHUB_REPO_OWNER` and `GITHUB_REPO_NAME` from `Config.xcconfig` now flow through `Info.plist`, so the Report a Bug and releases links come from your config instead of the hardcoded defaults.
- **Intel Homebrew detection.** Intel Macs installed via Homebrew now take the Homebrew path (Sparkle off, Homebrew update card shown, bug reports tagged `Homebrew`). The old check only looked at `/usr/local/Cellar/` and missed the `/usr/local/Caskroom/` location casks use.
- Cleaned up native build warnings, a SwiftUI layout reentrancy issue, and duplicate log lines (#22).
- Fixed an onboarding URL bug, permissions correctness, and layout stability (#28).
- **Export Logs no longer crashes** on empty or very large logs (#50).
- **Settings and About windows** show after the AppKit layout pass, silencing the `layoutSubtreeIfNeeded` recursion warning (#53).
- **Music access icon** adapts to light and dark mode, and the top scroll fade that clipped the section header is gone (#48).
- **PillButton** no longer shifts width mid-animation (#49).
- **Apple Music logo** trimmed to the glyph so template tinting picks it up (#37).
- **OBS logo** trimmed to the glyph for matching template rendering (#45).
- **Menu bar pointer arrow** anchored to the `TrayIcon` center in the onboarding preview (#41).
- **Brand icons in the menu bar** render as templates with refreshed logo SVGs (#40).
- **CI** skips `TrackInfoCommandTests` on the `macos-26` runner, where MusicKit isn't available (#42).
- **Settings sidebar toggle.** Removed the duplicate titlebar toggle, restored the toolbar toggle, and got rid of the floating `>>` reveal control (#59, #61, #77).
- **About window** spacer that left a gap between the legal links and the footer is gone (#60).
- **App icon cutouts** are preserved by switching to the `evenodd` fill-rule (#62).
- **Apple Music control under the sandbox.** Granted the Apple Events entitlement so the sandboxed app can actually drive Music; before this, the "WolfWave wants to control Music" prompt never appeared and ScriptingBridge quietly did nothing (#124).
- **Now-playing survives ScriptingBridge quirks.** The `playerState` parser now accepts every value type Music returns (NSNumber, Int, UInt32, type-code descriptor, 4-byte string) instead of collapsing the unexpected ones to `NOT_PLAYING` and blanking the now-playing card, Discord presence, and overlay while music is playing (#134, #135, #136).
- **Recheck and the Sync toggle** force a fresh now-playing read instead of waiting for the next track change, so the UI catches up right after you grant permission or flip tracking (#125).
- **Apple Music Recheck button** visibly responds when tapped, instead of looking broken (#141).
- **Stats card layout** no longer jumps around, and the section is gated on Apple Music access so it doesn't render half-empty when denied (#118).
- **Settings window default size** enlarged, and `StatusChip` tightened so integration rows fit without horizontal scrolling (#114).
- **About window Check for Updates** now actually invokes Sparkle, and the Release Notes link points at the docs changelog instead of an empty popover (#150).
- **Onboarding Preferences step** no longer overlaps the nav bar on shorter windows (#94).
- **Onboarding step header** anchored so icons stop drifting between steps (#145).
- **Vote-skip timer race.** A timer that outlived a fast-passing vote could clear a newer session when the cooldown is 0. It now captures a session token when it starts and bails if a different session has opened since (#198).

### Removed

- **`WallpaperBloomBackground`**, in favor of native macOS chrome (#24).
- **Repeated onboarding success rows**, for a tighter wizard (#21).

## [1.2.0] - 2026-04-04

### Added

- **Shared UI components.** Extracted reusable `ConnectionTestButton`, `SectionHeaderWithStatus`, `InfoRow`, and `ConfigRequiredBanner` for a consistent settings UI across sections.

### Changed

- **Music playback architecture.** Refactored to a pluggable source system (`PlaybackSourceManager` + `PlaybackSource` protocol), laying the groundwork for music sources beyond Apple Music.
- **AppDelegate decomposed.** Split the monolithic delegate into focused extensions (`+MenuBar`, `+Services`, `+Windows`) for maintainability.
- **Logger format.** Streamlined to local time (`HH:mm:ss.SSS`) with emoji prefixes for faster scanning in the Xcode console.
- **Widget appearance settings.** Reorganized into a compact 2-per-row layout; dropdown pickers now auto-size to content.
- **Discord and Twitch settings.** Unified section headers and connection test buttons using shared components.
- **Code quality.** Added MARK sections and DocC comments across 12+ files for better Xcode navigation; added a `Color` hex initializer and a `NotificationCenter` posting helper.

### Fixed

- Settings window not appearing on screen when opened from the menu bar in menu-bar-only mode. Window show is now deferred to the next run-loop tick after the activation policy switch.
- `@MainActor` isolation for `getCurrentSongInfo()` / `getLastSongInfo()` Twitch bot callbacks. Replaced `DispatchQueue.main.sync` with `MainActor.assumeIsolated` to satisfy Swift strict concurrency.
- 4 Xcode build warnings: actor isolation annotations in `Logger.swift` and unreachable code in `SparkleUpdaterService.swift`.
- Widget favicon broken reference path.

## [1.1.0] - 2026-03-31

### Added

- **Discord buttons.** Rich Presence now shows two clickable buttons: **Open in Apple Music** (direct track link) and **song.link** (opens on Spotify, YouTube Music, Tidal, and more). Buttons appear whenever a track link resolves, even if artwork isn't available.
- **Launch at Login.** A new toggle in Settings → App Visibility. Uses `SMAppService`, so it appears in System Settings → General → Login Items. Turning it on switches "Dock Only" mode to "Dock and Menu Bar" so the app is always reachable.
- **Custom DMG background.** The installer window now has a polished dark background with the WolfWave brand colors and a drag-to-Applications arrow.
- **Homebrew auto-update.** A GitHub Actions workflow now opens a pull request on the Homebrew tap whenever a new release is published.

### Fixed

- iTunes Search API URL encoding. Track and artist names containing `&`, `+`, or `=` no longer break artwork and link lookups (switched to `URLComponents` + `URLQueryItem`).
- Launch at Login toggle now reverts if `SMAppService` registration fails, preventing a mismatch between the UI and the actual system state.

## [1.0.2] - 2026-03-31

### Fixed

- App icon missing in CI-built releases (added a pre-built .icns fallback for Xcode 16 runners).
- Sparkle updater unable to detect new versions (build number now incremented per release).
- Sparkle initialization race condition (restored synchronous init instead of deferred async).

## [1.0.1] - 2026-03-30

### Changed

- Dropped Intel (x86_64) support. Apple Silicon only.
- Raised the minimum macOS version to 26.0 (Tahoe).
- Logger: replaced NSLock with a serial DispatchQueue for thread-safe file I/O.
- TwitchChatService/DiscordRPCService: documented thread safety patterns.
- KeychainService: added error logging for all Keychain operations.
- AppConstants: cached GitHub repo resolution (no longer recomputes on every access).
- Migrated TwitchViewModel and OnboardingViewModel to the @Observable macro.
- WhatsNewView: dynamic version string, native button style, v1.0.1 feature highlights.
- Narrowed the entitlements file exception path.
- Added Twitch user ID redaction to log output.
- NotificationCenter observers now properly cleaned up on app termination.
- Windows (Settings, Onboarding, What's New) properly released on close.
- Deferred Sparkle/onboarding init past the initial layout to fix a layoutSubtreeIfNeeded warning.
- Removed the duplicate "up to date" alert (Sparkle handles it natively).
- Added VoiceOver accessibility labels across all settings and onboarding views.

## [1.0.0] - 2026-03-30

### Added

- Native macOS menu bar app for Apple Music integration.
- Real-time now-playing detection via ScriptingBridge and distributed notifications, with 2-second fallback polling.
- Twitch chat bot with `!song`, `!currentsong`, `!nowplaying`, `!lastsong`, `!last`, `!prevsong` commands.
- Discord Rich Presence showing "Listening to Apple Music" with dynamic album art.
- OBS stream widget via a built-in WebSocket server (browser source overlay).
- Automatic updates via Sparkle for DMG installs; Homebrew Cask installs update separately via `brew upgrade --cask wolfwave`.
- First-launch onboarding wizard (Welcome, Twitch, Discord, OBS Widget).
- macOS Keychain credential storage (no plain-text tokens).
- Twitch OAuth Device Code authentication flow.
- Bot command cooldowns (global + per-user, default 15s) and broadcaster bypass.
- Channel validation with the Twitch Helix API.
- Settings UI with a NavigationSplitView sidebar (Music Monitor, App Visibility, Twitch, Discord, OBS Widget, Advanced).
- Unified Music Monitoring panel with integration status indicators.
- App visibility modes: menu bar only, dock only, or both.
- Diagnostic log export.
- Full reset / danger zone in Advanced settings.
- CI pipeline with Developer ID certificate import, code signing, notarization via `notarytool`, stapling, and keychain cleanup.

### Changed

- **Channel validation.** Moved Twitch channel name validation from keystroke-triggered to connect-button-triggered. No more API calls while typing; validation happens when you click Connect.
- **Bot command toggles.** Fixed a bug where disabling a command toggle didn't persist across restarts. Commands now read their enabled state from UserDefaults at initialization.
- **Command aliases in settings.** Bot command toggle rows now show all trigger aliases (e.g., `!song · !currentsong · !nowplaying`).
- **Onboarding Welcome step.** Updated to list all features (Music Sync, Twitch Chat Bot, Discord Rich Presence, Stream Overlays, Menu Bar) with brand-colored icons.
- **Onboarding window.** Now centers on screen before showing to prevent a flash at the origin.
- **Menu bar simplified.** Removed the now-playing display from the tray menu. The menu now holds only Settings, About, and Quit.
- **macOS system colors.** The UI uses system accent and semantic colors for automatic light/dark support.
- **Discord auto-reconnect.** Exponential backoff reconnection (5s base, doubling to a 60s cap) with availability polling when Discord isn't running.
- **Twitch reconnection.** Network path monitoring with automatic reconnection on connectivity changes, capped at 5 retry cycles with a 60s cooldown.
- **Documentation.** Updated all docs for current features and added a Legal section with the Privacy Policy and Terms of Service.
- **UX wording.** Unified feature naming (Music Sync, Now-Playing Widget), standardized empty states, and shortened descriptions for clarity.
- **Typography hierarchy.** Established an H1/H2/H3 heading system across all settings views.
- **Thread safety.** Fixed MainActor.assumeIsolated crash risks and added lock coverage for Twitch service properties.
- **Sparkle updates.** Completely disabled in DEBUG builds; fixed appcast Ed25519 signing.
- **Dev bundle.** Separate .dev bundle ID for side-by-side development testing.

### Removed

- Now-playing track display from the menu bar dropdown (moved to the Music Monitor settings preview).
