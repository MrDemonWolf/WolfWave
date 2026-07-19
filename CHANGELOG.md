# Changelog

All notable changes to this project will be documented in this file.

## [2.1.0] - Unreleased

> The next release. These changes ship on the [Nightly channel](https://mrdemonwolf.github.io/wolfwave/docs/nightly) off `main` until 2.1.0 is tagged for stable, when this heading gets its date.

### Added

- **Custom bot commands.** Make your own chat commands with a fixed reply, right in Settings → Twitch → Custom Commands. Drop in variables like `$user`, `$touser`, `$args`, `$1`–`$9`, `$song`, and `$lastsong` and they fill in live. Each command gets its own aliases and Everyone / Per-person cooldowns, same as the built-ins.
- **Pick who can run a command.** Set any custom command to Everyone, Subscribers, VIPs, Moderators, or Broadcaster only. Custom commands ride along with your settings backup.
- **Approve songs before they play.** New opt-in "Require My Approval" toggle in Settings → Song Requests → Access. When it's on, every request (chat, channel points, bits) waits in the Queue tab until you approve or decline it. Off by default, so requests still auto-queue unless you turn it on.
- **Two new overlay layouts: Vinyl and Classic.** Vinyl is a spinning record with your album art as the label and a circular progress ring. Classic sets the album tile beside a card with the title, artist, and a progress bar. Pick either in Settings → Stream Widgets, same as Horizontal, Vertical, and Compact.

### Developer

- New `BotCommand.isAllowed(context:)` permission hook and `allTriggers` protocol requirement (both default-preserving, so built-ins are unchanged). `CustomBotCommand` is an `AsyncBotCommand` built per message from `CustomCommandStore`, so edits apply on the next chat line without re-registration. Pure `CustomCommandRenderer` covers variable substitution; 21 new tests.

## [2.0.1] - 2026-07-11

### Fixed

- **Update notes now load.** Sparkle's "What's New" window no longer 404s when you check for updates. (It broke in 2.0.0.)
- **Fewer crashes.** Fixed a crash for people who opted into diagnostics, a crash from an out-of-range widget port, and hard failures when a log write hit a full disk.
- **Music.app can't freeze WolfWave.** Every command to Apple Music now times out instead of hanging the app if Music gets stuck.
- **Snappier menu bar.** Play/pause state reads from cache instead of pinging Music.app while the menu is open.
- **No double actions.** Twitch events that arrive twice (chat commands, channel-point redemptions) only run once now.
- **Overlays keep updating.** Closing the Settings window no longer stops now-playing updates from reaching your overlay.
- **Vote-skip won't get stuck.** A Twitch poll that never closes now falls back cleanly, and chat votes reset between songs.
- **Accurate history.** Listening History no longer double-counts a play, and tells apart songs that share a title.
- **`!playlist` survives hiccups.** A brief network blip while checking your playlist link no longer switches the command off.

### Developer

- Full multi-agent audit pass: 28 native + 9 OBS widget findings, adversarially verified and fixed (#351). `DiagnosticsService` nonisolated, throwing `FileHandle` in Logger, clamped `Preferences.resolvedWidgetPort`/`resolvedWebSocketServerPort`, EventSub `message_id` dedup, per-subscriber connection-state `AsyncStream`s.
- Release workflow uploads the Sparkle release-notes HTML with the DMG + appcast, and hard-fails if it's missing (#349).
- Docs / README / CLAUDE.md synced with the current source tree (#352).

## [2.0.0] - 2026-07-01

### Security

- **Stream Widgets now need an access token.** Your overlay link carries a private token, so nobody else on your network can pull up your now-playing feed. It's made on first launch and kept in the Keychain. Your OBS sources keep working. Reveal, regenerate, or replace it in Settings → Stream Widgets.
- **Streamer Mode.** One tray toggle hides anything you wouldn't want on camera: channel name, overlay and widget URLs, and the access token. Copy and Open buttons switch off too. On-screen only. Your overlay, Discord, and chat output are untouched.

### Added

**Song requests**

- **Song Requests.** Viewers request tracks with `!sr <song>`. Plays through Apple Music without stealing focus from your stream. Each request is saved to a "WolfWave Requests" playlist and played from there, so it works on macOS 26 (Tahoe), where Apple Music stopped letting apps play songs you haven't saved.
- **Guided setup.** A quick walk-through (Twitch, Apple Music access, your requests playlist) runs before song requests can be switched on, so nothing goes live half-configured. Re-run it anytime from the pane.
- **Queue commands.** `!queue` and `!myqueue` show the queue. `!skip`/`!next`, `!clearqueue`, and `!hold`/`!resume` are for mods and the broadcaster.
- **`!playlist` command.** Drops a link to your requests playlist in chat. Share the playlist in the guided setup and the link stays live as songs are added. If you later delete or un-share it, WolfWave turns `!playlist` off and shows a "set up again" banner so chat never gets a dead link. Off by default.
- **Chat Vote-Skip.** Chat votes out a song with `!vs`. Counts unique voters, or opens a native Twitch poll (Affiliate/Partner). Set it up in Settings → Song Requests.
- **Song Request Queue view.** A now-playing card, who asked for each track, and Skip / Hold / Clear.
- **Hold the queue.** New requests pile up without auto-playing, so you can line them up first. From the queue view or the menu bar.
- **Requests wait while Apple Music is closed.** Saved, then played when Music reopens.
- **Fallback playlist.** Plays an Apple Music playlist whenever the queue runs dry.
- **Limits and controls.** Per-user and global limits, subscriber-only mode, on/off per command, and custom aliases.
- **Recreate Reward button.** Rebuilds the "Request a Song" Channel-Point reward if you delete it by hand.

**Your music, tracked**

- **Listening History.** An opt-in, on-device log of what you play. Stays on your Mac, never uploaded. Off by default. Skips don't count.
- **Stats and Charts.** Top artists, listening time, a 7-day trend, and a by-hour breakdown. Needs Listening History on.
- **Monthly Wrap.** A personal "Wrapped" for any month. Save it as a PNG or share it.
- **History retention picker.** Keep history forever, or for 7 / 30 / 90 / 180 / 365 days.
- **`!stats` command.** Chat asks for today's top track. Only replies while you're live.

**On stream**

- **`!wolfwave` command.** A one-tap chat shoutout for the app. Four reply styles. Off by default.
- **Widget themes.** Six overlay themes (Default, Dark, Light, Glass, Neon, WolfWave) and three layouts.
- **Live widget preview.** See your overlay update as you tweak the theme, layout, font, and colors.
- **Smoother OBS widget.** Songs slide in, fade out calmly, and crossfade on fast skips. No strobing.
- **Discord idle and pause controls.** Keep an idle marker when nothing plays, or clear your profile while paused. Both off by default.
- **Discord playlist in your presence.** Shows the current Apple Music playlist next to the track.
- **Song-change notifications.** An optional macOS banner on every track change. Off by default.
- **Skip-vote notifications.** Optional banners when a vote starts and when it passes. Off by default.

**The app**

- **Light, Dark, or System appearance.** Pick one in Settings → General. The menu bar follows too.
- **Back up and restore your settings.** Export to a JSON file, restore on another Mac. Accounts and secrets stay in the Keychain. On import, you choose whether to reconnect Twitch.
- **macOS 26 Liquid Glass redesign.** Settings, menu bar, and a rebuilt onboarding wizard for Tahoe.
- **Nightly update channel.** Opt into dev builds off main from Settings → Software Update. Clearly warned, easy to leave, and Stable stays the default.
- **Diagnostics and bug reporting.** Export/Clear Logs and a one-click Report a Bug, with sensitive details redacted.
- **On-device diagnostics.** An opt-in MetricKit report with a share card. Stays on your Mac. Off by default.
- **Branded About window.** A native WolfWave About replaces the macOS default.
- **WolfMark branding.** A new album-art placeholder and brand polish across the app and overlay.
- **Faster overlay URLs.** WolfWave caches your local IP, so settings no longer pause looking it up.

### Changed

- **Clearer settings headings.** Every pane has one big title with section titles a step below, so it reads top to bottom at a glance. VoiceOver can jump between them by heading.
- **Redesigned Settings sidebar.** A branded header, grouped rows with round icon chips, and an accent-colored selection pill. Sections are grouped by what they're for.
- **Calmer destructive buttons.** Reset, Clear Logs, and Clear Artwork Cache drop the loud red bar for a neutral button with a red label. The Danger Zone card gets a red heading instead of a red wash.
- **Type RESET to wipe everything.** The Reset confirmation spells out what it erases and makes you type RESET first, so a stray click can't reset the app.
- **Apple Music playback keeps your focus.** Music never steals focus from OBS or other streaming tools.
- **MusicKit is only used for search**, never for playback.
- **Steadier under stress.** A safety net catches the rare hard crash. If WolfWave goes down, it shows a one-time "Recovered from a crash" notice in Advanced with a one-click bug report.
- **Permissions live in one onboarding step.** Apple Music access, the notification prompt, and the per-alert toggles are now together.
- **Onboarding polish.** Repeated success rows gone, tighter wording, and pinned sizes so nothing jumps around. VoiceOver announces each step by name.
- **Music permission row is actionable.** Tap it to re-request access or jump into System Settings.
- **App Visibility** is a single-column picker for the menu bar, the Dock, or both. General lays Startup and Display Mode side by side.
- **Tighter wording** across onboarding, settings, and the menu bar.

### Performance

- **Lower idle energy use.** Background timers now let macOS batch their wakeups together, which saves power for an all-day menu bar app. Real-time track changes still arrive instantly.
- **No more jank** when switching between settings sections.
- **Faster first paint** and an instant Now-Playing Server row, thanks to off-main-thread font lookup and the cached local IP.

### Developer

> Developer-facing changes. Not visible to end users.

- **Unified design system.** A single `design-system/tokens.json` feeds `generate.ts`, which emits four platform outputs (Swift `Tokens.generated.swift`, docs CSS, widget JS, marketing TS). A Turbo `tokens` task runs as a build prerequisite (#72, #76).
- **Component catalog.** `design-system/components/` gains one markdown entry per reusable view, tracked against a shared template (#76).
- **DEBUG-only Debug tab.** A developer tooling tab (inspectors, service controls, log/event views, UI previews) plus What's New preview controls, only in DEBUG builds (#66, #69).
- **Expanded design-token roster.** `font.size` gains the 9/15/16/18/24/26/28/36 px slots used across views; `space` gains `s0` (2 px), `s10` (32 px), and `s11` (44 px). Token-only additions with no visual change.
- **Sparkle delegate hardening.** Implemented `allowedSystemProfileKeys(for:)` returning an empty array, opting WolfWave out of Sparkle's system-profile telemetry (OS version, CPU arch, and bundle metadata never leave the user's machine on update checks). Documented why `automaticallyDownloadsUpdates = false`: explicit consent is required before bytes touch the disk.
- **WebSocket security-model docs.** Added a `## Security model` block to `WebSocketServerService.swift` describing the loopback-only contract.
- **New unit tests.** `SongBlocklistTests`, `HistoryFormattingTests`, and `LaunchAtLoginServiceTests` cover three previously-untested services.
- **OBS widget build pipeline.** The overlay source moved out of the hand-edited `apps/native/WolfWave/Resources/widget.html` into a new `apps/widget/` Tailwind + TypeScript workspace. The bundled HTML is now a generated, fully inlined artifact (compiled CSS, design tokens, and JS runtime in one file, no external `<link>` or `<script src>`). Xcode ships the committed `widget.html` as-is; CI rebuilds the widget before every `xcodebuild` run in `test.yml` and `build_release.yml` and fails the PR on any drift. Manual rebuild is `bun run --filter widget build`. The WebSocket payload, widget URL, and theme/layout params are unchanged. Source files are heavily commented so the runtime can be read end to end.
- **Inside-out release signing.** `build_release.yml` now signs nested bundles deepest-first before the app shell, dropping `--deep --force`, which stripped per-bundle entitlements. The pipeline is XPC-ready for a future sandbox helper (#199). The signing sweep also matches Sparkle's extension-less `Autoupdate` helper, which the bundle-only globs skipped, leaving it ad-hoc signed with no secure timestamp and failing notarization (statusCode 4000); it now gets the Developer ID identity and secure timestamp like every other nested binary. The same fix is mirrored in `nightly.yml`.
- **Typed NotificationCenter payload helpers.** `Core/NotificationPayloads.swift` centralizes every notification payload post/observe pair so both sides share the same keys and types, removing about 38 hand-decoded `userInfo` sites (#198).
- **HelixClient.** A shared HTTP wrapper for all Helix API calls, replacing per-service `send()` helpers. Maps 401, 429, and structured Helix errors uniformly; covered by `HelixClientTests` (#197).
- **Preferences typed accessor.** `Core/Preferences.swift` centralizes UserDefaults reads and writes for non-bool keys across AppDelegate and WolfWaveApp (#197).
- **Actor adoption.** `SongBlocklist` and `SkipVoteManager` move from `final class + NSLock` to actors; `BotCommandContext` is marked `nonisolated + Sendable`. Combine is fully removed from the app target, with the last publisher replaced by a `.task` loop (#197).
- **Sparkle release notes.** The release pipeline now turns each version's CHANGELOG section into styled HTML (`scripts/release-notes.mjs`) and embeds it in the appcast, so the in-app update dialog shows what's new with a link out to the full changelog.
- **Crash safety net.** `CrashReporter` installs an uncaught-exception handler plus `sigaction` for SIGABRT/ILL/SEGV/FPE/BUS/TRAP (async-signal-safe write path), records a breadcrumb, flushes the log, and chains the previous handler so the OS crash report and MetricKit diagnostics still fire. `guardedStart()` isolates a synchronous service-setup failure, the three `JSONSerialization.data(withJSONObject:)` sites are fronted by `isValidJSONObject`, and a blocking `swiftlint-crash-safety` CI gate runs force-unwrap/try/cast at error severity across production source (#255, #264).
- **Shared helpers, less copy-paste.** Extracted `StringFormatting.truncatedWithEllipsis` (chat-reply truncation), a generic `Atomic<Value>` box in `ThreadSafeStorage.swift` that replaces the hand-rolled `AtomicBool` and Discord state-snapshot locks, `FeatureFlags.songRequestHoldEnabled`, and a Discord button-key resolver, so the duplicated logic lives in one tested place.

### Fixed

- **Twitch bot no longer goes silent after a relaunch.** It now reconnects to your saved channel on its own, so chat commands work without reopening Twitch settings. The reconnect is silent.
- **One recovery card for denied Music access.** No more stacking the same "Music access denied" warning three times. A single card owns the explanation and the Open System Settings button. "Try again" shows a spinner instead of feeling like a dead button.
- **Now-playing survives Apple Music quirks.** The player-state reader accepts every value Music returns, instead of blanking the now-playing card, Discord presence, and overlay while music is playing.
- **Apple Music control under the sandbox.** The "WolfWave wants to control Music" prompt now appears and WolfWave can actually drive Music.
- **Two-PC stream widget works.** Open your overlay from a second computer or your phone on the same network. The Network Address URL in Settings → Stream Widgets now works (and is gated by the access token).
- **Twitch settings card stops jumping** between the signed-out, authorizing, and error states.
- **Onboarding is steadier.** Steps are centered again, the header no longer drifts between steps, and the Preferences step stops overlapping the nav bar on short windows.
- **Recheck and the Sync toggle** force a fresh now-playing read, so the UI catches up right after you grant permission.
- **Apple Music Recheck button** visibly responds when tapped, instead of looking broken.
- **Stats card layout** no longer jumps around and is gated on Apple Music access.
- **Export Logs no longer crashes** on empty or very large logs.
- **About window Check for Updates** now actually runs Sparkle, and Release Notes points at this changelog.
- **Intel Homebrew detection.** Intel Macs installed via Homebrew now disable Sparkle and show the Homebrew update card.
- **Keychain self-heals** a duplicate item that could appear after onboarding.
- **Settings sidebar toggle** cleaned up: one toggle, no floating reveal control.
- Cleaned up build warnings, layout glitches, duplicate log lines, and small icon and window-sizing issues.

### Removed

- **`WallpaperBloomBackground`**, in favor of native macOS chrome.
- **Repeated onboarding success rows**, for a tighter wizard.

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
