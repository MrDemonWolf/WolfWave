# Changelog

All notable changes to this project will be documented in this file.

## [2.1.0] - Unreleased

> The next release. These changes ship on the [Nightly channel](https://mrdemonwolf.github.io/wolfwave/docs/nightly) off `main` until 2.1.0 is tagged for stable, when this heading gets its date.

### Security

- **Safer local widget credentials.** Token-bearing HTML is served only to a true loopback peer using a literal local Host and is marked `no-store`; token changes are saved to Keychain before connected clients rotate.

### Added

- **Custom bot commands.** Make your own chat commands with a fixed reply, right in Settings → Twitch → Custom Commands. Drop in variables like `$user`, `$touser`, `$args`, `$1`–`$9`, `$song`, and `$lastsong` and they fill in live. Each command gets its own aliases and Everyone / Per-person cooldowns, same as the built-ins.
- **Pick who can run a command.** Set any custom command to Everyone, Subscribers, VIPs, Moderators, or Broadcaster only. Custom commands ride along with your settings backup.
- **Approve songs before they play.** New opt-in "Require My Approval" toggle in Settings → Song Requests → Access. When it's on, every request (chat, channel points, bits) waits in the Queue tab until you approve or decline it. Off by default, so requests still auto-queue unless you turn it on.
- **Fair-share song ordering.** The queue now interleaves requests round-robin, so everyone's first request plays before anyone's second. A regular who re-types fast no longer plays back-to-back while newcomers wait. On by default; flip "Fair-Share Ordering" off in Settings → Song Requests → Queue for classic first-in, first-out.
- **Sub / VIP request priority.** Reward your subs, VIPs, and mods: pick a perk in Settings → Song Requests → Queue. "Skip cooldown" lets them request without the wait; "Jump the queue" also moves their song ahead of regular requests within the same fair-share round (so it's a nudge up, not a queue takeover). Off by default.
- **Two new overlay layouts: Vinyl and Classic.** Vinyl is a spinning record with your album art as the label and a circular progress ring. Classic sets the album tile beside a card with the title, artist, and a progress bar. Pick either in Settings → Stream Widgets, same as Horizontal, Vertical, and Compact.
- **Queue ticker overlay.** Add `?queueTicker=1` to your widget URL for a panel showing the next 3 song requests, title and requester, so viewers see their spot in line. Off by default, matches your current widget theme.

### Changed

- **A custom WolfWave mark.** The familiar wolf now carries a padded side equalizer, used consistently across the app icon, menu bar, onboarding, OBS fallback, Discord art, DMG installer, docs, and repository branding.
- **Settings toggles all look the same now.** Launch at Login, "Check automatically" (Software Update), and "Collect on-device diagnostics" (Advanced) now use the standard row: name and short description on the left, switch on the right. Same layout as every other toggle in Settings.
- **Lighter on your Mac.** WolfWave does a lot less work between songs now. Chat lines that aren't commands bail out immediately, the request poller sleeps when nothing is playing and the queue is empty, and Discord and your overlay only get an update when something actually changed instead of every few seconds. The History pane stopped re-sorting your whole play log twice on every redraw. Same features, less CPU and battery.
- **Lighter OBS overlay.** Progress painting is batched at 10 Hz, and animation work stops while the page is hidden or unloaded and when reduced motion is enabled.
- **Less background work.** WolfWave now pauses unused overlay, Twitch, song-request, and Discord tasks instead of polling or retrying while those features are idle, disconnected, held, hidden, or disabled.
- **What's New only shows up for feature releases.** The window used to reappear after every version bump, including bug-fix ones, showing a stale feature list. It now opens once per release that actually ships features.
- **Dev builds have their own app icon.** If you build WolfWave from source, the Debug app now carries an orange icon instead of the blue one, so **WolfWave Dev** and the release app are easy to tell apart in the Dock and the app switcher. Nothing changes for anyone installing from a DMG or Homebrew.

### Fixed

- **Twitch sign-in survives service hiccups.** Device-code login now uses the original expiry deadline, follows the required polling slowdown and timeout backoff, and keeps trying through rate limits plus temporary network or server failures instead of failing early.
- **Twitch no longer mistakes an outage for an expired sign-in.** Only Twitch's explicit token rejection or confirmed missing permissions prompts a reconnect. Network errors, rate limits, and malformed refresh responses retry within a bounded window and leave saved credentials intact when Twitch remains unavailable.
- **Twitch account changes stay internally consistent.** Access tokens, refresh tokens, account identity, and the configured channel now change together in one Keychain write. Existing saved fields migrate without deleting the originals until the new record is safe. Imported and edited channel names are checked with Twitch before becoming canonical; invalid, missing, stale, or temporarily unverifiable names stay pending.
- **Settings backups preserve authored rules.** Custom bot commands and the Song Request blocklist now round-trip with other portable preferences, and Reset Settings clears the centralized blocklist data.
- **Slow Twitch commands no longer hold up chat.** Song requests and custom commands run as tracked connection work, so keepalives and later messages continue; disconnecting or switching channels cancels old replies before they can land in the wrong chat.
- **Paid Twitch actions recover after quits and outages.** Channel-point intake and fulfill/refund outcomes are durable until Twitch acknowledges them. Qualifying Bits cheers persist the complete boost/request action before queue work and replay after relaunch. If local recovery storage fails, WolfWave pauses the managed reward, shows a warning, and still gives an already-paid Bits cheer one process-owned attempt.
- **Discord presence replies no longer cross wires or hang indefinitely.** Each local IPC command consumes the response with its own nonce, the handshake accepts only Discord's READY dispatch, and stalled local connects or replies now stop at one bounded deadline.
- **Duplicate Twitch commands stay single-shot.** Command message IDs keep their complete replay window even in busy chat, including while commands are disabled, so delayed EventSub redelivery cannot rerun queue or playback actions.
- **Local WebSocket peers can no longer hold unlimited resources.** WolfWave caps pre-handshake peers, expires stalled handshakes, limits inbound messages to 16 KiB, and cleans every old listener generation before retrying.
- **Stream Deck reconnects no longer crash while a socket is still opening.** Retiring a connecting socket now keeps the required error sink until close.
- **Stream Deck control is local-only and no longer shares your overlay secret.** WolfWave now keeps separate read-only overlay and control tokens. Stream Deck protocol v2 always connects to this Mac, so LAN widgets can still receive track data but can never run playback or queue commands. After updating, copy the new **Stream Deck Control Token** into the plugin once.
- **Twitch custom commands stay locked while disconnected.** The settings card now explains that Twitch must be connected and closes an open editor if the connection becomes unavailable.
- **Twitch stays connected when its server moves you.** Twitch periodically hands your connection to a different server. WolfWave could flash "disconnected" and tear down the new, healthy connection while doing that. It rides through cleanly now.
- **Low Power Mode no longer stalls launch.** Startup reads the posted power-state snapshot without recursively initializing the monitor.
- **Discord presence settings apply immediately.** Idle presence and "hide while paused" changes refresh at once, preserve the paused track for restoration, and stay hidden when Discord is enabled mid-pause.
- **Apple Music stays closed when you close it.** WolfWave no longer reopens Music.app after you quit it, and no longer opens it on its own while running.
- **WolfWave tells you when Music isn't open.** The now-playing card used to say "Nothing playing right now" whether Music was closed or just idle. It now says "Apple Music isn't open" with an Open Music button when the app is shut.
- **Settings sidebar no longer opens too narrow.** The sidebar could come back squeezed from a previous session and cut off section names like "Stream Widgets". It now uses a fixed width, matching System Settings, and a stale saved width can no longer be restored over it.
- **Version history opens instead of downloading.** Clicking "version history" in the update window saved an HTML file to your Downloads instead of showing the changelog. The notes are embedded in the update feed now, so they render in place.
- **Overlays keep working after you change the token or port.** Regenerating your access token or changing the port could leave every new OBS source getting rejected until you restarted WolfWave.
- **No more crashes from bad saved data.** A corrupted settings backup could crash the app the next time chat ran `!voteskip`, and one bad line in your listening history could crash the History pane and `!stats` every time they drew. Both are handled now, and a full disk no longer takes the app down while it's writing a log.
- **No more freezes from song requests.** WolfWave now talks to Apple Music off the main thread, so a slow or busy Music.app can't beachball the app while the request queue auto-advances or when you hit play, pause, or skip.
- **Stream Deck overlay key stays connected.** The action now hides or shows overlay cards without dropping the authenticated control socket, so the next key press and its acknowledgement still work.
- **Advanced settings opens instantly.** Log size and line count load in the background now, so a large log file no longer stalls the pane when it appears.
- **Album art stays current.** A slow old lookup can no longer replace the current track's art, temporary download failures remain retryable, and the tray's decoded-art cache is bounded.
- **Accurate lifetime stats after a hard quit.** Listening History no longer double-counts old plays if WolfWave is force-quit or crashes while it's trimming its history.
- **Song requests survive playback races.** A failed or cancelled Apple Music start no longer loses the next request, and overlapping clears or queue edits while Music is responding can no longer revive an old item or overwrite the new order. Playlist setup coalesces simultaneous creation and stale-playlist recovery, follows every discovery page safely, and never adopts a same-name playlist that the user made.
- **Vote-skip stays with the poll and song that started it.** Delayed or unrelated Twitch poll results can no longer skip a replacement track or clear the real active poll. If Twitch may have created a poll but did not return a trustworthy answer, WolfWave waits for timeout instead of opening a simultaneous chat tally or second poll.
- **History clears and rankings stay exact.** Clearing history during its launch-time disk read can no longer restore old plays, finite retention no longer resurrects undated lifetime data, and tied stats and Monthly Wrap results are deterministic.
- **Clean Twitch sign-in cancel.** Cancelling the Twitch connect flow no longer flashes a false "OAuth setup failed" error.
- **Steadier under the hood.** Hardened Discord Rich Presence against a rare bad-playback-position crash, stopped a Twitch rate-limit wait from spinning the CPU when a connection drops, and made LAN IP detection skip a bad network interface instead of showing a blank overlay address.
- **Nightly testers can get back to Stable.** Switching the Update Channel back to Stable now works on its own: the next stable release offers itself like any other update, instead of leaving you stuck until you manually reinstalled the DMG. One exception, one time: if you installed the August 5, 2026 nightly, grab any newer DMG once — that specific build can't update itself. See [Nightly Builds](https://mrdemonwolf.github.io/wolfwave/docs/nightly).

### Developer

- Docs restructure: merged the Features/Usage and Getting Started/Development pages, added Settings and Stream Deck Control API pages, trimmed the comparison page, and refreshed the legal pages.
- Debug builds can treat every chatter, or selected Twitch logins, as normal viewers for permission and cooldown testing. Release builds omit the simulator.

- New `BotCommand.isAllowed(context:)` permission hook and `allTriggers` protocol requirement (both default-preserving, so built-ins are unchanged). `CustomBotCommand` is an `AsyncBotCommand` built per message from `CustomCommandStore`, so edits apply on the next chat line without re-registration. Pure `CustomCommandRenderer` covers variable substitution; 21 new tests.
- Stream Deck control API (groundwork for the upcoming plugin, WW-36). The overlay WebSocket is now bidirectional: it parses a protocol-versioned inbound `command` envelope, runs it through a router mapping 11 actions to existing services, and replies with an `ack`; new `queue_state` / `health` broadcasts drive counter/health keys. The connection is still gated by the per-install `wolfwave.token.<hex>` handshake. Pure `StreamDeckControl.parse` with new tests. See `apps/native/docs/streamdeck-control-api.md`.
- Adversarially-verified crash/lockup/data-race review pass. `AppleMusicController` runs `NSAppleScript` on `@MainActor` with bounded Apple Event timeouts, and `playbackSnapshot()` plus the playback commands are `async` for structured-concurrency callers (the dead `isPlaying`/`isPaused`/`currentTrackID` reads were dropped). `RateLimiter.awaitCapacity` unwinds on cancellation instead of busy-spinning. `LifetimeTally` gained an optional `lastFoldedTimestamp` high-water mark so a crash-recovery reload can't re-fold overflow records, and `ListeningHistoryService` coalesces concurrent loads. Plus the Stream Deck overlay toggle now changes card visibility without stopping the authenticated WebSocket control channel or companion HTTP server, alongside a finiteness guard on Discord presence timestamps, an off-main log-stats read in the Advanced pane, a Twitch sign-in cancel guard, and a `getnameinfo` return-code check.
- `queue_state` gained a `held` field carrying real request-queue hold state (`SongRequestService.isHoldEnabled`), and `SongRequestHoldChanged` now triggers a Stream Deck rebroadcast alongside `SongRequestQueueChanged`. Without it a hold key had to track its own optimistic toggle, which inverted the moment hold was changed from the tray, chat (`!hold`), or Settings. Additive on an outbound broadcast, so no `protocolVersion` bump — the version gates the inbound command envelope only.
- Stream Deck plugin, Phase B (WW-45), in the new `apps/streamdeck/` bun workspace. Consumes the Phase A control API: `src/wolfwave/protocol.ts` is the TypeScript mirror of `StreamDeckCommand.swift` (action tokens are the Swift enum's raw values; a test pins the full v1 set so the two can't drift), `state.ts` is a pure reducer that returns the same reference on an unchanged fold so per-second `progress` frames don't repaint keys, and `client.ts` holds one shared socket for all keys with capped reconnect backoff and FIFO ack correlation. Eleven key classes over a base that paints the disconnected / unauthorized / outdated states centrally, plus a Property Inspector that talks Elgato's protocol directly rather than loading `sdpi-components` from a CDN. Bundled for Node (Stream Deck runs `CodePath` under its own Node), output gitignored — it ships through Elgato, not inside the app. Icons are generated from the brand mark by `scripts/generate-icons.ts` (SVG everywhere Elgato allows it, so there is no @1x/@2x pair to drift; PNG only for the plugin icon, which Elgato requires), and `bun run --filter streamdeck pack` produces the `.streamDeckPlugin`. A new CI job typechecks, tests, packages, and fails on icon drift. **Still outstanding**: verification on real hardware, and the Marketplace submission itself.
- Steady-state performance pass: ten hot-path fixes, all behaviour-preserving, each removing work that repeated every ~5s tick or per chat line. `BotCommandDispatcher` early-outs on a missing `!` prefix before the command-table snapshot copy and per-command alias `UserDefaults` reads; `SongRequestService.pollTick` early-outs when nothing is playing and the queue is empty, skipping a 2s AppleScript round trip; `AppleMusicController` uses targeted `runningApplications(withBundleIdentifier:)` and caches compiled `NSAppleScript` by source; `DiscordRPCService.updatePresence` skips unchanged `SET_ACTIVITY` frames and `WebSocketServerService.updateNowPlaying` skips unchanged rebroadcasts; widget artwork only refetches on a genuine track change; `MusicMonitorSettingsView` stops restarting `AsyncImage` every tick; `HistoryStatsSettingsView` dropped a twice-per-body-pass O(n log n) sort over up to ~10k records; `SongBlocklist.isBlocked` lowercases once instead of per entry.
- Concurrency correctness pass: ten adversarially-verified race and leak fixes. `TwitchChatService` now posts `NotificationCenter` from `@MainActor` (panes observe via `.onReceive` with no main hop) and bails out of `handleReceiveError` on `Task.isCancelled` so an orphaned receive loop can't undo a session migration; `DiscordRPCService.connectIfNeeded` re-validates generation/enabled/fd after its two-await handshake; `WebSocketServerService` detaches `stateUpdateHandler` before cancel and cancels failed connections; `MonthlyWrapView.loadTint` guards cancellation. Leaks closed in `TwitchViewModel.deinit` (connection-observer task), `TwitchChatService.deinit` (URLSession), and `NotificationService` (stranded artwork temp files when authorization is denied). `MusicPermissionCache` traded `nonisolated(unsafe)` statics for `@MainActor` isolation.
- Crash-guard pass: four process-abort vectors reachable from external or user-writable data, none caught by the force-op lint gate. `Int(Double)` traps clamped in `MetricsService.recordTwitchRateLimit` (a `Ratelimit-Reset` header of `inf`/`nan`/`1e999`), `SkipVoteManager.sessionCooldown` (unclamped and exportable, so a corrupt backup crashed the next `!voteskip`), and `HistoryFormat.listeningTime`/`clock` (plus sanitizing `duration`/`playedSeconds` at the `PlayRecord` decode boundary). `Logger` swapped six legacy raising `synchronizeFile()`/`closeFile()` sites for `try? synchronize()`/`close()`, which were aborting mid-error-handling on fsync `ENOSPC`/`EIO`. Regression tests feed `inf`/`nan`/`1e300` to each converter.
- DRY pass across the codebase: 20 mechanical extractions, no behaviour change. Shared HTTP-response / widget-config / now-playing / JSON-guard helpers, an EventSub body + form-POST + custom-rewards URL builder, shared day-bucketing and history-store filesystem helpers, a shared song-request dedup predicate and capacity insert, `BotCommand.commandToken(in:)` shared across the command match loops, `SectionHeaderWithStatus` reused at 10 hand-rolled header sites, and centralized setting + widget-appearance defaults.
- Source layout split for readability, no behaviour change: `AppConstants` into per-namespace `extension` files, `DiscordRPCService` into a pure `DiscordPresenceBuilder` plus an IPC seam, and the `TwitchChatService` actor across same-actor seam files (`+Auth`, `+Connection`, `+EventSub`, `+Redemptions`).
- Dead code removed and stale doc comments corrected: ~89 unused lines from `ViewModifiers` (`interactiveRow`, `cardClipShape`, the reduce-motion helpers, the `NotificationCenter.post(_:)` shorthand), plus doc fixes across `PlaybackSourceManager`, `SettingsView`/`SettingsNavRail`, `TwitchViewModel`, `AppConstants`, `SparkleUpdaterService`, `WidgetHTTPService`, and the Discord / Twitch / WebSocket settings views, each verified against the actual code.
- Swift file headers normalized to the header Xcode generates from `IDETemplateMacros.plist`, with each `Created by` date reset to the file's real git creation date. New `scripts/check-headers.mjs` (`make lint-headers`, plus a blocking CI job) keeps them from drifting again.
- CI hardening: new SwiftLint baseline gate blocks new violations without requiring the existing backlog to be cleared, and the full test suite now runs unskipped on `macos-26` (the weekly canary is retired). Sparkle appcast generation passes `--embed-release-notes` and fails the build if the notes aren't inline. Nightly releases are titled by their build commit's short SHA while keeping the fixed rolling `nightly` tag the appcast depends on.
- `AGENTS.md` added (Codex guidance mirroring `CLAUDE.md`), and `FEATURE_IDEAS.md` retired in favour of Jira project `WW`.
- Docs site and landing page pass: WCAG AA/AAA contrast in both themes (new `--brand-fill` token for white-on-blue fills), mobile hardening (40px+ tap targets, single-column stat grid under 420px, opaque mobile TOC backing, the sticky first table column the CSS comment had only promised), de-AI'd copy, the redundant "Open & trusted" proof band dropped with the section spine renumbered to a contiguous 01–08, per-page eyebrows moved from in-body spans to the route, corrected download / on-disk size claims measured against the shipped v2.0.1 artifacts, and Instrument Sans replacing Unbounded.
- OBS resource pass: the browser batches progress paint at 10 Hz and fully suspends when hidden/unloaded/reduced-motion; native progress work exists only while enabled, visible, playing, and serving clients, and JSON fan-out encodes once.
- Idle-service pass: Twitch owns one keepalive/session with bounded classified retries and tears network work down on leave; Song Requests stops auto-advance polling while idle/held/disabled; Discord polls availability only while enabled and disconnected; decoded tray art is single-flight and bounded to 64 items / 32 MiB; duplicate startup warming was removed and reduced-power policy applies immediately.
- Music.app is now addressed by **pid**, never by bundle identifier. A bundle-id-addressed Apple event is auto-launched by LaunchServices, so `SBApplication(bundleIdentifier:)` and a bare `tell application "Music"` both start Music when it isn't running; `LSLaunchFlags` has no opt-out. Guarding with an is-running check before the send only narrows the race, which is why this shipped twice before (#203, #273) and came back both times. `AppleMusicSource` now resolves `MusicProcess.pid` and uses `SBApplication(processIdentifier:)`, and `AppleMusicController.timeoutWrapped` gates every script on `application "Music" is running` (evaluated without launching), raising `-600` when closed so callers take their existing no-information path. Note that `SBApplication(processIdentifier:)` does **not** return nil for an unresolvable pid as its header claims — it returns a non-KVC-compliant object whose `value(forKey:)` raises `NSUnknownKeyException`, so the read is gated on `isRunning` + `responds(to:)`. New shared `Core/MusicProcess.swift` replaces three duplicated is-running checks; a SwiftLint custom rule now bans `SBApplication(bundleIdentifier:`.
- Local Debug builds sign with a stable Apple Development identity instead of ad-hoc. Ad-hoc signatures derive from the binary hash, so every rebuild looked like a different app and invalidated both the Keychain ACL and the TCC Automation grant, producing a password prompt on each launch. CI keeps ad-hoc signing (`test-ci` unchanged) and the Makefile falls back to it when no identity is present.
- `scripts/check-test-results.sh` fixes: it summed the per-suite *and* enclosing-suite `Executed N tests` lines (an 18-test suite reported as 54), its failure-detail grep matched none of the formats xcodebuild actually emits, and it ignored Swift Testing entirely — so a failing `@Test` reported zero failures and exited 0.
- `WidgetHTTPServiceTests` no longer pins ports 59995/59993; both tests use the existing `startBoundService` port walker, so a lingering socket or a running WolfWave can't fail the suite.
- Build/version standard, applied to both release feeds. New `scripts/version.sh` is the single source of truth for marketing version + build number; `build_release.yml` and `nightly.yml` both call it and inject `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` at build time, so the pbxproj build number is now a dev-only placeholder and is no longer hand-bumped. Build number is `git rev-list --count HEAD` (floored), shared by both channels — the retired nightly scheme used a UTC minute stamp (~2×10¹¹), which is ~100× over Android's `versionCode` cap and sat so far above stable that no release could ever overtake it. Both workflows now need `fetch-depth: 0`; the resolver hard-fails on a shallow clone. Rationale and the portable cross-platform rules are in `docs/build-versioning-standard.md`. `version.sh` also warns when the committed `MARKETING_VERSION` still equals the newest `v*` tag, since nightlies advertise the *next* release version and that means the post-release bump-ahead was skipped.
- Documentation sync across the repo. `README.md` and `CLAUDE.md` corrected to Swift 6.0 / Xcode 26 (both still claimed 5.9 / 16), five bot commands had undocumented aliases added (`!request`, `!songrequest`, `!songlist`, `!requests`, `!mysongs`, `!musicstats`, `!cq`), `!hold`/`!resume` collapsed into the single command it actually is, and the seven undocumented `make` targets added, including all four lint entry points. `apps/streamdeck/` is now named in the README feature list and project tree instead of being referred to hypothetically. `CLAUDE.md` gained the three missing source files (`MusicProcess.swift`, `DebugDiagnostics.swift`, `OnboardingView.swift`), the four missing test files, the `//#ds:lint` root task, and an accurate CI table (the `test.yml` bullet described one job; there are seven, plus three drift gates). The dead `usage.mdx` reference was replaced with `settings.mdx` in both `CLAUDE.md` and the PR template. `apps/widget/README.md` asserted a closed set of six URL params and was missing `queueTicker`. The design-system catalog documented three modifiers deleted in the 2.1.0 dead-code sweep (`interactiveRow`, `Animation.reducedMotion`, `reduceMotionAware`), `design-system/README.md` listed a `tokens.schema.json` that never existed and claimed the docs site renders the catalog, and `OnboardingStepScaffold` had no catalog entry despite the README promising full coverage. The shipped nightly-channel plan and the Stream Deck control API doc are now marked as historical and living-reference respectively.
- `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1), and `.github/ISSUE_TEMPLATE/config.yml` added. The config disables blank issues and routes feature ideas to Discord, which is where they have gone since `FEATURE_IDEAS.md` was retired.
- `AUDIT.md` removed. Its 100 findings were all resolved back in 2.0.0 per its own Resolution block, and it cited two files that no longer exist plus a test count roughly 3x low.
- `tokens.schema.json` is now enforced, not just advisory. New `bun run ds:schema` (`design-system/scripts/validate-tokens.ts`) validates `tokens.json` against it and runs as a step on the existing `ds-lint` CI job. The schema shipped without anything executing it, so it only helped editors that honour `$schema` and could drift from `tokens.json` unnoticed. It was verified correct before wiring: `tokens.json` validates clean, and nine injected mistakes (dropped namespace, typo'd namespace, unknown namespace, malformed hex, wrong scalar type, empty theme/layout maps) are all rejected. The `ds-lint` path filter previously covered only Views and the lint script, so it now also watches `tokens.json`, the schema, `package.json`, and `bun.lock`; the job gained a `bun install` step because `ds:lint` is dependency-free but `ds:schema` needs `ajv`. Adding a new top-level token namespace now requires updating the schema in the same change, which is the intended coupling: `generate.ts` reads namespaces by name and emits five platform outputs without checking shape first.

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

- **Stream Widgets now need an access token.** Every WebSocket client must authenticate with a per-install token kept in the Keychain. Localhost HTML receives it from WolfWave; LAN links carry it as connection bootstrap. Existing OBS sources keep working. Reveal, regenerate, or replace the token in Settings → Stream Widgets.
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
- **Widget themes and layouts.** Five selectable themes (Default, Dark, Light, Glass, Neon), plus a hidden internal WolfWave theme, and five layouts (Horizontal, Vertical, Compact, Vinyl, Classic).
- **Live widget preview.** See your overlay update as you tweak the theme, layout, font, and colors.
- **Smoother OBS widget.** Songs slide in, fade out calmly, and crossfade on fast skips. No strobing.
- **Discord idle and pause controls.** Keep an idle marker when nothing plays, or clear your profile while paused. Both off by default.
- **Discord playlist in your presence.** Shows the current Apple Music playlist next to the track.
- **Song-change notifications.** An optional macOS banner on every track change. Off by default.
- **Skip-vote notifications.** Optional banners when a vote starts and when it passes. Off by default.

**The app**

- **Light, Dark, or System appearance.** Pick one in Settings → General. The menu bar follows too.
- **Back up and restore your settings.** Export to a JSON file, restore on another Mac. Credentials and private account IDs stay in the Keychain; the public Twitch channel name travels with your preferences. On import, you choose whether to reconnect Twitch.
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
