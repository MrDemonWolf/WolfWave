# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

WolfWave is a native macOS menu bar app that bridges Apple Music with Twitch, Discord, and stream overlays. It tracks the currently playing song via ScriptingBridge and broadcasts it to Twitch chat via bot commands (EventSub + Helix API), shows "Listening to WolfWave" (with Apple Music album art) on Discord via Rich Presence, and streams now-playing data to overlays via WebSocket.

**Stack**: Swift 5.9+, SwiftUI, AppKit, macOS 26.0+, Xcode 16+. Minimal dependencies (Sparkle for auto-updates); all other functionality uses native Apple frameworks.

**Monorepo**: bun workspaces + Turborepo. The root `package.json` defines workspaces (`apps/*`, `apps/marketing/*`) and Turbo orchestrates `dev`, `build`, and `clean` tasks across packages.

## Skills: use them, every time, by what you're editing

These skills are not optional extras. Invoke the matching skill **before and while editing** the relevant code. Pick by what the change touches:

| Editing | Use these skills |
|---|---|
| Native app (any `.swift` under `apps/native/`) | `swift` (language patterns, concurrency, idioms) **and** `macos` (SwiftUI, AppKit bridging, macOS 26 APIs). For UI/view changes also pull `design` (Liquid Glass, animation, visual patterns). |
| SwiftUI views specifically | `macos` + `design` + `swift`. Review against HIG before finalizing layout, color, control choices. |
| Web frontend (docs site, landing page, OBS widget: `apps/docs/`, `apps/widget/`, any React/TS/CSS/HTML) | `frontend-design` (distinctive, production-grade UI; avoids generic AI look). |
| Tests | `testing` (TDD, characterization, snapshot, test contracts). |
| App Store / release prep | `release-review`, `greenlight`, `app-store-review-audit` as relevant. |

**Research the Swift docs when needed.** When unsure about a Swift / SwiftUI / AppKit / Apple-framework API (signature, availability, behavior, the modern idiom), look it up before writing code. Prefer official Apple developer docs and the Swift language reference over guessing. The `swift` and `macos` skills point at the right patterns; confirm specifics against the docs rather than assuming. Never invent an API or default to a deprecated one.

Default stance: if a change lands in Swift/SwiftUI, the `swift` + `macos` skills are in play. If it lands in web frontend, `frontend-design` is in play. Use them as the work demands, not just when asked.

## Build & Development Commands

### Monorepo (bun + Turborepo)

```bash
bun install                              # Install all workspace dependencies
bun dev                                  # Start all dev servers via Turbo
bun run dev --filter docs                # Start docs dev server only
bun run dev --filter wolfwave-announcement  # Open Remotion studio only
bun run build --filter docs              # Build docs site
bun run --filter widget build            # Rebuild OBS widget (Tailwind → inline)
```

> **OBS widget**: source lives at `apps/widget/`; the bundled
> `apps/native/WolfWave/Resources/widget.html` is a **generated artifact**
> that is **committed** to the repo. Xcode does **not** rebuild it; the
> native build ships the committed file as-is, so contributors who only
> touch Swift never need `bun`. If you edit anything under `apps/widget/`,
> run `make widget` (or `bun run --filter widget build`) and commit the
> regenerated `widget.html` alongside your source change. CI rebuilds the
> widget and fails the PR on any drift between sources and the committed
> output. See `apps/widget/README.md` and the
> [OBS Widget Architecture](apps/docs/content/docs/widget.mdx) docs page.

### Native App (Make)

```bash
make build          # Debug build via xcodebuild
make clean          # Clean build artifacts
make test           # Run unit tests (111 test files; run locally for current pass count)
make test-verbose   # Run unit tests with full xcodebuild output
make test-ci        # Run unit tests in CI mode (writes TestResults.xcresult)
make update-deps    # Resolve SwiftPM dependencies
make open-xcode     # Open Xcode project
make ci             # CI-friendly build (alias for test-ci)
make prod-build     # Release build → DMG in builds/
make prod-install   # Release build → install to /Applications
make notarize       # Notarize the DMG (requires Developer ID + env vars)
make verify-notarize # Verify the notarization ticket is stapled
```

Xcode project is at `apps/native/WolfWave.xcodeproj` with scheme `WolfWave`. Build and run with Cmd+R in Xcode.

## Build Configuration

`Config.xcconfig` holds `TWITCH_CLIENT_ID`, `DISCORD_CLIENT_ID`, `GITHUB_REPO_OWNER`, `GITHUB_REPO_NAME` and is **not committed** (gitignored). Copy from `Config.xcconfig.example` and fill in your keys. Values are expanded into `Info.plist` at build time.

> URL values must escape `//` with `$()` (e.g. `DOCS_URL = https:/$()/...`). xcconfig treats a bare `//` as a comment and silently truncates the value to `https:`, which breaks every derived in-app link (docs, privacy, acknowledgements, community Discord).

### Worktrees: copy the local Config.xcconfig

`Config.xcconfig` is gitignored, so a fresh git worktree under `.claude/worktrees/` won't have one and the native app can't build there. **When working in a worktree and `apps/native/WolfWave/Config.xcconfig` is missing, copy it from the primary checkout before building.** Find it via `git worktree list` (first entry is the main worktree) and copy that worktree's `apps/native/WolfWave/Config.xcconfig` into the current one. Only copy an existing real config; never synthesize one from `Config.xcconfig.example` to unblock a build without asking.

`Info.plist` also contains `SUPublicEDKey` (Sparkle EdDSA public key) and `SUFeedURL` (appcast URL). These are committed and should not be modified unless rotating the Sparkle signing key.

### Entitlements: do NOT remove

`apps/native/WolfWave/WolfWave.entitlements` must keep **all** of the following keys for Music.app control to work under the App Sandbox. Removing any of them will silently break ScriptingBridge: distributed notifications still fire, but `value(forKey:)` reads return nil and the WebSocket broadcasts an empty `playback_state`. See PR #65 / PR #124 history for the regression that proved this the hard way.

| Key | Why it's required |
|---|---|
| `com.apple.security.automation.apple-events` (`true`) | Modern entitlement that lets the sandboxed app request the standard TCC Automation grant for any target. Required for the "WolfWave wants to control Music" prompt to ever appear. |
| `com.apple.security.temporary-exception.apple-events` → `["com.apple.Music"]` | Proven working entry from v1.x. Belt-and-suspenders for pre-existing TCC entries and older macOS revisions. |
| `com.apple.security.scripting-targets` → `com.apple.Music`: `["com.apple.Music"]` | The access-group name here is **not** a real Music.app sdef group, so this entry alone is a no-op; keep it but never rely on it as the only AppleEvents grant. |
| `com.apple.security.temporary-exception.sbpl` (Discord IPC socket regex) | Discord Rich Presence local Unix domain socket. The regex uses the canonical `/private/var/folders/...` path in **both** `WolfWave.entitlements` and `WolfWave.dev.entitlements`. |
| `com.apple.security.temporary-exception.files.absolute-path.read-write` → `/private/var/folders/` | Read-write reach into the per-user temp tree where Discord exposes its `discord-ipc-N` sockets (that dir has a random middle segment, so a path-prefix exception cannot be narrowed below `/private/var/folders/`). Treated as **load-bearing for Discord IPC, pending a removal-safety test**: a 2026-06 audit flagged it as broad, but removing it needs a real signed build plus a Discord-RPC `connect()` check across macOS versions first. Do **not** blind-delete. The dev entitlements file was corrected from `/var/folders/` to the canonical `/private/var/folders/` (the sandbox matches the resolved path, so the old `/var` form silently never matched). |
| `com.apple.security.keychain-access-groups` | Token storage. |
| `com.apple.security.files.user-selected.read-write` | Load-bearing for the Settings backup/restore export and import file pickers, and the log export file picker in the Advanced pane. Without it the sandbox blocks the open/save panels from accessing the user-selected destination. |

If you think one of the apple-events entitlements is redundant: it isn't. Don't remove it.

### `playerState` parsing: do NOT regress to `as? NSNumber`

`AppleMusicSource.checkCurrentTrack` reads Music.app's `playerState` via `SBApplication.value(forKey:)`. **Do not** narrow the parse back to a single `stateObj as? NSNumber` cast; that quietly collapses every other bridge result into `NOT_PLAYING`, which silently blanks the now-playing card, Discord Rich Presence, and the overlay while Music is actively playing. PR #134 fixed the nil-return case; PR #136 fixed the "non-nil but unexpected bridge type" case.

The current decision flow MUST be preserved:

| Layer | Rule |
|---|---|
| `extractPlayerState(_:)` | Tolerant FourCharCode extractor: accept `NSNumber`, `Int`, `UInt32`, `NSAppleEventDescriptor.typeCodeValue`, and 4-byte `String` (e.g. `"kPSP"`). Return nil only for genuinely unknown bridge types. |
| "Track loaded" set | `kPSP` (playing), `kPSp` (paused), `kPSF` (ffwd), `kPSR` (rewind). All four emit the track. **Pausing does not blank the UI** (deliberate: Discord/overlay should reflect the loaded track even while paused). Only `kPSS` (stopped) or empty `currentTrack` map to `NOT_PLAYING`. |
| Fallback emit | If `extractPlayerState` returns nil but `currentTrack.name` is non-empty, trust the track and emit. Log once via `state-parse-fallback` so unknown bridge types surface in Console without spam. |
| Diagnose log | When the parse + emit path resolves to `NOT_PLAYING` while Music is running, `diagnose-not-playing` log fires once with the raw value, bridge type, and currentTrack probe; keep it. Future regressions are invisible without it. |

If a future SDK introduces a new bridge type, **add a branch to `extractPlayerState`**; don't simplify the parser. Coverage is locked in by `AppleMusicSourceTests.testExtractPlayerState*` (7 cases).

### CrashReporter safety net: do NOT regress

`Core/CrashReporter.swift` installs the process-wide last-gasp crash handlers (`NSSetUncaughtExceptionHandler` plus `sigaction` for SIGABRT/ILL/SEGV/FPE/BUS/TRAP). It exists so a hard crash leaves a breadcrumb at `…/Application Support/WolfWave/State/last-crash.marker` before the process dies; the next launch reads it and the Advanced pane shows a one-time "Recovered from a crash" callout. `applicationWillFinishLaunching` installs it (gated off under XCTest). Keep these invariants:

| Rule | Why |
|---|---|
| The **signal handler** stays async-signal-safe (`man 7 signal-safety`): only `open`/`write`/`close`/`strlen`/`signal`/`raise` over the pre-baked malloc'd C path and the C label table. No Swift `String`/`Array` growth, no Foundation, no `Log`. | A signal can fire on any thread mid-allocation. Calling `malloc`, locks, or Foundation there deadlocks or double-faults. Rich work (backtrace, reason, `Log.flush()`) belongs only in the NSException handler, which runs in a normal runtime. |
| **SIGPIPE stays `SIG_IGN`**, never trapped or re-raised. | The app holds long-lived sockets (Discord IPC, WebSocket). A peer dropping mid-write raises SIGPIPE, and the socket code already handles `errno == EPIPE`. A re-raising handler would turn that handled case into a crash. |
| Both handlers **chain**: the exception path calls the previous handler; the signal path captures each prior `sigaction` at install and restores it (falling back to `SIG_DFL` only when none was set) before `raise`. Never `_exit` or swallow. | The OS crash report and MetricKit `MXCrashDiagnostic` (consumed by `DiagnosticsService`) only fire if the crash reaches the default disposition, and the debugger / Swift runtime backtracer install their own signal handlers that a bare `SIG_DFL` reset would drop. |
| The handler funcs and their file-scope globals stay `nonisolated` / `nonisolated(unsafe)`. | The module defaults to `MainActor` isolation, and a `@convention(c)` function cannot be actor-isolated. Marking them `MainActor` breaks the C-function-pointer conversion and won't compile. |

The crash-class lint gate is **blocking** on production source: `.swiftlint-crash-safety.yml` runs `force_unwrapping` / `force_try` / `force_cast` at error severity with `--strict` and no `continue-on-error` (CI job `lint-crash-safety`, local `make lint-crash-safety`). Do **not** add new force-unwraps, `try!`, or `as!` to `apps/native/WolfWave/`. The marker lifecycle is covered by `CrashReporterTests`; never raise a real signal or `NSException` in a test (it kills the xctest host).

## Architecture

**Pattern**: MVVM + Service-Oriented, with an NSApplicationDelegateAdaptor-based lifecycle.

### Core flow

`WolfWaveApp.swift` → AppDelegate manages the menu bar status item, initializes services (`PlaybackSourceManager`, `TwitchChatService`, `DiscordRPCService`, `SparkleUpdaterService`, `SongRequestService`), handles settings + onboarding window lifecycle, and wires song info callbacks into the Twitch and Discord services. AppDelegate is split into `AppDelegate+MenuBar.swift`, `AppDelegate+Services.swift`, and `AppDelegate+Windows.swift`. The system tray menu is dynamic (rebuilt via `NSMenuDelegate` on each open) with now-playing info, quick toggles, hold/resume for the request queue, and conditional items.

### Source layout (`apps/native/WolfWave/`)

- **Core/** - `AppConstants.swift` + `AppConstants+Notifications.swift` (centralized config enums for keys, identifiers, timing, notification names), the `AppDelegate+*` extensions, `KeychainService.swift` (macOS Security framework wrapper), `Logger.swift` (structured logging), `PowerStateMonitor.swift`, `NetworkInfoService.swift` (LAN IP cache), `StreamerMode.swift` (UI-only masking of sensitive values for on-camera safety; observable singleton read across settings views and the menu bar), `SongRequestItem.swift`, `BlocklistItem.swift`. Foundation utilities: `HTTPClient.swift` (shared async HTTP wrapper), `JSONCoders.swift` (shared `JSONEncoder`/`JSONDecoder`), `BugReportURL.swift` (pre-filled GitHub issue URL builder), `Bundle+InstallMethod.swift` (DMG vs Homebrew install detection), `Preferences.swift` / `FeatureFlags.swift` (typed `UserDefaults` accessors; strings/ints and bool toggles, so reads route through one place instead of scattered `UserDefaults.standard` calls), `SharedFormatters.swift` / `ByteFormatting.swift` / `StringFormatting.swift` (shared date, byte, and string-truncation formatting), `ThreadSafeStorage.swift` (`Atomic<Value>`, the `nonisolated @unchecked Sendable` + `NSLock` box used by actor→sync bridge seams like `DiscordRPCService.stateSnapshot` and the Twitch dispatcher flags).
- **Monitors/** - Playback source abstraction. `PlaybackSource.swift` (protocol), `AppleMusicSource.swift` (ScriptingBridge + distributed notifications + 2s fallback polling), `PlaybackSourceManager.swift` (selects + multiplexes sources). Delegate pattern via `PlaybackSourceDelegate`.
- **Services/Twitch/** - `TwitchChatService.swift` (EventSub WebSocket + Helix chat API, thread-safe with NSLock, network path monitoring for reconnection, Twitch user ID redacted in logs; also dispatches `channel.channel_points_custom_reward_redemption.add` and `channel.bits.use` events into the song-request pipeline), `TwitchChannelPointsService.swift` (Helix create / reconcile / fulfill / cancel for the WolfWave-managed "Request a Song" reward), `TwitchDeviceAuth.swift` (OAuth Device Code flow).
- **Services/Twitch/Commands/** - `BotCommand` protocol (`triggers`, `description`, `execute(message:) -> String?`), `AsyncBotCommand` for I/O-bound commands, `BotCommandContext`, `BotCommandDispatcher`. Concrete commands: `TrackInfoCommand` (used for both `!song` and `!last`), `SongRequestCommand`, `QueueCommand`, `MyQueueCommand`, `SkipCommand`, `HoldCommand`, `ClearQueueCommand`, `VoteSkipCommand` (chat vote-to-skip). `CooldownManager` enforces global + per-user cooldowns.
- **Services/SongRequest/** - `SongRequestService.swift` (request flow orchestrator; `processRequest(query:username:source:)` takes a `RequestSource` so chat commands, channel-point redemptions, and bit cheers share the same pipeline), `SongRequestAccess.swift` (`RequestAudience` chat-command gate, `RequestSource`, `SongRequestPreset` one-tap configurations, `RedemptionStatus` for the settings re-auth banner), `SongRequestQueue.swift` (queue with hold mode, Music.app-closed buffering, and a `boost(username:)` method for bit-cheer boosts), `SkipVoteManager.swift` (chat vote-to-skip sessions: chat tally or Twitch Polls), `SongSearchResolver.swift` + `LinkResolverService.swift` (MusicKit search / Apple Music link resolve), `AppleMusicController.swift` (AppleScript playback with focus preservation), `SongBlocklist.swift`.
- **Services/Discord/** - `DiscordRPCService.swift` (Discord Rich Presence via local IPC Unix domain socket, auto-reconnect with backoff).
- **Services/UpdateChecker/** - `SparkleUpdaterService.swift` (Sparkle framework wrapper for auto-updates, EdDSA-signed appcast verification, Homebrew install detection disables Sparkle, DEBUG mode allows manual check via bundled `dev-appcast.xml`).
- **Services/WebSocket/** - `WebSocketServerService.swift` (overlay broadcast, per-install auth-token handshake; connections must present `Sec-WebSocket-Protocol: wolfwave.token.<hex>` or get rejected), `WidgetHTTPService.swift` (static widget HTTP server; auto-injects the auth token into served `widget.html` for loopback peers).
- **Services/ListeningHistory/** - `ListeningHistoryService.swift` (opt-in, on-device append-only NDJSON play log; records a track only after it crosses the half-length or 4-minute mark so skips don't count), `StatsAggregator.swift` (top artists / listening time / 7-day trend / listening-by-hour rollups powering History & Stats), `MonthlyWrap.swift` (per-month "wrapped"-style summary + share-card export), `HistoryFormatting.swift` (date/duration formatting helpers).
- **Services/Notifications/** - `NotificationService.swift` (opt-in macOS banners via `UNUserNotificationCenter`; song-change, skip-vote-started, and skip-vote-passed each reuse a stable per-type identifier so a new banner replaces the previous one of its kind instead of stacking. Skip-vote-started is silent; skip-vote-passed uses the default system sound. Static `make…Content` builders keep the text pure and unit-testable. Skip-vote events arrive via `SkipVoteManager.onVoteEvent`, gated in `AppDelegate.handleVoteEvent` on both `voteSkipEnabled` and the matching per-event toggle. The service is also the `UNUserNotificationCenterDelegate` (installed at launch) so banners still present while WolfWave is frontmost, and it owns the Twitch re-auth banner via `postTwitchReauthNeeded()`, which only posts when authorization is already granted - boot paths must never trigger the system permission prompt).
- **Services/** - `ArtworkService.swift` (iTunes Search artwork fetch + cache), `LaunchAtLoginService.swift`, plus `DiagnosticsService.swift` (opt-in MetricKit diagnostics + share card).
- **Views/** - SwiftUI settings shell `SettingsView.swift` with `NavigationSplitView` sidebar. Per-section views decomposed into `GeneralSettingsView.swift`, `MusicMonitor/MusicMonitorSettingsView.swift`, `AppVisibility/AppVisibilitySettingsView.swift`, `WebSocket/WebSocketSettingsView.swift` (Stream Widgets: token reveal/regenerate/edit controls), `Twitch/TwitchSettingsView.swift`, `Discord/DiscordSettingsView.swift`, `SongRequest/SongRequestSettingsView.swift` + `SongRequestQueueView.swift`, `Notifications/NotificationsSettingsView.swift`, `HistoryStats/HistoryStatsSettingsView.swift` + `StatsChartsView.swift` + `MonthlyWrapView.swift` (SwiftUI Charts powered, gated on the opt-in Listening History setting), `About/AboutSettingsView.swift`, `Advanced/AdvancedSettingsView.swift`. `TwitchViewModel` is the main observable for auth/connection state.
- **Views/Onboarding/** - macOS 26 Liquid Glass onboarding wizard. The `OnboardingStep` enum (in `OnboardingViewModel.swift`) defines the step order: Welcome → Discord → Twitch → OBS Widget (overlay URL + HTTP widget toggle) → Preferences → Permissions (Apple Music automation only) → Notifications (notification authorization + the song-change / skip-vote alert toggles) → Menu Bar Pointer, followed by `OnboardingCompletionView`. Permissions and Notifications are deliberately two separate screens so each has a single job. Components in `Onboarding/Components/` (`PillButton`, `BrandTile`).
- **Views/Debug/** - **DEBUG-only** developer tooling tab. `DebugSettingsView.swift` shell plus cards: `DebugInspectorsCard`, `DebugLogsAndEventsCard`, `DebugMetricsCard`, `DebugServiceControlsCard`, `DebugUIPreviewsCard`. Not compiled into release builds.
- **Views/Shared/** - Shared UI components: `StatusChip`, `InfoRow`, `ToggleSettingRow`, `SuccessFeedbackRow`, `SectionHeaderWithStatus`, `NowPlayingHeroCard`, `AlbumArtView`, `IntegrationDashboardView`, `ConnectionTestButton`, `ConfigRequiredBanner`, `CopyButton`, `UpdateBannerView`, `WhatsNewView`, `WarningBanner`, `ActionGrid`, `LoadingRow`, `MusicPermissionBanner`, `DSIconButton`, `TwitchGlitchShape`, `ViewModifiers`, `SettingsNavRail` (shared two-column jump-nav rail + scroll-sync used by General, Debug, Song Requests, and History & Stats; sections conform `SettingsRailSection` and tag their top view with `.railSection(_:)`; panes that use it bypass `standardDetailScroll` in `SettingsView.detailPane` to own the full pane width). Sensitive fields wrap their value in a `StreamerMode.shared` check before rendering; when Streamer Mode is on, the value is replaced with a `••••••` mask and Copy/Open buttons are disabled.

### Key patterns

- **Credentials**: All tokens/secrets stored via `KeychainService` (never UserDefaults). Keys defined in `AppConstants.Keychain`.
- **Settings**: User preferences in `UserDefaults` via `@AppStorage`. Keys centralized in `AppConstants.UserDefaults`. Note: `currentSongCommandEnabled`, `lastSongCommandEnabled`, and `widgetHTTPEnabled` all default to `false`.
- **Notifications**: Loose coupling via `NotificationCenter` (e.g., `TrackingSettingChanged`, `DockVisibilityChanged`). Names in `AppConstants.Notifications`.
- **Thread safety**: `NSLock` for shared state mutations in `TwitchChatService`. `DiscordRPCService` uses `ipcQueue` serial queue confinement plus `enabledLock` for thread safety. Logger uses a serial `DispatchQueue` for thread-safe file I/O.
- **Bot commands**: Register new commands in `BotCommandDispatcher.registerDefaultCommands()`. Each command implements `BotCommand` protocol. Max response 500 chars, target <100ms execution.
- **Discord IPC**: Unix domain socket at `$TMPDIR/discord-ipc-{0..9}`. SBPL entitlements enable socket access within App Sandbox.
- **ADHD-friendly text**: All user-facing text should be short, punchy, and jargon-free.

## Design System

Single source of truth: [`design-system/tokens.json`](design-system/tokens.json). The generator [`design-system/scripts/generate.ts`](design-system/scripts/generate.ts) emits five platform outputs; **do not edit generated files by hand**:

| Output | Path | Consumer |
|---|---|---|
| Swift | `apps/native/WolfWave/Core/DesignSystem/Tokens.generated.swift` | Native app: `DSColor`, `DSFont`, `DSSpace`, `DSRadius`, `DSMotion`, `DSDimension` |
| CSS | `apps/docs/app/tokens.generated.css` | Fumadocs site (`--ds-*` custom properties) |
| Widget JS | `apps/native/WolfWave/Resources/widget-tokens.generated.js` | `widget.html` reads via `window.WW_TOKENS` |
| Marketing TS | `apps/marketing/shared/tokens.generated.ts` | Remotion projects |
| Docs widget themes TS | `apps/docs/app/(home)/_widgets/widget-themes.generated.ts` | `USER_THEMES`, `WIDGET_THEMES`, `WIDGET_LAYOUTS`, `DEFAULT_THEME`, `DEFAULT_LAYOUT` for the landing-page OBS overlay preview |

### Regenerating

```bash
bun run tokens          # Direct
bun turbo tokens        # Via Turbo (cached when inputs unchanged)
bun turbo build         # `tokens` is a build prerequisite; runs automatically
```

`turbo.json` declares `//#tokens` as a root task; both `build` and `dev` `dependsOn` it. Inputs: `design-system/tokens.json` + `design-system/scripts/generate.ts`. Outputs: the five generated files above.

### Widget themes (`window.WW_TOKENS`)

`widget.html` consumes `WW_TOKENS.themes` (6 themes: `Default`, `Dark`, `Light`, `Glass`, `Neon`, `WolfWave`) and `WW_TOKENS.layouts` (`Horizontal`, `Vertical`, `Compact`). Themes live in `tokens.json` under `widget.themes`; add or edit there, then regenerate. `WidgetHTTPService` serves `widget-tokens.generated.js` at `/widget-tokens.generated.js`, loaded via `<script src>` before the inline script.

### Component catalog

[`design-system/components/`](design-system/components/) - one markdown entry per reusable view. Status tracked in [`design-system/components/README.md`](design-system/components/README.md). Every entry follows the same template (Purpose, API, Tokens used, Anatomy mermaid, Accessibility, Do/Don't, Example); see [`status-chip.md`](design-system/components/status-chip.md) as the quality bar.

**When you touch any of these views, update the matching catalog entry in the same change.** That keeps token usage docs and anatomy diagrams from drifting.

### Design-system discipline

These rules are enforced by [`design-system/scripts/lint.ts`](design-system/scripts/lint.ts) (`bun run ds:lint`, also run in CI):

- **Never** use literal numbers in `font(.system(size:))`; use `DSFont.Size.*` (`xs=10`, `sm=11`, `body=12`, `base=13`, `md=14`, `lg=17`, `xl=20`, `x2xl=22`, `x3xl=26`). Heading ramp: `.paneTitle()` (22 bold, H1) → `.sectionHeader()` (17 semibold, H2) → `.sectionEyebrow()` (11 semibold secondary, H3); body via `.fieldSubtitle()` (13) / `.captionText()` (10). The old `.sectionSubHeader()` (15) was retired 2026-06-05 because it collided with the 17pt pane title; `x3xl` (26) is reserved for hero + the Monthly Wrap share card.
- **Never** use literal numbers in `spacing:` or `.padding(N)`; use `DSSpace.*` (`s0=2`, `s1=4`, `s2=8`, `s3=10`, `s4=12`, `s5=14`, `s6=16`, `s7=20`, `s8=24`, `s9=28`, `s10=32`, `s11=44`).
- For single-glyph bordered buttons, use [`DSIconButton`](apps/native/WolfWave/Views/Shared/DSIconButton.swift); do **not** hand-roll `Button { Image(...) } .buttonStyle(.bordered) .controlSize(.small)`. Hand-rolled icon-only buttons collapse to a narrower frame than text-label neighbors like `CopyButton`, causing visible drift.
- When you touch a `Views/Shared/` component, update its catalog entry in [`design-system/components/`](design-system/components/) in the same change.

Existing legacy literals are tracked in [`design-system/lint-allowlist.txt`](design-system/lint-allowlist.txt); migrate them file-by-file in follow-up PRs. Do **not** add new entries.

## Testing

Unit tests live in `apps/native/WolfWaveTests/` and use XCTest + Swift Testing with `@testable import WolfWave`. The test target is a hosted unit test bundle (`TEST_HOST` = WolfWave.app). Current file count: 111 test files (run `ls apps/native/WolfWaveTests/*.swift | wc -l` to verify).

> Auto-discovery: `apps/native/WolfWaveTests/` is a `PBXFileSystemSynchronizedRootGroup`; dropping a new `*.swift` file in is enough, no Xcode project edit required.

### Test files

- `SparkleUpdaterServiceTests.swift` - Sparkle wrapper init, manual check gating, Homebrew detection
- `TrackInfoCommandTests.swift` - `TrackInfoCommand` covering both `!song`/`!currentsong`/`!nowplaying` and `!last`/`!lastsong`/`!prevsong` trigger sets via shared fixtures (trigger matching, case insensitivity, enable/disable, callback, default message, 500-char truncation)
- `BotCommandDispatcherTests.swift` - Message routing, callback wiring, length guards, whitespace handling
- `CommandIntegrationTests.swift` - End-to-end dispatcher flow per command
- `CooldownManagerTests.swift` - Global + per-user cooldown enforcement
- `SongRequestServiceTests.swift`, `SongRequestQueueTests.swift`, `SongRequestCommandTests.swift`, `HoldCommandTests.swift`, `SongBlocklistTests.swift` - Song Request system (queue, hold mode, request command parse, blocklist)
- `LaunchAtLoginServiceTests.swift` - SMAppService registration/unregister state
- `SkipVoteManagerTests.swift`, `VoteSkipCommandTests.swift` - Chat vote-to-skip (threshold, dedup, window expiry, cooldown, subscriber gate, Polls mode, reply formatting)
- `SongRequestAccessTests.swift` - `RequestAudience` permission rules, `SongRequestPreset` apply/detect, `RedemptionStatus` banner messages
- `SongRequestQueueBoostTests.swift` - bit-cheer boost: moves a user's most-recent queued item to the front
- `TwitchChannelPointsServiceTests.swift` - Helix create / reconcile / fulfill / cancel for the WolfWave-managed "Request a Song" reward
- `TwitchBitsParsingTests.swift` - `channel.bits.use` message parsing (cheermote fragment stripping)
- `StatsCommandTests.swift` - `!stats` live-gating via `stream.online` / `stream.offline` EventSub
- `StreamerModeTests.swift` - masking rules + Streamer Mode toggle persistence
- `ListeningHistoryServiceTests.swift`, `PlayLogStoreTests.swift`, `RecentTracksBufferTests.swift`, `HistoryFormattingTests.swift`, `StatsAggregatorTests.swift`, `MonthlyWrapTests.swift`, `LifetimeTallyTests.swift` - opt-in History & Stats pipeline (NDJSON append, rollups, monthly wrap, lifetime totals)
- `NotificationServiceTests.swift` - song-change notification banner dedup + identifier reuse
- `MetricsServiceTests.swift`, `DiagnosticsServiceTests.swift`, `DebugDiagnosticsTests.swift` - Opt-in MetricKit diagnostics + Debug-tab diagnostics
- `WebSocketServerAuthTests.swift` - Per-install auth-token handshake (rejects missing/mismatched `wolfwave.token.<hex>` subprotocol)
- `TwitchEventSubDedupTests.swift` - EventSub `message_id` dedup (at-least-once delivery: TTL expiry, cap eviction, no timestamp refresh on dup)
- `TwitchConnectionStateHubTests.swift` - per-subscriber connection-state streams (multi-subscriber fan-out, single-subscriber termination, finish-all)
- `PreferencesResolvedPortTests.swift` - clamped widget/WebSocket port resolution (0 falls back to default, out-of-range clamps instead of trapping)
- `AppleMusicControllerTests.swift` - AppleScript playback dispatch + focus preservation
- `LinkResolverServiceTests.swift`, `SongSearchResolverTests.swift` - MusicKit search + Apple Music link resolve
- `MusicPermissionBannerTests.swift`, `MenuStatusFormatterTests.swift`, `OnboardingCompletionViewTests.swift`, `ActionGridTests.swift`, `LoadingRowTests.swift`, `WarningBannerTests.swift` - Shared view + onboarding state coverage
- `HTTPClientTests.swift`, `ArtworkServiceNetworkTests.swift`, `TwitchDeviceAuthNetworkTests.swift`, `AppConstantsConfigOverrideTests.swift` - Foundation utilities + config plumbing
- `AppleMusicSourceTests.swift` - Playback source start/stop and delegate wiring
- `OnboardingViewModelTests.swift` + `OnboardingViewModelEdgeCaseTests.swift` - Step navigation, boundary conditions, UserDefaults persistence
- `TwitchViewModelTests.swift`, `TwitchChatServiceTests.swift`, `TwitchDeviceAuthTests.swift`, `TwitchDeviceAuthErrorTests.swift` - Twitch auth + EventSub + view model state
- `DiscordRPCServiceTests.swift` - IPC framing, reconnect backoff
- `DiscordPresenceBuilderTests.swift` - Rich Presence payload construction (state/details, buttons, timestamps)
- `ArtworkServiceTests.swift`, `ArtworkServiceCacheTests.swift` - iTunes Search artwork fetch + cache eviction
- `WebSocketServerServiceTests.swift`, `WebSocketServerIntegrationTests.swift`, `WidgetHTTPServiceTests.swift` - Overlay broadcast + widget HTTP
- `KeychainServiceTests.swift` - Save/load/delete, Unicode, concurrent access
- `LoggerTests.swift`, `PowerStateMonitorTests.swift` - Core utilities (logging incl. log clearing, power state). Log-clear tests are direct members of the `.serialized` "Logger Tests" suite so the truncating `clearLogFile()` can't race the file-readback tests.
- `BugReportURLTests.swift` - Pre-filled GitHub issue URL construction and encoding
- `BundleInstallMethodTests.swift` - DMG vs Homebrew (cask) install detection
- `AppConstantsTests.swift` + `AppConstantsEdgeCaseTests.swift` - Constant values, URL validity, dimension bounds, cross-references

### Writing tests

- Use `@testable import WolfWave` (module name matches `PRODUCT_NAME`)
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` applies to test classes too; XCTest runs on main thread
- Test files are auto-discovered via `PBXFileSystemSynchronizedRootGroup`; just add `.swift` files to `apps/native/WolfWaveTests/`
- Focus on pure logic (version comparison, command matching, state machines); avoid tests that need AppDelegate, Keychain, or network

## CI/CD

- `.github/workflows/test.yml` - Runs `xcodebuild test` on every push/PR to `main` (path-filtered to native changes). Creates a placeholder `Config.xcconfig` for CI builds and sets `MallocNanoZone=0` to work around a runner-image allocator crash.
- `.github/workflows/build_release.yml` - Builds, signs, notarizes, and creates a GitHub Release on tag push (`v*`). Required secrets: `DEVELOPER_ID_CERT_P12`, `DEVELOPER_ID_CERT_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`, `TWITCH_CLIENT_ID`, `DISCORD_CLIENT_ID`, `SPARKLE_PRIVATE_KEY`.
- `.github/workflows/docs.yml` - Builds and deploys the Fumadocs site to GitHub Pages.
- `.github/workflows/update_homebrew.yml` - Opens a PR on the Homebrew tap after a GitHub Release is published.
- `.github/workflows/update_sponsors.yml` - Refreshes the GitHub Sponsors list. `.github/workflows/license-year.yml` - Keeps the `LICENSE` year current.

### Sparkle Auto-Updates

Sparkle uses EdDSA (Ed25519) signing for update verification. The public key is in `Info.plist` as `SUPublicEDKey`. The private key is stored in the developer's macOS Keychain and as the `SPARKLE_PRIVATE_KEY` GitHub secret for CI.

- **DEBUG builds**: Sparkle is instantiated with `startingUpdater: false` (no background checks). Manual "Check Now" works and the `SPUUpdaterDelegate.feedURLString(for:)` callback points Sparkle at the bundled `dev-appcast.xml` (dummy v99.0.0 entry), so the full Sparkle UI is exercisable without a real release.
- **Release builds**: Sparkle checks the remote appcast at the `SUFeedURL` in Info.plist.
- **In-app release notes**: At release time, `scripts/release-notes.mjs` renders the version's `CHANGELOG.md` section into a styled, self-contained HTML file named to match the DMG (`WolfWave-X.Y.Z.html`). `generate_appcast` embeds that matching-name HTML as the appcast item `<description>`, so Sparkle's update dialog shows what's new. The `### Developer` block is dropped from the in-app notes (it stays on the web changelog), and a footer links out to the full changelog. `dev-appcast.xml` carries a styled sample so DEBUG "Check for Updates" previews the same rendering. The workflow runs the script via `bun` before the "Generate Sparkle appcast" step in `build_release.yml`.
- **Homebrew installs**: Sparkle is fully disabled (updates managed by Homebrew).
- **Key management**: Run `generate_keys` from Sparkle's tools to view/export/import keys. The tool is at `SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys` in DerivedData.

## Documentation

Docs site built with Fumadocs (Next.js) at `apps/docs/`. Content in `apps/docs/content/docs/` as `.mdx` files. Sidebar defined in `apps/docs/content/docs/meta.json` with Guide/Developers sections. Deployed to GitHub Pages. Run with `bun run dev --filter docs` from root.

> The site is a **static export** (GitHub Pages), served under the `/wolfwave` base path in production (empty in dev). A fresh git worktree under `.claude/worktrees/` has no `node_modules`, so run `bun install` once before `bun run dev`/`build` there. The preview launch config is named `docs` (port 3000); in dev the OG routes serve at `/opengraph-image` (no `.png`).

> **Docs card styling gotcha.** Fumadocs puts `data-card=""` + `class="peer"` on every heading's permalink anchor, so a bare `a[data-card]` selector borders every docs heading too. Style real `<Cards>` with `a[data-card]:not(.peer)` (or `a[data-card="true"]`) in `global.css`.

### Landing page (`app/(home)`)

The marketing home is `app/(home)/page.tsx`, an **async server component** that fetches the GitHub star count + latest release tag at build time (`getRepoStats()`, graceful fallback) so the trust chips show live-at-build data without shipping third-party shields.io images.

- **Section spine.** Every section is a `<section id="…">` introduced by a numbered `Kicker` (01–09) via the shared `Kicker` / `CenterHead` helpers. Order: hero → `audiences` (01) → `twitch` (02) → `discord` (03) → `overlay` (04) → `compare` (05) → `download` (06, the "Open & trusted" proof band) → `developers` (07) → `privacy` (08) → `faq` (09) → `cta`. **Keep the section `id`s stable**; the navbar links to them (`lib/layout.shared.tsx`: Features→`/#audiences`, Compare→`/#compare`, FAQ→`/#faq`) and other CTAs target `#download`. If you reorder, renumber the kickers to match.
- **Widgets** live in `app/(home)/_widgets/`: `HeroNowPlaying`, `DiscordPresenceCard`, `OBSOverlayWidget`, `TwitchChatPreview` (recreated Twitch chat, intentionally dark in both themes), `ComparisonTable` (responsive: real table ≥`md`, stacked cards `<md`), `BackToTop` (landing-only floating button, rendered from `page.tsx`), `AlbumArt`, the shared `useCyclingTrack` demo timer, and `sample-tracks.ts`. **All demo data is invented**; sample tracks are wolf songs with wolf-species "artists". Never use real artists, song titles, or album art.
- **Styling** uses `ww-*` utility classes in `app/global.css` (`ww-kicker`, `ww-stat`, `ww-proof`, `ww-chip`, `ww-card`, `ww-glass`, `ww-btn`, `ww-pill`, `ww-to-top`). Reuse these instead of one-off styles. Brand color tokens (`--brand-*`, `--bg-*`, `--txt-*`, `--hairline`) flip per theme.
- **Apple corner geometry.** Rounded surfaces opt into `corner-shape: squircle` (Apple's continuous superellipse) via an `@supports` block; Chromium renders the true squircle, every other browser falls back to the existing `border-radius`. The app-icon squircle uses Apple's **22.37%** ratio. Capsule/pill controls keep true-capsule ends; do **not** squircle them.
- **Flat by default.** Resting elements are flat; defined by a hairline border (and optional *subtle* shadow), never by bevels or float. No inset white highlights, no glassy `::before` sheen, no heavy multi-layer drop shadows. `.ww-glass` is a flat frosted card (frost + border only). Keep drop shadows shallow (e.g. `0 8-10px 24-28px -16px` at low alpha). **Hover-lifts are fine** (subtle `translateY` + brand-tinted shadow on `:hover` only). The OG image (`og-card.tsx`) is a rendered social card, not an on-page element, so it keeps real depth; don't flatten it.
- **Mobile gutters.** Sections use `px-[10%] md:px-6` → content is ~80% width (centered) on phones/tablets, reverting to the `max-w-*` cap on desktop. Use this pattern on new sections rather than a fixed `px-6`.
- **Mobile centering.** Section headers and short feature intros center on mobile (`text-center md:text-left`); card bodies and docs long-form stay left-aligned for readability.

### SEO & Open Graph images

The docs site generates Open Graph / Twitter card images at build time. Both paths are wired so changing page copy updates the social card. Do **not** hand-edit generated PNGs.

**Per-page docs cards (automatic).** Each MDX file under `content/docs/` drives its own card via `apps/docs/app/og/docs/[...slug]/route.tsx`, which reads these optional frontmatter fields and falls back to a section preset in `apps/docs/app/og/_components/og-presets.ts`:

| Frontmatter field | Card slot | Fallback |
|---|---|---|
| `ogTitle` | headline | `title` |
| `ogDescription` | sub-line | `description` |
| `ogEyebrow` | pill | preset by first slug segment |
| `ogChips` | chip row | preset by first slug segment |
| `keywords` | `<meta keywords>` | none |

The changelog page is special-cased: its card is built from the latest `## vX.Y.Z` block in `changelog.mdx`, not from chips. The shared card visual lives in `apps/docs/app/og/_components/og-card.tsx` (`OgCard` + `ChangelogOgCard`).

> `OgCard` renders its headline **one word per flex item** so Satori wraps on word boundaries instead of clipping a single long flex child; don't collapse it back to one text node. Long descriptions are truncated (~120 chars) so the chip row never falls off the 1200×630 frame, and the body is top-aligned so a tall block can't overflow up into the wordmark header.

**Homepage / root card (single source of truth).** Homepage social copy lives in one constant, `homepageSeo` in `apps/docs/lib/site.ts`. It feeds `app/layout.tsx` (root meta + JSON-LD), `app/(home)/page.tsx` (homepage meta), `app/opengraph-image.tsx`, and `app/twitter-image.tsx`. Edit `homepageSeo` once and the meta tags plus both images update on the next build.

**The rule when you touch SEO or visible copy:**

- Changed a docs page's title, description, or pitch: update that page's frontmatter (`ogTitle` / `ogDescription` / `ogChips` / `keywords`) so its card matches.
- Changed the homepage or landing pitch: edit `homepageSeo` in `lib/site.ts`. Never hardcode homepage strings back into `layout.tsx`, `opengraph-image.tsx`, or `twitter-image.tsx`.
- Added a new docs page: start from the frontmatter template below so the card and SEO match the rest of the site.

**New-page frontmatter template:**

```yaml
---
title: Short page title
description: One-sentence search snippet, around 150 chars, keyword-rich.
ogTitle: Card headline (defaults to title)
ogDescription: Card sub-line (defaults to description)
ogEyebrow: Small pill label
ogChips:
  - Three
  - Or four
  - Short
  - Chips
keywords:
  - primary long-tail phrase
  - secondary phrase
---
```

**OG image standards (what a good card follows):**

- 1200x630 px (1.91:1). This is `OG_SIZE`; do not change it.
- Keep total weight well under 8 MB. Text cards from `next/og` are tiny, so no action needed unless you embed heavy raster art.
- Leave roughly 60 px of breathing room around key text. X, iMessage, and Discord crop the frame differently, so center-weight the message.
- One headline plus three or four chips. High contrast, large type, no paragraphs.
- Use absolute image URLs (`absoluteUrl(...)`; `metadataBase` is set) and `twitter:card = summary_large_image`.
- Give every image real `alt` text.

**Validate after a change:**

1. `bun run build --filter docs`. The OG routes are `force-static`, so they build here and fail the build on a code error.
2. Eyeball the PNGs locally (`bun run dev --filter docs`): `/opengraph-image.png`, `/twitter-image.png`, and a page card such as `/og/docs/installation/image.png`.
3. After deploy, re-scrape with opengraph.xyz, the Facebook Sharing Debugger, the X Card Validator, and the LinkedIn Post Inspector. Social platforms cache cards hard, so a rebuild alone will not refresh what people already saw.

## Marketing

Remotion-based video projects live in `apps/marketing/`. Each subfolder is a standalone Remotion project (React + TypeScript) for producing announcement/promo videos.

- **wolfwave-announcement** - v1.0 launch announcement video. Run `bun run dev --filter wolfwave-announcement` from root to open the Remotion editor.

## Known Harmless Runtime Noise

These lines appear in Xcode console / stdout but are emitted by macOS itself, not WolfWave. Safe to ignore; do not chase them as bugs:

- `Rule path is not accessible: /var/protected/xprotect/...` and `Error reading rules: (null)` - XProtect / sandbox introspection denial.
- `FSFindFolder failed with error=-43` - legacy Carbon API noise from a system framework.
- `CoreSVG has logged an error. Set environment variable "CORESVG_VERBOSE" to learn more.` - system SVG renderer; unrelated to our assets. Set `CORESVG_VERBOSE=1` only if you want to investigate.
- `Unable to obtain a task name port right for pid …: (os/kern) failure (0x5)` - sandbox blocks task-port introspection of other processes.

## Code Conventions

- Swift 5.9+ with async/await concurrency (no DispatchQueue for new async work)
- MARK sections organize every file (Properties, Public Methods, Private Helpers, etc.)
- DocC-style `///` comments on all public APIs
- No force unwrapping; use optionals and guard
- MVVM for views: ViewModels use `@Observable` macro (migrated from `ObservableObject`/`@Published`)
- Prefer structs for data models, classes for services
- camelCase for variables/functions, PascalCase for types

## Versioning

Follows [Semantic Versioning (SemVer)](https://semver.org/): `MAJOR.MINOR.PATCH`:

- **MAJOR** - Breaking changes (API incompatibility, dropped platform support)
- **MINOR** - New features, backward-compatible
- **PATCH** - Bug fixes, security patches, code quality improvements

Version is set in `MARKETING_VERSION` in `project.pbxproj` (4 occurrences). `CURRENT_PROJECT_VERSION` (build number) must also be incremented with each release; Sparkle uses it as the primary version comparator in appcast.xml. Git tags use `v` prefix (e.g., `v1.0.1`). The release workflow triggers on `v*` tag pushes. Homebrew cask, CHANGELOG.md, and GitHub Release notes must all be updated to match.

### Release Checklist

Run through every item before pushing the release tag.

1. **`apps/native/WolfWave.xcodeproj/project.pbxproj`** - bump `MARKETING_VERSION` (4 occurrences) and `CURRENT_PROJECT_VERSION` (4 occurrences). Sparkle uses the build number as its primary comparator.
2. **`CHANGELOG.md`** - add `## [X.Y.Z] - YYYY-MM-DD` entry in Keep-a-Changelog format. The release workflow renders this exact section into Sparkle's in-app update notes via `scripts/release-notes.mjs`, so write it for users first and keep developer-only items under `### Developer` (that subsection is stripped from the in-app notes).
3. **`apps/docs/content/docs/changelog.mdx`** - add `## vX.Y.Z. Month DD, YYYY` entry in MDX format (the OG card reads the latest `## vX.Y.Z` block).
4. **Push git tag** - `git tag vX.Y.Z && git push origin vX.Y.Z` triggers the release workflow (builds, signs, notarizes, creates GitHub Release).
5. **Homebrew cask** - auto-updated by `update_homebrew.yml` after the GitHub Release is created. Verify the workflow ran successfully.

> After tagging, verify the GitHub Actions release workflow completes cleanly before announcing.
