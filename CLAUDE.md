# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

WolfWave is a native macOS menu bar app that bridges Apple Music with Twitch, Discord, and stream overlays. It tracks the currently playing song via ScriptingBridge and broadcasts it to Twitch chat via bot commands (EventSub + Helix API), shows "Listening to WolfWave" (with Apple Music album art) on Discord via Rich Presence, and streams now-playing data to overlays via WebSocket.

**Stack**: Swift 6.0, SwiftUI, AppKit, macOS 26.0+, Xcode 26+. Minimal dependencies (Sparkle for auto-updates); all other functionality uses native Apple frameworks.

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
bun run build                            # Build every workspace in dependency order
bun run clean                            # Clean workspace build artifacts
bun run tokens                           # Regenerate design tokens (root task //#tokens)
bun run ds:lint                          # Design-system lint (root task //#ds:lint)
bun run ds:schema                        # Validate tokens.json against tokens.schema.json
bun run ds:test                          # Unit-test the design-system lint rules themselves
bun run dev --filter docs                # Start docs dev server only
bun run dev --filter wolfwave-announcement  # Open Remotion studio only
bun run build --filter docs              # Build docs site
bun run --filter widget build            # Rebuild OBS widget (Tailwind → inline)
bun run --filter streamdeck build        # Bundle the Stream Deck plugin
bun run --filter streamdeck test         # Stream Deck plugin tests (bun test)
```

> **Stream Deck plugin**: `apps/streamdeck/` is the Elgato plugin consuming the
> app's control API. Unlike the widget, its bundle is **not** committed and is
> **not** shipped inside the app; it's distributed through Elgato. `src/wolfwave/`
> is the TypeScript mirror of `Services/WebSocket/StreamDeckCommand.swift`: the
> action tokens are the Swift enum's raw values and `PROTOCOL_VERSION` must equal
> `StreamDeckControl.protocolVersion`. **Change one side, change the other**, and
> bump the protocol version on any breaking envelope change. Protocol v2 uses a
> dedicated `wolfwave.control.<hex>` credential and fixed loopback transport; the
> OBS widget uses a separate read-only `wolfwave.overlay.<hex>` credential that
> can never authorize commands. The plugin bundle
> lives at `apps/streamdeck/com.mrdemonwolf.wolfwave.sdPlugin/` (`manifest.json`
> plus the `ui/` Property Inspector); `manifest.json` is a `streamdeck#build` turbo
> input and both it and the Property Inspector have their own tests. The `streamdeck`
> CI job runs `typecheck`, `bun test`, `pack`, and an icon-drift check on any change
> under `apps/streamdeck/`, so a protocol mismatch fails the PR. Icons are generated
> from the brand mark by `scripts/generate-icons.ts`; regenerate rather than hand-editing
> them, or the drift check fails. See `apps/native/docs/streamdeck-control-api.md`
> and `apps/streamdeck/README.md`.

<!-- Separates the two blockquotes; a bare blank line between them trips markdownlint MD028. -->

> **OBS widget**: source lives at `apps/widget/`; the bundled
> `apps/native/WolfWave/Resources/widget.html` is a **generated artifact**
> that is **committed** to the repo. Xcode does **not** rebuild it; the
> native build ships the committed file as-is, so contributors who only
> touch Swift never need `bun`. If you edit `apps/widget/`, run `make widget`
> (or `bun run --filter widget build`). If you edit design tokens or their
> generator, run `bun run tokens` first, or use the ordered root
> `bun run build`. Commit the regenerated `widget.html` (and any token
> outputs) with the source change. CI regenerates both layers and fails the
> PR on drift. See `apps/widget/README.md` and the
> [OBS Widget Architecture](apps/docs/content/docs/widget.mdx) docs page.

### Native App (Make)

```bash
make build          # Debug build via xcodebuild
make clean          # Clean build artifacts
make test           # Run unit tests (run locally for the current file + pass count)
make test-verbose   # Run unit tests with full xcodebuild output
make test-ui        # Run the XCUITest suite (launches and drives the real app)
make test-ci        # Run unit tests in CI mode (writes TestResults.xcresult)
make update-deps    # Resolve SwiftPM dependencies
make open-xcode     # Open Xcode project
make ci             # CI-friendly build (alias for test-ci)
make widget         # Rebuild the OBS widget into Resources/widget.html
make icons          # Regenerate the Debug app icon (AppIcon.icon -> AppIcon-Dev.icon)
make check-drift    # Regenerate widget/tokens/SponsorConfig/app icon and fail on drift (mirrors CI)
make sponsor-config # Regenerate SponsorConfig.generated.swift from FUNDING.yml
make prod-build     # Release build → DMG in builds/
make prod-install   # Release build → install to /Applications
make notarize       # Notarize the DMG (requires Developer ID + env vars)
make verify-notarize # Verify the notarization ticket is stapled

# Lint. All four also run as their own CI jobs; the last two are blocking.
make lint           # SwiftLint against swiftlint-baseline.json
make lint-baseline  # Regenerate that baseline (ratchet: it may only shrink)
make lint-crash-safety # No new force_unwrapping / force_try / force_cast
make lint-headers   # Swift file-header convention check
```

`sponsor-config` is a prerequisite of `build`, every `test*` target, and `prod-build`, so
it normally runs on its own. Invoke it directly only when regenerating after a
`FUNDING.yml` edit.

Xcode project is at `apps/native/WolfWave.xcodeproj` with scheme `WolfWave`. Build and run with Cmd+R in Xcode. The Debug action must resolve to `WolfWave Dev.app`, display as **WolfWave Dev**, and use bundle ID `com.mrdemonwolf.wolfwave.dev`; Release remains `WolfWave.app` / `com.mrdemonwolf.wolfwave`. Do not collapse those identities or point the Debug scheme runnable at the Release product.

Debug and Release also ship **different app icons**, so the two are distinguishable in the Dock, the app switcher, and Spotlight when both are installed. Both are Icon Composer bundles under `WolfWave/Resources/`:

| Config | `ASSETCATALOG_COMPILER_APPICON_NAME` | Bundle | Artwork |
|---|---|---|---|
| Debug | `AppIcon-Dev` | `AppIcon-Dev.icon` | brand blue + a bottom-centre `DEV` badge |
| Release | `AppIcon` | `AppIcon.icon` | brand blue |

The icon is **always the blue WolfWave icon**; the only thing Debug adds is the badge. `AppIcon.icon` is the hand-authored source of truth, and **`AppIcon-Dev.icon` is a generated artifact** derived from it by [`scripts/generate-app-icons.ts`](scripts/generate-app-icons.ts): same background fill, the same `logo` layer (light/dark `fill-specializations`, scale, group shadow and translucency all carried through verbatim), plus an `iconwolf-development-badge.svg` layer in its own group.

The badge follows the [iconwolf](https://github.com/mrdemonwolf/iconwolf) development-badge convention already shipping in ConPaws (`apps/native/assets/images/ConPaws-development.icon`): a fixed bottom-centre pill at `304,724,416x176,rx44`, lettering drawn as a grid of 16pt squares from a 5x7 pixel font. Two rules that are easy to undo by accident:

- **The lettering is rectangles, not SVG `<text>`.** A text node depends on a font being installed and resolving identically wherever the icon is compiled; rectangles render the same everywhere. Adding a letter means adding a glyph to `GLYPHS`.
- **The badge group is emitted first.** Icon Composer draws the first group on top, and the wolf fills the canvas, so a badge appended last renders behind the mark with the lettering struck through by the waveform leg.

Generation is pure string assembly with no rasterisation, so the output is byte-identical on every host and CI can diff it.

**Do not hand-edit `AppIcon-Dev.icon`.** When the mark changes, update `AppIcon.icon/Assets/logo.svg` and run `make icons`. `Resources/` is a `PBXFileSystemSynchronizedRootGroup`, so a new `.icon` bundle is picked up without editing the project file.

All `make test*` targets use the ignored `DerivedData/Tests` directory. This keeps their unsigned test host from replacing the signed Debug app in Xcode's normal DerivedData. Test hosts also default `KeychainService` to process-local storage before any suite setup, so tests must never read, write, or prompt for the user's real dev Keychain.

## Build Configuration

`Config.xcconfig` holds `TWITCH_CLIENT_ID`, `DISCORD_CLIENT_ID`, `GITHUB_REPO_OWNER`, `GITHUB_REPO_NAME` and is **not committed** (gitignored). Copy from `Config.xcconfig.example` and fill in your keys. Values are expanded into `Info.plist` at build time.

> URL values must escape `//` with `$()` (e.g. `DOCS_URL = https:/$()/...`). xcconfig treats a bare `//` as a comment and silently truncates the value to `https:`, which breaks every derived in-app link (docs, privacy, acknowledgements, community Discord).

### Worktrees: copy the local Config.xcconfig

`Config.xcconfig` is gitignored, so a fresh git worktree under `.claude/worktrees/` won't have one and the native app can't build there. **When working in a worktree and `apps/native/WolfWave/Config.xcconfig` is missing, copy it from the primary checkout before building.** Find it via `git worktree list` (first entry is the main worktree) and copy that worktree's `apps/native/WolfWave/Config.xcconfig` into the current one. Only copy an existing real config; never synthesize one from `Config.xcconfig.example` to unblock a build without asking.

#### Each worktree has its own DerivedData

Xcode derives the DerivedData directory name from the project's **path**, so every worktree gets its own `~/Library/Developer/Xcode/DerivedData/WolfWave-<hash>/`. Inspecting a build product without confirming which one you are in is a reliable way to verify the wrong thing: a stale `WolfWave Dev.app` from another worktree looks exactly like a change that failed to take effect. This produced a false negative while verifying the Debug app icon (PR #406) — the built app appeared unchanged because the `.app` being read was a week-old artifact from a different worktree.

Resolve the path from the build itself rather than guessing:

```bash
# The DerivedData dir for THIS worktree
xcodebuild -project apps/native/WolfWave.xcodeproj -scheme WolfWave -showBuildSettings \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $2; exit}'
```

If several candidates exist, the newest build wins; `find ~/Library/Developer/Xcode/DerivedData -name 'WolfWave Dev.app' -maxdepth 6` plus the timestamp disambiguates. Also note `xcodebuild ... -quiet` (what `make build` uses) suppresses the error detail on failure, so rerun without `-quiet` when a build result looks wrong.

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

`WolfWaveApp.swift` → AppDelegate manages the menu bar status item, initializes services (`AppleMusicSource`, `TwitchChatService`, `DiscordRPCService`, `SparkleUpdaterService`, `SongRequestService`), handles settings + onboarding window lifecycle, and wires song info callbacks into the Twitch and Discord services. AppDelegate is split into `AppDelegate+DockMenu.swift`, `AppDelegate+MenuBar.swift`, `AppDelegate+Services.swift`, `AppDelegate+StreamDeck.swift` (Stream Deck command router + state broadcasts), and `AppDelegate+Windows.swift`. The system tray menu is dynamic (rebuilt via `NSMenuDelegate` on each open) with now-playing info, quick toggles, hold/resume for the request queue, and conditional items.

### Source layout (`apps/native/WolfWave/`)

- **Core/** - `AppConstants.swift` split across per-namespace `extension` files: `AppConstants+Notifications.swift`, `AppConstants+Discord.swift`, `AppConstants+Twitch.swift`, `AppConstants+URLs.swift`, `AppConstants+UserDefaults.swift` (centralized config enums for keys, identifiers, timing, notification names), the `AppDelegate+*` extensions, `KeychainService.swift` (macOS Security framework wrapper; Twitch access token, refresh token, resolved identity, and configured channel share one crash-atomic versioned record with copy-then-delete migration from legacy fields), `LogTailCursor.swift` (incremental log tailing: bounded priming, partial-line carry, re-prime on truncate/rotate), `Logger.swift` (structured logging; `LogCategory` is the ONLY accepted category type, there is no `String` overload, so a typo is a compile error; logfmt-style line `<ISO8601>  <LEVEL>  <Category>  <File.swift:line>  <message>[ key=value…]`, one invariant: a record starts with an ISO-8601 timestamp at column 0 and a line starting with whitespace is a continuation. Grammar + redaction rules in `apps/native/docs/logging-format.md`), `LogRecord.swift` (the pure, canonical **reader** for that format, used by the Debug log viewer, the diagnostics export, and external tooling. Do not hand-roll a second parser), `PowerStateMonitor.swift`, `NetworkInfoService.swift` (LAN IP cache), `StreamerMode.swift` (UI-only masking of sensitive values for on-camera safety; observable singleton read across settings views and the menu bar), `SongRequestItem.swift`, `BlocklistItem.swift`. Foundation utilities: `HTTPClient.swift` (shared async HTTP wrapper), `JSONCoders.swift` (shared `JSONEncoder`/`JSONDecoder`), `BugReportURL.swift` (pre-filled GitHub issue URL builder), `Bundle+InstallMethod.swift` (DMG vs Homebrew install detection), `Preferences.swift` / `FeatureFlags.swift` (typed `UserDefaults` accessors; strings/ints and bool toggles, so reads route through one place instead of scattered defaults calls), `DefaultsStore.swift` (the single `UserDefaults` instance every non-`@AppStorage` read and write goes through; resolves to an isolated suite under test so the hosted bundle can never edit the dev app's live domain, mirroring `KeychainService.backend`), `SharedFormatters.swift` / `ByteFormatting.swift` / `StringFormatting.swift` (shared date, byte, and string-truncation formatting), `ThreadSafeStorage.swift` (`Atomic<Value>`, the `nonisolated @unchecked Sendable` + `NSLock` box used by actor→sync bridge seams like `DiscordRPCService.stateSnapshot` and the Twitch dispatcher flags). Also in Core/: `AppContainer.swift` (Application Support / temp directory resolution), `AppearanceController.swift` (app-wide `NSApp.appearance` override), `KeychainBackend.swift` (test-injectable storage behind `KeychainService`), `DiagnosticsService.swift` (opt-in MetricKit diagnostics + share card), `MetricsService.swift`, `MenuStatusFormatter.swift`, `ExternalLink.swift`, `Pasteboard.swift`, `ImageEncoding.swift`, `InlineMarkdown.swift`, `NotificationPayloads.swift`, `RecentTrack.swift`, `SponsorConfig.generated.swift`, `CrashReporter.swift` (process-wide last-gasp crash handlers; the marker now carries kind/signal/pid/version/build/epoch, pre-baked at install so the signal path stays async-signal-safe), `CrashMarker.swift` (parses that marker, plus the legacy shapes; read at launch and written into the log BEFORE the marker is cleared), `DiagnosticSnapshot.swift` (one environment block for the bug report, the export header, and the Debug card. NOT `#if DEBUG` on purpose), `DiagnosticsBundle.swift` (composes the export: environment + crash + every rotated log, oldest first), `MusicProcess.swift` (resolves the running Music.app by pid so ScriptingBridge never relaunches a quit Music; see PR #392), `UITestMode.swift` (the out-of-process test seam: `isUnderTestHarness` is what `DefaultsStore` and `KeychainService` branch on, so a UI test gets throwaway storage the same way the hosted unit bundle does), and the `Core/ListeningHistory/` subdir (`PlayLogStore`, `PlayRecord`, `LifetimeTally`, `DurationSanitizer` (clamps implausible track durations), `HistoryStoreSupport` (shared store filesystem + day-bucketing helpers)).
- **Monitors/** - Apple Music playback monitoring. `AppleMusicSource.swift` uses PID-targeted ScriptingBridge with a retained error delegate, distributed notifications, monotonic event deduplication, and 5s fallback polling throttled slower in low-power mode, and reports updates through `PlaybackSourceDelegate.swift`.
- **Services/Twitch/** - `TwitchChatService.swift` (actor-isolated EventSub WebSocket + Helix chat API, network path monitoring for reconnection, Twitch user ID redacted in logs; also dispatches `channel.channel_points_custom_reward_redemption.add` and qualifying `channel.bits.use` cheer events into the song-request pipeline), `TwitchChannelPointsService.swift` (Helix create / reconcile / fulfill / cancel for the WolfWave-managed "Request a Song" reward), `TwitchRedemptionResolutionOutbox.swift` (atomic disk-backed paid-event state: channel-point intake becomes a known fulfill/refund before Helix delivery, unknown startup intake refunds conservatively, and complete Bits boost/request actions replay until atomically acknowledged), `HelixClient.swift` (shared Helix API wrapper over `HTTPClient`: auth headers, body encode, status validation, Helix error mapping; used by `TwitchChatService` and `TwitchChannelPointsService`), `TwitchDeviceAuth.swift` (OAuth Device Code flow). The chat-service actor is split across same-actor seam files: `TwitchChatService+Auth.swift`, `TwitchChatService+Connection.swift`, `TwitchChatService+EventSub.swift`, `TwitchChatService+Redemptions.swift`.
- **Services/Twitch/Commands/** - `BotCommand` protocol (`triggers`, `description`, `execute(message:) -> String?`), `AsyncBotCommand` for I/O-bound commands, `BotCommandContext`, `BotCommandDispatcher`. Concrete commands: `TrackInfoCommand` (drives `!song`, `!last`, and `!stats` via three configured instances), `InfoCommand` (`!wolfwave`, static reply styled by `WolfWaveReplyStyle`), `SongRequestCommand`, `QueueCommand`, `MyQueueCommand`, `SkipCommand`, `HoldCommand`, `ClearQueueCommand`, `VoteSkipCommand` (chat vote-to-skip), `SongListCommand` (`!playlist`). Streamer-authored commands run through `CustomBotCommand` (an `AsyncBotCommand` rebuilt per message from `CustomCommandStore`), backed by the `CustomCommand` model and the `CustomCommandRenderer` enum, which does variable substitution (`$user`/`$sender`, `$touser`, `$args`, `$1`–`$9`, `$song`, `$lastsong`) and `CommandPermission` gating (everyone/subscriber/vip/moderator/broadcaster). Each `CustomCommand` also carries a `ReplyDelivery` (reply / message / announce, decoded as `.reply` when absent from older storage); the dispatcher returns it in `CommandReply` and `TwitchChatService+EventSub` routes announce through `sendAnnouncement` (Helix `/chat/announcements`, never the `sendMessageOnce` 401→reauth path) with a reply fallback and an `AnnounceStatus` banner key. `StatsCommandFormat` supplies the `!stats` window formatting. `CooldownManager` enforces global + per-user cooldowns.
- **Services/SongRequest/** - `SongRequestService.swift` (request flow orchestrator; `processRequest(query:username:source:)` takes a `RequestSource` so chat commands, channel-point redemptions, and bit cheers share the same pipeline; opt-in approval screening (`isApprovalRequired`, `approve`/`decline`) holds every request in a pending state until the broadcaster acts), `SongRequestAccess.swift` (`RequestAudience` chat-command gate, `RequestSource`, `SongRequestPreset` one-tap configurations, `RedemptionStatus` for the settings re-auth banner, `SongRequestPriorityMode` + `SongRequestPriority` for the Sub/VIP perk), `SongRequestQueue.swift` (fair-share round-robin ordering with Sub/VIP priority applied within rounds, hold mode, Music.app-closed buffering, and a `boost(username:)` method for bit-cheer boosts), `SkipVoteManager.swift` (chat vote-to-skip sessions: chat tally or Twitch Polls), `SongSearchResolver.swift` + `LinkResolverService.swift` (MusicKit search / Apple Music link resolve), `AppleMusicController.swift` (main-thread NSAppleScript playback with structured failures, PID-addressed events, exact request matching, and guarded focus restoration), `AppleMusicLibraryService.swift` (MusicKit library add + WolfWave Requests playlist probe), `SongBlocklist.swift`.
- **Services/SettingsBackup/** - `SettingsBackup.swift` (payload model), `SettingsBackupCoder.swift` (pure encode/decode), `SettingsBackupService.swift` (`@MainActor` export/import orchestration). Credentials and resolved account IDs are excluded; the public Twitch channel name is the sole integration metadata. See `apps/docs/content/docs/backup.mdx`.
- **Services/Discord/** - `DiscordRPCService.swift` (Discord Rich Presence via local IPC Unix domain socket, auto-reconnect with backoff), split into `DiscordRPCService+IPC.swift` (socket framing / connect) and `DiscordPresenceBuilder.swift` (pure presence-payload construction).
- **Services/UpdateChecker/** - `SparkleUpdaterService.swift` (Sparkle framework wrapper for auto-updates, EdDSA-signed appcast verification, Homebrew install detection disables Sparkle, DEBUG mode allows manual check via bundled `dev-appcast.xml`), `UpdateChannel.swift` (`nonisolated` Stable/Nightly enum backing the dual-feed picker).
- **Services/WebSocket/** - `WebSocketServerService.swift` (overlay broadcast plus role-separated authentication: read-only `wolfwave.overlay.<hex>` clients may connect from loopback or LAN, while command-capable `wolfwave.control.<hex>` clients are accepted only from literal loopback; parses Stream Deck control commands via an injected `onCommand` handler and pushes `queue_state` / `health` broadcasts; progress work exists only while enabled, overlay-visible, playing, and serving clients, and each fan-out encodes once), `StreamDeckCommand.swift` (pure `StreamDeckAction` / `StreamDeckCommand` / `CommandAck` + `StreamDeckControl.parse` protocol-v2 envelope decoder, see `apps/native/docs/streamdeck-control-api.md`; `overlay_toggle` changes card visibility without stopping the authenticated transport), `WidgetHTTPService.swift` (static widget HTTP server; injects only the overlay token for literal loopback Host requests, returns those responses with `no-store`, and enforces `no-referrer` for every widget document; generated widget tokens are already build-inlined), `WebSocketAuthToken.swift` (separate per-install overlay/control token generation, persistence-first Keychain rotation, constant-time role matching, and literal-loopback classification).
- **Services/ListeningHistory/** - `ListeningHistoryService.swift` (opt-in, on-device append-only NDJSON play log; records a track only after it crosses the half-length or 4-minute mark so skips don't count), `StatsAggregator.swift` (top artists / listening time / 7-day trend / listening-by-hour rollups powering History & Stats), `MonthlyWrap.swift` (per-month "wrapped"-style summary + share-card export), `HistoryFormatting.swift` (date/duration formatting helpers).
- **Services/Notifications/** - `NotificationService.swift` (opt-in macOS banners via `UNUserNotificationCenter`; song-change, skip-vote-started, and skip-vote-passed each reuse a stable per-type identifier so a new banner replaces the previous one of its kind instead of stacking. Skip-vote-started is silent; skip-vote-passed uses the default system sound. Static `make…Content` builders keep the text pure and unit-testable. Skip-vote events arrive via `SkipVoteManager.onVoteEvent`, gated in `AppDelegate.handleVoteEvent` on both `voteSkipEnabled` and the matching per-event toggle. The service is also the `UNUserNotificationCenterDelegate` (installed at launch) so banners still present while WolfWave is frontmost, and it owns the Twitch re-auth banner via `postTwitchReauthNeeded()`, which only posts when authorization is already granted - boot paths must never trigger the system permission prompt).
- **Services/** - `ArtworkService.swift` (iTunes Search artwork fetch + cache), `ArtworkTint.swift` (album-art representative-color sampler for the Monthly Wrap share card), `LaunchAtLoginService.swift`. (`DiagnosticsService.swift` now lives in Core/.)
- **Views/** - SwiftUI settings shell `SettingsView.swift` with `NavigationSplitView` sidebar. Per-section views decomposed into `GeneralSettingsView.swift`, `MusicMonitor/MusicMonitorSettingsView.swift`, `AppVisibility/AppVisibilitySettingsView.swift`, `WebSocket/WebSocketSettingsView.swift` (Stream Widgets: connection, browser source, appearance, then the raw feed) + `WebSocket/WebSocketCustomOverlayCard.swift` (port, overlay token, and the two WebSocket addresses) + `WebSocket/WebSocketTokenEditorRow.swift` (the one credential editor both panes render, so overlay and control validation cannot drift), `StreamDeck/StreamDeckSettingsView.swift` (Stream Deck: the `streamDeckControlEnabled` capability switch, the control token, setup steps) + `StreamDeck/StreamDeckPaneStatus.swift` (the pure `nonisolated` header-chip resolver; the shared server outranks the command switch, because commands on a stopped server produce a key that silently does nothing), `Twitch/TwitchSettingsView.swift`, `Discord/DiscordSettingsView.swift`, `SongRequest/SongRequestSettingsView.swift` + `SongRequestQueueView.swift`, `Notifications/NotificationsSettingsView.swift`, `HistoryStats/HistoryStatsSettingsView.swift` + `StatsChartsView.swift` + `MonthlyWrapView.swift` (SwiftUI Charts powered, gated on the opt-in Listening History setting), `Appearance/AppearanceSettingsView.swift`, `SoftwareUpdate/SoftwareUpdateSettingsView.swift`, `About/AboutSettingsView.swift` + `AboutCopy.swift` (pure copy strings incl. the displayed copyright year), `Advanced/AdvancedSettingsView.swift` + `SettingsImportSheet.swift` + `DiagnosticsShareCardView.swift`. The shell itself is split into `SettingsSidebarView.swift` (sidebar) and `SettingsSceneBridge.swift` (AppKit window plumbing). Per-pane supporting views: `Discord/DiscordPreviewCard.swift` + `DiscordButtonConfigRow.swift`, `MusicMonitor/MusicPermissionState.swift` + `PermissionDeniedView.swift`, `Twitch/TwitchCommandsCard.swift` + `CustomCommandsCard.swift` + `DeviceCodeView.swift`, `WebSocket/WidgetAppearancePreview.swift`, and `SongRequest/Setup/SongRequestSetupView.swift` + `SongRequestSetupViewModel.swift` (the guided setup gate). `TwitchViewModel` is the main observable for auth/connection state.
- **Views/Onboarding/** - macOS 26 Liquid Glass onboarding wizard. The `OnboardingStep` enum (in `OnboardingViewModel.swift`) defines the step order: Welcome → Discord → Twitch → OBS Widget (overlay URL + HTTP widget toggle) → Preferences → Permissions (Apple Music automation only) → Notifications (notification authorization + the song-change / skip-vote alert toggles) → Menu Bar Pointer, followed by `OnboardingCompletionView`. Permissions and Notifications are deliberately two separate screens so each has a single job. One file per step: `OnboardingWelcomeStepView`, `OnboardingDiscordStepView`, `OnboardingTwitchStepView`, `OnboardingOBSWidgetStepView`, `OnboardingPreferencesStepView`, `OnboardingPermissionsStepView`, `OnboardingNotificationsStepView`, `OnboardingMenuBarPointerStepView`, all hosted by the `OnboardingView.swift` wizard container. Components in `Onboarding/Components/` (`PillButton`, `BrandTile`, `OnboardingStepScaffold`, `OnboardingToggleCard`, `WolfHeroMark`).
- **Views/Debug/** - **DEBUG-only** developer tooling tab. `DebugSettingsView.swift` shell plus cards: `DebugInspectorsCard`, `DebugLogViewerCard` (live tail of the log file: level/category filters, search, follow toggle, backed by `Core/LogTailCursor.swift` for incremental reads and `Core/LogRecord.swift` for parsing), `DebugLogsAndEventsCard`, `DebugMetricsCard`, `DebugServiceControlsCard`, `DebugUIPreviewsCard`, over the `DebugDiagnostics.swift` snapshot helpers (Connections vs Preferences are separate tables on purpose: a preference being on is not evidence a service connected). Rail layout lives in `DebugSection.railGroups` and is coverage-checked by `DebugSectionCoverageTests`. Not compiled into release builds.
- **Views/Shared/** - Shared UI components: `StatusChip`, `InfoRow`, `ToggleSettingRow`, `SuccessFeedbackRow`, `SectionHeaderWithStatus`, `CardEyebrowHeader`, `NowPlayingHeroCard`, `AlbumArtView`, `IntegrationDashboardView`, `CalloutBanner` (consolidated info/success/warning/error/neutral tinted callout that replaced the old `WarningBanner` / `ConfigRequiredBanner` / `ConnectionTestButton` variants), `Binding+Sanitized` (`snapped(to:fallback:)` / `clamped(to:fallback:)`; wrap any `@AppStorage`-backed `Picker` selection or `Slider` value with these, because a persisted value outside the control's tags or bounds traps inside SwiftUI and takes the settings window down), `CopyButton`, `CopyableURLRow`, `OpenInBrowserButton`, `SharePickerButton`, `DestructiveButton`, `DSIconButton`, `AsyncActionButton` (one button owning one `async` action: spinner replaces the label, control disabled while in flight, brief success checkmark, width pinned by `stableWidth` so no phase change resizes the row. Not for a button that fire-and-forgets a `Task`, and not usable inside `.alert` / `.confirmationDialog`, which only accept plain `Button`s), `UpdateBannerView`, `WhatsNewView`, `ActionGrid`, `LoadingRow`, `HintRow`, `MusicPermissionBanner`, `StatTile`, `LabeledSlider`, `CooldownSliderPair`, `CommandAliasField`, `CommandSettingRow`, `ResponsiveRow`, `QRCodeImage`, `StreamerModeBadge`, `TwitchConnectionNotice`, `TwitchGlitchShape`, `ViewModifiers`, `SettingsNavRail` (shared two-column jump-nav rail + scroll-sync used by General, Debug, Song Requests, and History & Stats; sections conform `SettingsRailSection` and tag their top view with `.railSection(_:)`; panes that use it bypass `standardDetailScroll` in `SettingsView.detailPane` to own the full pane width). Sensitive fields wrap their value in a `StreamerMode.shared` check before rendering; when Streamer Mode is on, the value is replaced with a `••••••` mask and Copy/Open buttons are disabled.

### Key patterns

- **Credentials**: All tokens/secrets stored via `KeychainService` (never UserDefaults). Twitch access, refresh, username, user ID, and configured channel are one revisioned atomic grant; never split an account transition back into per-field writes. A channel restored from backup may exist in UserDefaults only as a pending, nonauthoritative hint until OAuth commits it with the account. Keys defined in `AppConstants.Keychain`.
- **Settings**: User preferences in `UserDefaults` via `@AppStorage`. Keys centralized in `AppConstants.UserDefaults`. Note: `currentSongCommandEnabled`, `lastSongCommandEnabled`, and `widgetHTTPEnabled` all default to `false`. `streamDeckControlEnabled` is the one security-relevant capability that defaults to **`true`**, and must keep doing so: the capability shipped already gated by the control token, so defaulting it off would disarm every Stream Deck in the field on the first launch after an update. Read it through `FeatureFlags.streamDeckControlEnabled` (which passes the explicit default), never `defaults.bool`, which reports `false` for "never set".
- **Notifications**: Loose coupling via `NotificationCenter` (e.g., `TrackingSettingChanged`, `DockVisibilityChanged`). Names in `AppConstants.Notifications`.
- **Thread safety**: `TwitchChatService` uses actor isolation; its synchronous observation bridges use small lock-backed snapshots. `DiscordRPCService` uses `ipcQueue` serial queue confinement plus `enabledLock` for thread safety. Logger uses a serial `DispatchQueue` for thread-safe file I/O.
- **Bot commands**: Register new commands in `BotCommandDispatcher.registerDefaultCommands()`. Each command implements `BotCommand` protocol. Max response 500 chars, target <100ms execution.
- **Discord IPC**: Unix domain socket at `$TMPDIR/discord-ipc-{0..9}`. SBPL entitlements enable socket access within App Sandbox.
- **ADHD-friendly text**: All user-facing text should be short, punchy, and jargon-free.

## Design System

Single source of truth: [`design-system/tokens.json`](design-system/tokens.json). The generator [`design-system/scripts/generate.ts`](design-system/scripts/generate.ts) emits five platform outputs; **do not edit generated files by hand**:

| Output | Path | Consumer |
|---|---|---|
| Swift | `apps/native/WolfWave/Core/DesignSystem/Tokens.generated.swift` | Native app: `DSColor`, `DSFont`, `DSSpace`, `DSRadius`, `DSMotion`, `DSDimension` |
| CSS | `apps/docs/app/tokens.generated.css` | Fumadocs site (`--ds-*` custom properties) |
| Widget JS | `apps/native/WolfWave/Resources/widget-tokens.generated.js` | `apps/widget/build.ts` inlines `window.WW_TOKENS` into the shipped `widget.html` |
| Marketing TS | `apps/marketing/shared/tokens.generated.ts` | Remotion projects |
| Docs widget themes TS | `apps/docs/app/(home)/_widgets/widget-themes.generated.ts` | `USER_THEMES`, `WIDGET_THEMES`, `WIDGET_LAYOUTS`, `DEFAULT_THEME`, `DEFAULT_LAYOUT` for the landing-page OBS overlay preview |

### Regenerating

```bash
bun run tokens          # Direct
bun turbo tokens        # Via Turbo (cached when inputs unchanged)
bun turbo build         # `tokens` is a build prerequisite; runs automatically
```

`turbo.json` declares two root tasks:

| Root task | Script | Inputs |
|---|---|---|
| `//#tokens` | `bun run tokens` | `design-system/tokens.json`, `design-system/scripts/generate.ts`. Outputs the five generated files above. |
| `//#ds:lint` | `bun run ds:lint` | `apps/native/WolfWave/Views/**/*.swift`, `design-system/scripts/lint.ts`, `design-system/lint-allowlist.txt` |

`lint.ts` exports `RULES` and guards its own execution behind `import.meta.main`, so `lint.test.ts` can import the patterns without the import linting the tree and calling `process.exit`. A lint rule that silently stops matching is indistinguishable from a clean tree, which is what that suite exists to catch.

Both `build` and `dev` `dependsOn` `//#tokens`, so it runs automatically. `//#ds:lint` is
invoked on its own (locally, and as the `ds-lint` CI job).

### Widget themes (`window.WW_TOKENS`)

`widget.html` consumes build-inlined `WW_TOKENS.themes`: five selectable themes (`Default`, `Dark`, `Light`, `Glass`, `Neon`) plus the hidden internal `WolfWave` theme. `WW_TOKENS.layouts` contains five layouts (`Horizontal`, `Vertical`, `Compact`, `Vinyl`, `Classic`). Themes and layouts live in `tokens.json` under `widget`; add or edit them there, regenerate, then rebuild the widget. `WidgetHTTPService` may serve `/widget-tokens.generated.js` as a fallback asset route, but the shipped self-contained HTML does not fetch it at runtime.

### Component catalog

[`design-system/components/`](design-system/components/) - one markdown entry per reusable view, indexed by [`design-system/components/README.md`](design-system/components/README.md). The catalog covers three source directories, not just one: `Views/Shared/`, `Views/Onboarding/Components/`, and `Views/HistoryStats/`. Every entry follows the same template (Purpose, API, Tokens used, Anatomy mermaid, Accessibility, Do/Don't, Example); see [`status-chip.md`](design-system/components/status-chip.md) as the quality bar.

**When you touch any of these views, update the matching catalog entry in the same change.** That keeps token usage docs and anatomy diagrams from drifting.

### Design-system discipline

These rules are enforced by [`design-system/scripts/lint.ts`](design-system/scripts/lint.ts) (`bun run ds:lint`, also run in CI):

- **Never** use literal numbers in `font(.system(size:))`; use `DSFont.Size.*` (`xs=10`, `sm=11`, `body=12`, `base=13`, `md=14`, `lg=17`, `xl=20`, `x2xl=22`, `x3xl=26`). Heading ramp: `.paneTitle()` (22 bold, H1) → `.sectionHeader()` (17 semibold, H2) → `.sectionEyebrow()` (11 semibold secondary, H3); body via `.fieldSubtitle()` (13) / `.captionText()` (10). The old `.sectionSubHeader()` (15) was retired 2026-06-05 because it collided with the 17pt pane title; `x3xl` (26) is reserved for hero + the Monthly Wrap share card.
- **Never** use literal numbers in `spacing:` or `.padding(N)`; use `DSSpace.*` (`s0=2`, `s1=4`, `s2=8`, `s3=10`, `s4=12`, `s5=14`, `s6=16`, `s7=20`, `s8=24`, `s9=28`, `s10=32`, `s11=44`). `DSSpace` is a *spacing* scale: for a `.frame(width:)` reach for `DSDimension.*` instead.
- **Never** pass a raw system color as a `StatusChip` / `SectionHeaderWithStatus` state tint. Use `DSColor.success` / `.warning` / `.error` / `.info` / `.neutral`; the state-to-token table is in [`status-chip.md`](design-system/components/status-chip.md). `DSColor.neutral` is the off / disconnected state, and exists because `Color.secondary` is translucent, so the chip's own 10% background wash landed near-invisible beside opaque siblings. Enforced by the `raw-status-color` lint rule, which is scoped to the `color:` / `statusColor:` argument labels (so `.foregroundStyle(.secondary)` on body text is untouched) and reaches across a ternary. Its one blind spot, pinned by a test: a bare `return .gray` carries no argument label, so a line-based rule cannot see it. Two deliberate exceptions are outside the banned set and carry a comment: `.accentColor` for Software Update's "update available" (follows the system accent) and `Color.white.opacity(0.35)` for the Discord preview off dot (fixed brand surface, where neutral reads 1.9:1).
- For single-glyph bordered buttons, use [`DSIconButton`](apps/native/WolfWave/Views/Shared/DSIconButton.swift); do **not** hand-roll `Button { Image(...) } .buttonStyle(.bordered) .controlSize(.small)`. Hand-rolled icon-only buttons collapse to a narrower frame than text-label neighbors like `CopyButton`, causing visible drift.
- When you touch a component under `Views/Shared/`, `Views/Onboarding/Components/`, or `Views/HistoryStats/`, update its catalog entry in [`design-system/components/`](design-system/components/) in the same change.

Existing legacy literals are tracked in [`design-system/lint-allowlist.txt`](design-system/lint-allowlist.txt); migrate them file-by-file in follow-up PRs. Do **not** add new entries.

## Testing

Unit tests live in `apps/native/WolfWaveTests/` and use XCTest + Swift Testing with `@testable import WolfWave`. The test target is a hosted unit test bundle (`TEST_HOST` = `WolfWave Dev.app` for Debug and `WolfWave.app` for Release). Run `ls apps/native/WolfWaveTests/*.swift | wc -l` for the current file count.

> Auto-discovery: `apps/native/WolfWaveTests/` is a `PBXFileSystemSynchronizedRootGroup`; dropping a new `*.swift` file in is enough, no Xcode project edit required.

Test taxonomy is boundary-based:

- **Unit/service tests** exercise in-process logic, models, view models, and injected collaborators.
- **Integration tests** cross a real subsystem or transport boundary and assert an observable result. Loopback HTTP/WebSocket tests belong here.
- **End-to-end/UI tests** launch and drive the app as a user would. These live in `apps/native/WolfWaveUITests/` (target + scheme `WolfWaveUITests`, run with `make test-ui`), never in the hosted unit bundle. Hardware-, account-, and live-service journeys remain explicit manual release checks; `apps/native/docs/end-to-end-testing.md` is the current list of what is automated and what still needs hands.

### XCUITests (`apps/native/WolfWaveUITests/`)

A UI test runs the app in its **own process**, so `WolfWaveApp.isRunningTests` is false there and every isolation seam keyed on it would resolve to the live one. `Core/UITestMode.swift` is what closes that: the test bundle sets `WOLFWAVE_UI_TEST=1` on `launchEnvironment`, and the app then routes `DefaultsStore.store` and `KeychainService.backend` to throwaway storage and leaves `AppleMusicSource`, `TwitchChatService`, `DiscordRPCService`, and Sparkle down. **Never launch the app from a UI test without that flag** — it would edit the developer's real `com.mrdemonwolf.wolfwave.dev` domain and real Keychain, and the Music probe would park a TCC dialog over the runner.

- `WOLFWAVE_UI_TEST_ONBOARDED=1` starts past the wizard; `WOLFWAVE_UI_TEST_NO_WHATS_NEW=1` suppresses the What's New window. Both are declared in `UITestMode` and mirrored in `UITestEnvironment` in the test bundle (a UI test target cannot import the app). Change one side, change the other.
- Subclass `WolfWaveUITestCase` and declare state through `launchOptions`. Its `setUp` calls `app.activate()`, which is load-bearing: an inactive macOS app reports its whole window tree as disabled, so elements are findable but nothing is `isHittable` and clicks silently do nothing.
- Query by accessibility identifier, never visible label (panes repeat their section name, so a label matches the sidebar row and the content both). Sidebar rows are `settings.sidebar.<title>`; wizard buttons are `onboarding.<button>`. Check the element **type** against the real tree first — a sidebar `Label` maps to a `staticText`, not a button.
- `make test-ui` uses `UI_SIGN`, not `LOCAL_SIGN`: XCUITest attaches to the launched product, and a wholly unsigned app cannot be attached to, so the no-identity fallback is ad-hoc signing rather than `CODE_SIGNING_ALLOWED=NO`.
- The suite is **not** in `make test-ci`. Release and nightly stay unit-only so a UI run never gates a release.

### Test files

- `SparkleUpdaterServiceTests.swift` - Sparkle feed resolution, manual-check availability, and Homebrew gating
- `TrackInfoCommandTests.swift` - `TrackInfoCommand` covering both `!song`/`!currentsong`/`!nowplaying` and `!last`/`!lastsong`/`!prevsong` trigger sets via shared fixtures (trigger matching, case insensitivity, enable/disable, callback, default message, 500-char truncation)
- `BotCommandDispatcherTests.swift` - Message routing, callback wiring, length guards, whitespace handling
- `CooldownManagerTests.swift` - Global + per-user cooldown enforcement
- `SongRequestServiceTests.swift`, `SongRequestQueueTests.swift`, `SongRequestCommandTests.swift`, `HoldCommandTests.swift`, `SongBlocklistTests.swift` - Song Request system (queue, hold mode, request command parse, blocklist)
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
- `WebSocketServerAuthTests.swift` - role-prefixed overlay/control handshakes, credential separation, selected-subprotocol revalidation, and loopback-only command authorization
- `TwitchEventSubDedupTests.swift` - EventSub `message_id` dedup (at-least-once delivery: TTL expiry, cap eviction, no timestamp refresh on dup)
- `TwitchConnectionStateHubTests.swift` - per-subscriber connection-state streams (multi-subscriber fan-out, single-subscriber termination, finish-all)
- `PreferencesResolvedPortTests.swift` - clamped widget/WebSocket port resolution (0 falls back to default, out-of-range clamps instead of trapping)
- `AppleMusicControllerTests.swift` - PID-targeted AppleScript dispatch, structured errors, sanitization, timeout budgets, and guarded focus preservation
- `LinkResolverServiceTests.swift`, `SongSearchResolverTests.swift` - MusicKit search + Apple Music link resolve
- `MenuStatusFormatterTests.swift`, `OnboardingCompletionViewTests.swift`, `ActionGridTests.swift`, `LoadingRowTests.swift`, `CalloutBannerTests.swift` - Shared view + onboarding state coverage
- `HTTPClientTests.swift`, `TwitchDeviceAuthNetworkTests.swift`, `AppConstantsConfigOverrideTests.swift` - Foundation utilities + config plumbing
- `ArtworkServiceNetworkTests.swift` - Stubbed iTunes request parsing, retry policy, cache keys, persistence, and eviction
- `AppleMusicSourceTests.swift` - Playback source lifecycle, ScriptingBridge error delegate/status mapping, monotonic timing, and player-state parsing
- `OnboardingViewModelTests.swift` + `OnboardingViewModelEdgeCaseTests.swift` - Step navigation, boundary conditions, UserDefaults persistence
- `TwitchViewModelTests.swift`, `TwitchChatServiceTests.swift`, `TwitchDeviceAuthTests.swift`, `TwitchDeviceAuthErrorTests.swift` - Twitch auth + EventSub + view model state
- `DiscordRPCServiceTests.swift` - IPC framing, reconnect backoff
- `DiscordPresenceBuilderTests.swift` - Rich Presence payload construction (state/details, buttons, timestamps)
- `WebSocketServerServiceTests.swift`, `WebSocketServerIntegrationTests.swift`, `WidgetHTTPServiceTests.swift` - Overlay broadcast + widget HTTP
- `StreamDeckCommandTests.swift` - Stream Deck control-command envelope parse (type/protocol/action gating, args, ack JSON shape)
- `StreamDeckPaneStatusTests.swift` - Stream Deck header-chip precedence (server-off outranks commands-off) and distinct glyph per state
- `StreamDeckControlIntegrationTests.swift` - The same command across a real loopback WebSocket: a control client's frame reaches the injected handler and is acked on the originating connection, an overlay client's identical frame is refused `unauthorized` and never reaches the handler, and a stale protocol version is rejected without running. Covers the seam the parse suite and the auth suite each leave to the other.
- `KeychainServiceTests.swift` - Atomic Twitch grant migration and failure prefixes, save/load/delete, Unicode, and concurrent access
- `DefaultsStoreTests.swift` - Pins the `UserDefaults` isolation seam: a test host resolves to the dedicated suite, and a write through it never reaches the live app domain
- `PreferencesResolvedDomainTests.swift` - Domain-resolved reads (`resolvedInt` / `resolvedDouble`) and the sanitized `Binding` helpers against NaN, infinity, negatives, values past `Int.max`, and values outside a picker's tag set
- `LoggerTests.swift`, `PowerStateMonitorTests.swift` - Core utilities (logging incl. log clearing, power state). Log-clear tests are direct members of the `.serialized` "Logger Tests" suite so the truncating `clearLogFile()` can't race the file-readback tests.
- `BugReportURLTests.swift` - Pre-filled GitHub issue URL construction and encoding
- `BundleInstallMethodTests.swift` - DMG vs Homebrew (cask) install detection
- `AppConstantsTests.swift` + `AppConstantsEdgeCaseTests.swift` - Constant values, URL validity, dimension bounds, cross-references
- `AppContainerTests.swift` - Application Support path composition and container wipe
- `CrashReporterTests.swift` - Crash-marker lifecycle (never raises a real signal or `NSException`; that would kill the xctest host)
- `SettingsBackupCoderTests.swift`, `SettingsBackupServiceTests.swift`, `SettingsBackupKeyCoverageTests.swift` - Backup encode/decode, export/import orchestration, and the exportable / account-linked / runtime-state key classification
- `CustomCommandTests.swift`, `InfoCommandTests.swift`, `WolfWaveReplyStyleTests.swift` - Custom bot commands (variable substitution, permission gating), the `!wolfwave` info command, and reply styling
- `QueueCommandTests.swift`, `MyQueueCommandTests.swift`, `ClearQueueCommandTests.swift`, `SkipCommandTests.swift`, `SongListCommandTests.swift` - Remaining song-request chat commands
- `SongRequestQueuePendingTests.swift`, `SongRequestPriorityTests.swift` - Approval-screening pending state and the Sub/VIP priority perk
- `SongRequestSetupHealthTests.swift`, `SongRequestSetupViewModelTests.swift`, `PlaylistSetupStatusTests.swift`, `AppleMusicLibraryServiceTests.swift`, `MusicPermissionCheckerTests.swift` - Song Requests setup gate, playlist health check, and MusicKit library access
- `TwitchEventSubLifecycleTests.swift`, `TwitchTokenRefreshTests.swift`, `TwitchTokenLifecycleTests.swift`, `TwitchTokenValidationLifecycleTests.swift`, `TwitchRateLimiterTests.swift`, `HelixClientTests.swift`, `MapHelixErrorTests.swift` - EventSub lifecycle, token refresh/validation ownership, rate limiting, and the shared Helix wrapper
- `TwitchRedemptionResolutionOutboxTests.swift` - Durable channel-point outcomes and Bits action replay, corruption recovery, and duplicate tombstones
- `BotCommandGlobalGateTests.swift`, `TrackInfoCommandAliasTests.swift`, `StatsCommandFormatTests.swift`, `StatsWindowSummaryTests.swift` - Dispatcher gating, alias handling, and `!stats` formatting
- `UpdateChannelTests.swift` - Stable / Nightly channel resolution for the Sparkle dual feed
- `DiscordIdlePresenceTests.swift` - Idle Rich Presence payload
- `MonthlyWrapExportTests.swift`, `ArtworkTintTests.swift` - Monthly Wrap share-card export and album-art tint sampling
- `StreamerModeMaskingSweepTests.swift` - Sweeps every sensitive field for Streamer Mode masking
- `AtomicTests.swift`, `ByteFormattingTests.swift`, `InlineMarkdownTests.swift`, `FeatureFlagsDefaultsTests.swift`, `JSONSerializationGuardTests.swift` - Core utility coverage
- `HintRowTests.swift`, `LabeledSliderTests.swift`, `StatTileTests.swift`, `DestructiveButtonTests.swift`, `AsyncActionButtonTests.swift`, `SectionEyebrowTests.swift`, `NowPlayingHeroCardTests.swift`, `TwitchConnectionNoticeTests.swift`, `WidgetAppearancePreviewTests.swift` - Shared view components

### Writing tests

- Use `@testable import WolfWave` (module name matches `PRODUCT_NAME`)
- Test hosts default to `InMemoryKeychainBackend`; never replace it with `SystemKeychainBackend` or access the user's real Keychain
- **Swift Testing runs separate suites in parallel.** `.serialized` only orders tests *within* one suite, and those suites also overlap XCTest in the same process, so anything reached through a process-wide global is shared with whatever else is running. Three globals matter here: `KeychainService.backend`, `Preferences.twitchReauthNeeded`, and every key in `DefaultsStore.store`. One lock covers all three — `SharedTestStateIsolation` — deliberately, because a second lock is a deadlock waiting for the first suite that wants both. Take it one of three ways:

  | Suite kind | How it takes the lock |
  |---|---|
  | XCTest | subclass `WolfWaveTestCase` (its `setUp` acquires; a teardown block always releases) |
  | Swift Testing | the `.isolatedSharedTestState` suite trait |
  | one block | `SharedTestStateIsolation.withIsolatedSharedState { }` |

  Scopes are re-entrant (a `@TaskLocal` marks the holding task tree), so a suite trait plus an inner explicit block is safe. **Subclassing `WolfWaveTestCase` is not optional for an XCTest suite that touches those globals** — that is the only thing putting it under the lock. A `@MainActor` suite must acquire with `acquireAsync()` from `setUp() async throws`; a blocking `acquire()` on the main thread deadlocks whenever the current holder is a `@MainActor` test suspended mid-`await`. Guarding only the suites that *write* is not enough: an ordinary reader racing a write was itself the flake. `SongRequestServiceTests` set `songRequestEnabled = true` in `setUp()` and asserted several `await`s later while `TwitchChatServiceTests` and the setup-gate suites wrote the same key, which surfaced as `testRequestWhileMusicAppClosedBuffers` intermittently failing with `featureDisabled` and passing every time in isolation.
- A suite that installs its own Keychain backend also binds `KeychainService.backendBox` (a `@TaskLocal`) via the `.isolatedKeychainBackend` trait, which makes that backend unreachable from any other task tree; `KeychainServiceTests` uses it, and two tests in that suite pin the property so the trait cannot silently stop binding. **A `@TaskLocal` does not reach code that leaves the task tree** — a test that drives `KeychainService` from a `DispatchQueue` block or a `Task.detached` sees the process-wide backend instead, and must rebind with `KeychainService.$backendBox.withValue(box) { }` inside the block (this works off-task; `testConcurrentAccess` does it). The same limit is why the XCTest lock path uses a plain `acquire`/`release` pair rather than the task-local: XCTest runs `setUp` and the test body in different tasks.
- **Never touch `UserDefaults.standard` in a test.** The test bundle is hosted, so `.standard` inside a test process is literally the dev app's live preference domain (`com.mrdemonwolf.wolfwave.dev`). Tests writing there edited the developer's real settings; one such write (`voteSkipWindowSeconds = 1`, not a valid picker tag) crashed the Song Requests pane inside SwiftUI on the next launch. Read and write `DefaultsStore.store` (production routes through the same seam, so a test write is visible to the code under test), or hand a SUT a throwaway `UserDefaults(suiteName:)`. Enforced by `DefaultsStoreTests` and the blocking `user_defaults_standard` SwiftLint rule. Note the seam is one suite per *process*, not per test: it stops tests corrupting the dev app, not tests corrupting each other. That is the lock's job.
- `@AppStorage` is deliberately **not** routed through `DefaultsStore`, so do not drive `@AppStorage` bindings from a hosted unit test: those writes would land on the live domain
- `WolfWaveTests` uses `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`; annotate UI-facing tests or helpers with `@MainActor` explicitly
- Test files are auto-discovered via `PBXFileSystemSynchronizedRootGroup`; just add `.swift` files to `apps/native/WolfWaveTests/`
- Prefer pure logic (version comparison, command matching, state machines). Network integration tests must own a loopback endpoint, await observable readiness, and use bounded timeouts; never depend on a public service.

## CI/CD

### Shared CI plumbing (change it here, not per workflow)

CI, Release, and Nightly used to carry their own copy of the build preamble and
the signing block. They now share one composite action and a set of scripts, so
a fix lands once and every workflow gets it. Local `make` targets call the same
scripts, so a green run locally means the same thing it means on a runner.

| Shared piece | Used by | What it does |
|---|---|---|
| `.github/actions/setup-native-build` | CI `test`, Release ×2, Nightly ×2 | Bun + caches, `bun install`, design tokens + widget build, `Config.xcconfig`, `SponsorConfig`, SwiftPM cache. Takes `twitch-client-id` / `discord-client-id` inputs (default `placeholder` for test builds). |
| `make test-ci` | CI, Release, Nightly | The single `xcodebuild test` invocation. Do not inline a different one in a workflow. |
| `scripts/check-generated-drift.sh` | CI `test`, `make check-drift` | Fails on drift in `widget.html`, the five generated token outputs, `SponsorConfig.generated.swift`, or `AppIcon-Dev.icon`, naming the fix command per group. |
| `scripts/import-signing-cert.sh` | Release, Nightly | Developer ID `.p12` into a throwaway keychain. |
| `scripts/codesign-app.sh` | Release, Nightly | Inside-out app signing (never `--deep`; see the comments in the script before touching it). |
| `scripts/notarize-dmg.sh` | Release, Nightly, `make notarize` | Sign + notarize + staple, dumping the notary log on rejection. |
| `scripts/generate-appcast.sh` | Release, Nightly | Sparkle appcast generation plus the edSignature / inline-`<description>` / no-`releaseNotesLink` guards. |

- `.github/workflows/test.yml` (workflow name `CI`) - Runs on every push/PR to `main`. A single `changes` job runs `dorny/paths-filter` once and every other job gates on its outputs at the **job** level, so a docs-only PR shows the native jobs as skipped rather than running a job full of no-op steps (branch protection counts a skipped job as passing):

  | Job | Name | What it gates |
  |---|---|---|
  | `changes` | Detect changes | One paths-filter pass feeding every other job's `if:`. Add a new path filter here, not in the consuming job. |
  | `test` | Build & Test | `make test-ci` on `macos-26`, plus `scripts/check-generated-drift.sh` (widget, design tokens, SponsorConfig). Sets `MallocNanoZone=0` as insurance against a since-fixed runner-image allocator crash. |
  | `ui-test` | UI Tests | `make test-ui` on `macos-26`. Separate job on purpose: it launches the real app, so it runs in minutes and fails for a different class of reason than `test`. Needs no account or network (see `UITestMode`). |
  | `docs` | Docs Build | `types:check`, `lint`, and a full docs build |
  | `streamdeck` | Stream Deck Plugin | `typecheck`, `bun test`, `pack`, and an icon-generator drift check for `apps/streamdeck/`. Keeps the TS protocol mirror honest against `StreamDeckCommand.swift`, which is in the path filter so a Swift-only change still re-runs the TS tests |
  | `lint` | SwiftLint | SwiftLint against `swiftlint-baseline.json` |
  | `lint-crash-safety` | SwiftLint (crash-safety) | **Blocking.** No new force unwrap, `try!`, or `as!` |
  | `lint-headers` | Swift file headers | **Blocking.** File-header convention |
  | `ds-lint` | Design-system lint | `bun run ds:test` (pins the lint regexes against known-good and known-bad lines), `bun run ds:lint`, plus `bun run ds:schema`, which validates `tokens.json` against `tokens.schema.json` |

- `.github/workflows/build_release.yml` - Builds, signs, notarizes, and creates a GitHub Release on tag push (`v*`). Required secrets: `DEVELOPER_ID_CERT_P12`, `DEVELOPER_ID_CERT_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`, `TWITCH_CLIENT_ID`, `DISCORD_CLIENT_ID`, `SPARKLE_PRIVATE_KEY`.
- `.github/workflows/docs.yml` - Builds and deploys the Fumadocs site to GitHub Pages. Path-filtered, so a Swift-only push to `main` doesn't burn a Pages deployment; use `workflow_dispatch` to force one.
- `.github/workflows/update_homebrew.yml` - Opens a PR on the Homebrew tap after a GitHub Release is published.
- `.github/workflows/nightly.yml` - Nightly cron (05:00 UTC, midnight Chicago) signed + notarized build off `main` that publishes the rolling `nightly` GitHub prerelease feeding the opt-in Nightly update channel. `workflow_dispatch` builds on demand. A scheduled run is skipped when nothing that ships in the app changed since the last nightly: the `guard` job checks out `main` and diffs the last published `built-from:` sha against HEAD with an exclude list (`apps/docs`, `apps/marketing`, `apps/streamdeck`, `*.md`, `*.mdx`), because `schedule` triggers ignore `paths-ignore`. Docs-only days cost nothing.
- `.github/workflows/update_sponsors.yml` - Refreshes the GitHub Sponsors list. `.github/workflows/license-year.yml` - Keeps the `LICENSE` year current.

### Sparkle Auto-Updates

Sparkle uses EdDSA (Ed25519) signing for update verification. The public key is in `Info.plist` as `SUPublicEDKey`. The private key is stored in the developer's macOS Keychain and as the `SPARKLE_PRIVATE_KEY` GitHub secret for CI.

- **DEBUG builds**: Sparkle is instantiated with `startingUpdater: false` (no background checks). Manual "Check Now" works and the `SPUUpdaterDelegate.feedURLString(for:)` callback points Sparkle at the bundled `dev-appcast.xml` (dummy v99.0.0 entry), so the full Sparkle UI is exercisable without a real release.
- **Release builds**: Sparkle checks the remote appcast at the `SUFeedURL` in Info.plist.
- **In-app release notes**: At release time, `scripts/release-notes.mjs` renders the version's `CHANGELOG.md` section into a styled, self-contained HTML file named to match the DMG (`WolfWave-X.Y.Z.html`). `generate_appcast` embeds that matching-name HTML as the appcast item `<description>`, so Sparkle's update dialog shows what's new. The `### Developer` block is dropped from the in-app notes (it stays on the web changelog), and a footer links out to the full changelog. `dev-appcast.xml` carries a styled sample so DEBUG "Check for Updates" previews the same rendering. The workflow runs the script via `bun` before the "Generate Sparkle appcast" step in `build_release.yml`.
- **Homebrew installs**: Sparkle is fully disabled (updates managed by Homebrew).
- **Key management**: Run `generate_keys` from Sparkle's tools to view/export/import keys. The tool is at `SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys` in DerivedData.

## Documentation

Docs site built with Fumadocs (Next.js) at `apps/docs/`. Content in `apps/docs/content/docs/` as `.mdx` files. Sidebar defined in `apps/docs/content/docs/meta.json` with Guide, Developers, Design System, Support, and Legal sections. The Design System group is docs-facing (`design-system/{index,foundations,components,brand}.mdx`), separate from the source-of-truth `design-system/` directory at the repo root. Deployed to GitHub Pages. Run with `bun run dev --filter docs` from root.

> **Two Stream Deck pages, one character apart.** `streamdeck.mdx` is the user-facing
> plugin walkthrough (Guide group); `stream-deck.mdx` is the control API reference
> (Developers group). Check which one you opened before editing.

### Keep docs in sync (do not let these drift)

Any change that is user-facing or changes structure updates the docs in the **same PR**. Match the change to what it touches:

- **New or changed feature / command** → `README.md` (Features + Usage) **and** the affected docs pages (`features.mdx`, `settings.mdx`, `bot-commands.mdx`), plus a `CHANGELOG.md` entry under the top unreleased `## [x.y.z]` heading and the matching top block in `changelog.mdx`. The `### Developer` subsection is contributor-only: it is stripped from Sparkle's in-app notes and is deliberately absent from `changelog.mdx`, so a developer-only entry needs no docs-site change.
- **New service, renamed file, moved directory** → `architecture.mdx` source map **and** the Source-layout list in this file.
- **Changed numbers** (widget sizes, ports, theme/layout counts, minimum macOS) → grep the docs for the old value and fix every copy.

Never hardcode a value that drifts. Read it from the source of truth instead: test count from `ls apps/native/WolfWaveTests/*.swift | wc -l`, app version from `MARKETING_VERSION` in `project.pbxproj`, widget dimensions / themes / layouts from `design-system/tokens.json`. The PR template checklists gate all of this.

> The site is a **static export** (GitHub Pages), served under the `/wolfwave` base path in production (empty in dev). A fresh git worktree under `.claude/worktrees/` has no `node_modules`, so run `bun install` once before `bun run dev`/`build` there. The preview launch config is named `docs` (port 3000); in dev the OG routes serve at `/opengraph-image` (no `.png`).

> **Docs card styling gotcha.** Fumadocs puts `data-card=""` + `class="peer"` on every heading's permalink anchor, so a bare `a[data-card]` selector borders every docs heading too. Style real `<Cards>` with `a[data-card]:not(.peer)` (or `a[data-card="true"]`) in `global.css`.

### Landing page (`app/(home)`)

The marketing home is `app/(home)/page.tsx`, an **async server component** that fetches the GitHub star count + latest release tag at build time (`getRepoStats()`, graceful fallback) so the trust chips show live-at-build data without shipping third-party shields.io images.

- **Section spine.** Every section is a `<section id="…">` introduced by a numbered `Kicker` (01–08) via the shared `Kicker` / `CenterHead` helpers. Order: hero → `audiences` (01) → `twitch` (02) → `discord` (03) → `overlay` (04) → `compare` (05) → `developers` (06) → `privacy` (07) → `faq` (08) → `cta`. **Keep the section `id`s stable**; the navbar links to them (`lib/layout.shared.tsx`: Features→`/#audiences`, Compare→`/#compare`, FAQ→`/#faq`). Download CTAs point at the `/download` route, not an on-page anchor. If you reorder, renumber the kickers to match.
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

- Swift 6.0 with async/await concurrency (no DispatchQueue for new async work)
- MARK sections organize every file (Properties, Public Methods, Private Helpers, etc.)
- DocC-style `///` comments on all public APIs
- No force unwrapping; use optionals and guard
- MVVM for views: ViewModels use `@Observable` macro (migrated from `ObservableObject`/`@Published`)
- Prefer structs for data models, classes for services
- camelCase for variables/functions, PascalCase for types
- **File header.** Every `.swift` file starts with the header Xcode generates from `apps/native/WolfWave.xcodeproj/xcshareddata/IDETemplateMacros.plist`:

  ```swift
  //
  //  AppConstants.swift
  //  WolfWave
  //
  //  Created by Nathanial Henniges on 2026-01-14.
  //  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
  //
  ```

  Line 3 is the **project** name, so test-target files say `WolfWave` too (the template uses `___PROJECTNAME___`, not `___PACKAGENAME___`). The date is the file's creation date per `git log --diff-filter=A --follow` (`--follow` matters: without it a later-moved file reports the move commit). Dates stay ISO `YYYY-MM-DD` even though Xcode's `___DATE___` expands to a locale short date, so reformat that one line after creating a file. `*.generated.swift` is exempt and keeps its generator banner. Enforced by `make lint-headers` (`scripts/check-headers.mjs`) and a blocking CI job.

## Versioning

Follows [Semantic Versioning (SemVer)](https://semver.org/): `MAJOR.MINOR.PATCH`:

- **MAJOR** - Breaking changes (API incompatibility, dropped platform support)
- **MINOR** - New features, backward-compatible
- **PATCH** - Bug fixes, security patches, code quality improvements

Version is set in `MARKETING_VERSION` in `project.pbxproj` (4 occurrences). Git tags use `v` prefix (e.g., `v1.0.1`). The release workflow triggers on `v*` tag pushes. Homebrew cask, CHANGELOG.md, and GitHub Release notes must all be updated to match.

### Build numbers: do NOT hand-bump

`CURRENT_PROJECT_VERSION` in `project.pbxproj` is a **dev-only placeholder**. Both release workflows override it at build time from [`scripts/version.sh`](scripts/version.sh), which is the single source of truth for marketing version + build number. The full rationale, including the platform limits that force this design, is in [`docs/build-versioning-standard.md`](docs/build-versioning-standard.md) — that doc is the portable house standard, written to be copied into the iOS/Android repos.

The short version:

| Rule | Why |
|---|---|
| Build number = `git rev-list --count HEAD` (floored). Stable **and** Nightly draw from the same counter. | Sparkle compares build numbers and **never offers a lower version**. Two counters means whichever channel has the bigger number strands its users on the other. |
| Never a timestamp (`$(date -u +%Y%m%d%H%M)`). | ~2×10¹¹ — about 100× over Android's `versionCode` cap of 2,100,000,000, so it can't be the house standard. It also floats so far above any hand-set int that no release can overtake it. This is the exact bug the previous nightly scheme shipped. |
| Never reset the counter per release. | The macOS App Store requires `CFBundleVersion` unique across *all* marketing versions. |
| Every `actions/checkout` in a job that resolves a version needs `fetch-depth: 0`. | The default shallow clone makes the commit count `1`. `version.sh` hard-fails on a shallow repo rather than emitting a wrong number. |
| A release tag must sit on a commit **later** than the last nightly's. | Same commit = same count = same build number, and Sparkle would never offer the release to nightly testers. The CHANGELOG + version-bump commit normally guarantees this; `build_release.yml` asserts it and fails the release if not. |

Marketing version stays hand-maintained: `MARKETING_VERSION` in the pbxproj, overridden by the `v*` tag at release time.

```bash
scripts/version.sh --channel nightly
```

### Release Checklist

Run through every item before pushing the release tag.

1. **`apps/native/WolfWave.xcodeproj/project.pbxproj`** - bump `MARKETING_VERSION` (4 occurrences). Leave `CURRENT_PROJECT_VERSION` alone: it is a dev placeholder and CI overrides it from `scripts/version.sh` (see [Build numbers](#build-numbers-do-not-hand-bump)).
2. **`CHANGELOG.md`** - add `## [X.Y.Z] - YYYY-MM-DD` entry in Keep-a-Changelog format. The release workflow renders this exact section into Sparkle's in-app update notes via `scripts/release-notes.mjs`, so write it for users first and keep developer-only items under `### Developer` (that subsection is stripped from the in-app notes).
3. **`apps/docs/content/docs/changelog.mdx`** - add `## vX.Y.Z. Month DD, YYYY` entry in MDX format (the OG card reads the latest `## vX.Y.Z` block).
4. **Push git tag** - `git tag vX.Y.Z && git push origin vX.Y.Z` triggers the release workflow (builds, signs, notarizes, creates GitHub Release).
5. **Homebrew cask** - auto-updated by `update_homebrew.yml` after the GitHub Release is created. Verify the workflow ran successfully.
6. **Bump `MARKETING_VERSION` to the *next* version** (4 occurrences) and open the new `## [X.Y.Z] - Unreleased` block in `CHANGELOG.md` + `changelog.mdx`. Do this right after the release lands, not at the start of the next one. Nightly builds advertise the committed `MARKETING_VERSION`, so until it's bumped every nightly claims the version you just shipped. `scripts/version.sh` warns on stderr when it detects this (committed version == newest `v*` tag).

> After tagging, verify the GitHub Actions release workflow completes cleanly before announcing.
