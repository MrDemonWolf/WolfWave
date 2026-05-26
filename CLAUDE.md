# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

WolfWave is a native macOS menu bar app that bridges Apple Music with Twitch, Discord, and stream overlays. It tracks the currently playing song via ScriptingBridge and broadcasts it to Twitch chat via bot commands (EventSub + Helix API), shows "Listening to Apple Music" on Discord via Rich Presence, and streams now-playing data to overlays via WebSocket.

**Stack**: Swift 5.9+, SwiftUI, AppKit, macOS 26.0+, Xcode 16+. Minimal dependencies (Sparkle for auto-updates) — all other functionality uses native Apple frameworks.

**Monorepo**: bun workspaces + Turborepo. The root `package.json` defines workspaces (`apps/*`, `apps/marketing/*`) and Turbo orchestrates `dev`, `build`, and `clean` tasks across packages.

## Build & Development Commands

### Monorepo (bun + Turborepo)

```bash
bun install                              # Install all workspace dependencies
bun dev                                  # Start all dev servers via Turbo
bun run dev --filter docs                # Start docs dev server only
bun run dev --filter wolfwave-announcement  # Open Remotion studio only
bun run build --filter docs              # Build docs site
```

### Native App (Make)

```bash
make build          # Debug build via xcodebuild
make clean          # Clean build artifacts
make test           # Run unit tests (1218 tests across 42 test files)
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

`Info.plist` also contains `SUPublicEDKey` (Sparkle EdDSA public key) and `SUFeedURL` (appcast URL). These are committed and should not be modified unless rotating the Sparkle signing key.

### Entitlements — do NOT remove

`apps/native/WolfWave/WolfWave.entitlements` must keep **all** of the following keys for Music.app control to work under the App Sandbox. Removing any of them will silently break ScriptingBridge — distributed notifications still fire, but `value(forKey:)` reads return nil and the WebSocket broadcasts an empty `playback_state`. See PR #65 / PR #124 history for the regression that proved this the hard way.

| Key | Why it's required |
|---|---|
| `com.apple.security.automation.apple-events` (`true`) | Modern entitlement that lets the sandboxed app request the standard TCC Automation grant for any target. Required for the "WolfWave wants to control Music" prompt to ever appear. |
| `com.apple.security.temporary-exception.apple-events` → `["com.apple.Music"]` | Proven working entry from v1.x. Belt-and-suspenders for pre-existing TCC entries and older macOS revisions. |
| `com.apple.security.scripting-targets` → `com.apple.Music`: `["com.apple.Music"]` | The access-group name here is **not** a real Music.app sdef group, so this entry alone is a no-op — keep it but never rely on it as the only AppleEvents grant. |
| `com.apple.security.temporary-exception.sbpl` (Discord IPC socket regex) | Discord Rich Presence local Unix domain socket. |
| `com.apple.security.keychain-access-groups` | Token storage. |

If you think one of the apple-events entitlements is redundant: it isn't. Don't remove it.

### `playerState` parsing — do NOT regress to `as? NSNumber`

`AppleMusicSource.checkCurrentTrack` reads Music.app's `playerState` via `SBApplication.value(forKey:)`. **Do not** narrow the parse back to a single `stateObj as? NSNumber` cast — that quietly collapses every other bridge result into `NOT_PLAYING`, which silently blanks the now-playing card, Discord Rich Presence, and the overlay while Music is actively playing. PR #134 fixed the nil-return case; PR #136 fixed the "non-nil but unexpected bridge type" case.

The current decision flow MUST be preserved:

| Layer | Rule |
|---|---|
| `extractPlayerState(_:)` | Tolerant FourCharCode extractor — accept `NSNumber`, `Int`, `UInt32`, `NSAppleEventDescriptor.typeCodeValue`, and 4-byte `String` (e.g. `"kPSP"`). Return nil only for genuinely unknown bridge types. |
| "Track loaded" set | `kPSP` (playing), `kPSp` (paused), `kPSF` (ffwd), `kPSR` (rewind). All four emit the track. **Pausing does not blank the UI** — that's deliberate, Discord/overlay should reflect the loaded track even while paused. Only `kPSS` (stopped) or empty `currentTrack` map to `NOT_PLAYING`. |
| Fallback emit | If `extractPlayerState` returns nil but `currentTrack.name` is non-empty, trust the track and emit. Log once via `state-parse-fallback` so unknown bridge types surface in Console without spam. |
| Diagnose log | When the parse + emit path resolves to `NOT_PLAYING` while Music is running, `diagnose-not-playing` log fires once with the raw value, bridge type, and currentTrack probe — keep it. Future regressions are invisible without it. |

If a future SDK introduces a new bridge type, **add a branch to `extractPlayerState`** — don't simplify the parser. Coverage is locked in by `AppleMusicSourceTests.testExtractPlayerState*` (7 cases).

## Architecture

**Pattern**: MVVM + Service-Oriented, with an NSApplicationDelegateAdaptor-based lifecycle.

### Core flow

`WolfWaveApp.swift` → AppDelegate manages the menu bar status item, initializes services (`PlaybackSourceManager`, `TwitchChatService`, `DiscordRPCService`, `SparkleUpdaterService`, `SongRequestService`), handles settings + onboarding window lifecycle, and wires song info callbacks into the Twitch and Discord services. AppDelegate is split into `AppDelegate+MenuBar.swift`, `AppDelegate+Services.swift`, and `AppDelegate+Windows.swift`. The system tray menu is dynamic (rebuilt via `NSMenuDelegate` on each open) with now-playing info, quick toggles, hold/resume for the request queue, and conditional items.

### Source layout (`apps/native/WolfWave/`)

- **Core/** — `AppConstants.swift` + `AppConstants+Notifications.swift` (centralized config enums for keys, identifiers, timing, notification names), the `AppDelegate+*` extensions, `KeychainService.swift` (macOS Security framework wrapper), `Logger.swift` (structured logging), `PowerStateMonitor.swift`, `NetworkInfoService.swift` (LAN IP cache), `SongRequestItem.swift`, `BlocklistItem.swift`. Foundation utilities: `HTTPClient.swift` (shared async HTTP wrapper), `JSONCoders.swift` (shared `JSONEncoder`/`JSONDecoder`), `BugReportURL.swift` (pre-filled GitHub issue URL builder), `Bundle+InstallMethod.swift` (DMG vs Homebrew install detection).
- **Monitors/** — Playback source abstraction. `PlaybackSource.swift` (protocol), `AppleMusicSource.swift` (ScriptingBridge + distributed notifications + 2s fallback polling), `PlaybackSourceManager.swift` (selects + multiplexes sources). Delegate pattern via `PlaybackSourceDelegate`.
- **Services/Twitch/** — `TwitchChatService.swift` (EventSub WebSocket + Helix chat API, thread-safe with NSLock, network path monitoring for reconnection, Twitch user ID redacted in logs; also dispatches `channel.channel_points_custom_reward_redemption.add` and `channel.bits.use` events into the song-request pipeline), `TwitchChannelPointsService.swift` (Helix create / reconcile / fulfill / cancel for the WolfWave-managed "Request a Song" reward), `TwitchDeviceAuth.swift` (OAuth Device Code flow).
- **Services/Twitch/Commands/** — `BotCommand` protocol (`triggers`, `description`, `execute(message:) -> String?`), `AsyncBotCommand` for I/O-bound commands, `BotCommandContext`, `BotCommandDispatcher`. Concrete commands: `TrackInfoCommand` (used for both `!song` and `!last`), `SongRequestCommand`, `QueueCommand`, `MyQueueCommand`, `SkipCommand`, `HoldCommand`, `ClearQueueCommand`, `VoteSkipCommand` (chat vote-to-skip). `CooldownManager` enforces global + per-user cooldowns.
- **Services/SongRequest/** — `SongRequestService.swift` (request flow orchestrator; `processRequest(query:username:source:)` takes a `RequestSource` so chat commands, channel-point redemptions, and bit cheers share the same pipeline), `SongRequestAccess.swift` (`RequestAudience` chat-command gate, `RequestSource`, `SongRequestPreset` one-tap configurations, `RedemptionStatus` for the settings re-auth banner), `SongRequestQueue.swift` (queue with hold mode, Music.app-closed buffering, and a `boost(username:)` method for bit-cheer boosts), `SkipVoteManager.swift` (chat vote-to-skip sessions — chat tally or Twitch Polls), `SongSearchResolver.swift` + `LinkResolverService.swift` (MusicKit search / Apple Music link resolve), `AppleMusicController.swift` (AppleScript playback with focus preservation), `SongBlocklist.swift`.
- **Services/Discord/** — `DiscordRPCService.swift` (Discord Rich Presence via local IPC Unix domain socket, auto-reconnect with backoff).
- **Services/UpdateChecker/** — `SparkleUpdaterService.swift` (Sparkle framework wrapper for auto-updates, EdDSA-signed appcast verification, Homebrew install detection disables Sparkle, DEBUG mode allows manual check via bundled `dev-appcast.xml`).
- **Services/WebSocket/** — `WebSocketServerService.swift` (overlay broadcast), `WidgetHTTPService.swift` (static widget HTTP server).
- **Services/** — `ArtworkService.swift` (iTunes Search artwork fetch + cache), `LaunchAtLoginService.swift`.
- **Views/** — SwiftUI settings shell `SettingsView.swift` with `NavigationSplitView` sidebar. Per-section views decomposed into `GeneralSettingsView.swift`, `MusicMonitor/MusicMonitorSettingsView.swift`, `AppVisibility/AppVisibilitySettingsView.swift`, `WebSocket/WebSocketSettingsView.swift`, `Twitch/TwitchSettingsView.swift`, `Discord/DiscordSettingsView.swift`, `SongRequest/SongRequestSettingsView.swift` + `SongRequestQueueView.swift`, `Advanced/AdvancedSettingsView.swift`. `TwitchViewModel` is the main observable for auth/connection state.
- **Views/Onboarding/** — macOS 26 Liquid Glass onboarding wizard. The `OnboardingStep` enum (in `OnboardingViewModel.swift`) defines the step order: Welcome → Discord → Twitch → OBS Widget (overlay URL + HTTP widget toggle) → Preferences → Apple Music Access → Menu Bar Pointer, followed by `OnboardingCompletionView`. Components in `Onboarding/Components/` (`PillButton`, `BrandTile`).
- **Views/Debug/** — **DEBUG-only** developer tooling tab. `DebugSettingsView.swift` shell plus cards: `DebugInspectorsCard`, `DebugLogsAndEventsCard`, `DebugMetricsCard`, `DebugServiceControlsCard`, `DebugUIPreviewsCard`. Not compiled into release builds.
- **Views/Shared/** — Shared UI components: `StatusChip`, `InfoRow`, `ToggleSettingRow`, `SuccessFeedbackRow`, `SectionHeaderWithStatus`, `NowPlayingHeroCard`, `AlbumArtView`, `IntegrationDashboardView`, `ConnectionTestButton`, `ConfigRequiredBanner`, `CopyButton`, `UpdateBannerView`, `WhatsNewView`, `AboutView`, `TwitchGlitchShape`, `ViewModifiers`.

### Key patterns

- **Credentials**: All tokens/secrets stored via `KeychainService` (never UserDefaults). Keys defined in `AppConstants.Keychain`.
- **Settings**: User preferences in `UserDefaults` via `@AppStorage`. Keys centralized in `AppConstants.UserDefaults`. Note: `currentSongCommandEnabled`, `lastSongCommandEnabled`, and `widgetHTTPEnabled` all default to `false`.
- **Notifications**: Loose coupling via `NotificationCenter` (e.g., `TrackingSettingChanged`, `DockVisibilityChanged`). Names in `AppConstants.Notifications`.
- **Thread safety**: `NSLock` for shared state mutations in `TwitchChatService`. `DiscordRPCService` uses `ipcQueue` serial queue confinement plus `enabledLock` for thread safety. Logger uses a serial `DispatchQueue` for thread-safe file I/O.
- **Bot commands**: Register new commands in `BotCommandDispatcher.registerDefaultCommands()`. Each command implements `BotCommand` protocol. Max response 500 chars, target <100ms execution.
- **Discord IPC**: Unix domain socket at `$TMPDIR/discord-ipc-{0..9}`. SBPL entitlements enable socket access within App Sandbox.
- **ADHD-friendly text**: All user-facing text should be short, punchy, and jargon-free.

## Design System

Single source of truth: [`design-system/tokens.json`](design-system/tokens.json). The generator [`design-system/scripts/generate.ts`](design-system/scripts/generate.ts) emits four platform outputs — **do not edit generated files by hand**:

| Output | Path | Consumer |
|---|---|---|
| Swift | `apps/native/WolfWave/Core/DesignSystem/Tokens.generated.swift` | Native app — `DSColor`, `DSFont`, `DSSpace`, `DSRadius`, `DSMotion`, `DSDimension` |
| CSS | `apps/docs/app/tokens.generated.css` | Fumadocs site (`--ds-*` custom properties) |
| Widget JS | `apps/native/WolfWave/Resources/widget-tokens.generated.js` | `widget.html` reads via `window.WW_TOKENS` |
| Marketing TS | `apps/marketing/shared/tokens.generated.ts` | Remotion projects |

### Regenerating

```bash
bun run tokens          # Direct
bun turbo tokens        # Via Turbo (cached when inputs unchanged)
bun turbo build         # `tokens` is a build prerequisite — runs automatically
```

`turbo.json` declares `//#tokens` as a root task; both `build` and `dev` `dependsOn` it. Inputs: `design-system/tokens.json` + `design-system/scripts/generate.ts`. Outputs: the four generated files above.

### Widget themes (`window.WW_TOKENS`)

`widget.html` consumes `WW_TOKENS.themes` (6 themes — `Default`, `Dark`, `Light`, `Glass`, `Neon`, `WolfWave`) and `WW_TOKENS.layouts` (`Horizontal`, `Vertical`, `Compact`). Themes live in `tokens.json` under `widget.themes` — add or edit there, then regenerate. `WidgetHTTPService` serves `widget-tokens.generated.js` at `/widget-tokens.generated.js`, loaded via `<script src>` before the inline script.

### Component catalog

[`design-system/components/`](design-system/components/) — one markdown entry per reusable view. Status tracked in [`design-system/components/README.md`](design-system/components/README.md). Every entry follows the same template (Purpose, API, Tokens used, Anatomy mermaid, Accessibility, Do/Don't, Example) — see [`status-chip.md`](design-system/components/status-chip.md) as the quality bar.

**When you touch any of these views, update the matching catalog entry in the same change.** That keeps token usage docs and anatomy diagrams from drifting.

### Design-system discipline

These rules are enforced by [`design-system/scripts/lint.ts`](design-system/scripts/lint.ts) (`bun run ds:lint`, also run in CI):

- **Never** use literal numbers in `font(.system(size:))` — use `DSFont.Size.*` (`xs=10`, `sm=11`, `body=12`, `base=13`, `md=14`, `lg=17`, `xl=20`, `x2xl=22`).
- **Never** use literal numbers in `spacing:` or `.padding(N)` — use `DSSpace.*` (`s0=2`, `s1=4`, `s2=8`, `s3=10`, `s4=12`, `s5=14`, `s6=16`, `s7=20`, `s8=24`, `s9=28`, `s10=32`, `s11=44`).
- For single-glyph bordered buttons, use [`DSIconButton`](apps/native/WolfWave/Views/Shared/DSIconButton.swift) — do **not** hand-roll `Button { Image(...) } .buttonStyle(.bordered) .controlSize(.small)`. Hand-rolled icon-only buttons collapse to a narrower frame than text-label neighbors like `CopyButton`, causing visible drift.
- When you touch a `Views/Shared/` component, update its catalog entry in [`design-system/components/`](design-system/components/) in the same change.

Existing legacy literals are tracked in [`design-system/lint-allowlist.txt`](design-system/lint-allowlist.txt) — migrate them file-by-file in follow-up PRs; do **not** add new entries.

## Testing

Unit tests live in `apps/native/WolfWaveTests/` and use XCTest + Swift Testing with `@testable import WolfWave`. The test target is a hosted unit test bundle (`TEST_HOST` = WolfWave.app). Current pass count: **1218 tests across 42 test files**.

### Test files

- `SparkleUpdaterServiceTests.swift` — Sparkle wrapper init, manual check gating, Homebrew detection
- `TrackInfoCommandTests.swift` — `TrackInfoCommand` covering both `!song`/`!currentsong`/`!nowplaying` and `!last`/`!lastsong`/`!prevsong` trigger sets via shared fixtures (trigger matching, case insensitivity, enable/disable, callback, default message, 500-char truncation)
- `BotCommandDispatcherTests.swift` — Message routing, callback wiring, length guards, whitespace handling
- `CommandIntegrationTests.swift` — End-to-end dispatcher flow per command
- `CooldownManagerTests.swift` — Global + per-user cooldown enforcement
- `SongRequestServiceTests.swift`, `SongRequestQueueTests.swift`, `SongRequestCommandTests.swift` — Song Request system (queue, hold mode, request command parse)
- `SkipVoteManagerTests.swift`, `VoteSkipCommandTests.swift` — Chat vote-to-skip (threshold, dedup, window expiry, cooldown, subscriber gate, Polls mode, reply formatting)
- `SongRequestAccessTests.swift` — `RequestAudience` permission rules, `SongRequestPreset` apply/detect, `RedemptionStatus` banner messages
- `SongRequestQueueBoostTests.swift` — bit-cheer boost: moves a user's most-recent queued item to the front
- `TwitchBitsParsingTests.swift` — `channel.bits.use` message parsing (cheermote fragment stripping)
- `AppleMusicSourceTests.swift` — Playback source start/stop and delegate wiring
- `OnboardingViewModelTests.swift` + `OnboardingViewModelEdgeCaseTests.swift` — Step navigation, boundary conditions, UserDefaults persistence
- `TwitchViewModelTests.swift`, `TwitchChatServiceTests.swift`, `TwitchDeviceAuthTests.swift`, `TwitchDeviceAuthErrorTests.swift` — Twitch auth + EventSub + view model state
- `DiscordRPCServiceTests.swift` — IPC framing, reconnect backoff
- `DiscordPresenceBuilderTests.swift` — Rich Presence payload construction (state/details, buttons, timestamps)
- `ArtworkServiceTests.swift`, `ArtworkServiceCacheTests.swift` — iTunes Search artwork fetch + cache eviction
- `WebSocketServerServiceTests.swift`, `WebSocketServerIntegrationTests.swift`, `WidgetHTTPServiceTests.swift` — Overlay broadcast + widget HTTP
- `KeychainServiceTests.swift` — Save/load/delete, Unicode, concurrent access
- `LoggerTests.swift`, `LoggerClearTests.swift`, `PowerStateMonitorTests.swift` — Core utilities (logging, log clearing, power state)
- `BugReportURLTests.swift` — Pre-filled GitHub issue URL construction and encoding
- `BundleInstallMethodTests.swift` — DMG vs Homebrew (cask) install detection
- `AppConstantsTests.swift` + `AppConstantsEdgeCaseTests.swift` — Constant values, URL validity, dimension bounds, cross-references

### Writing tests

- Use `@testable import WolfWave` (module name matches `PRODUCT_NAME`)
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` applies to test classes too — XCTest runs on main thread
- Test files are auto-discovered via `PBXFileSystemSynchronizedRootGroup` — just add `.swift` files to `apps/native/WolfWaveTests/`
- Focus on pure logic (version comparison, command matching, state machines) — avoid tests that need AppDelegate, Keychain, or network

## CI/CD

- `.github/workflows/test.yml` — Runs `xcodebuild test` on every push/PR to `main` (path-filtered to native changes). Creates a placeholder `Config.xcconfig` for CI builds and sets `MallocNanoZone=0` to work around a runner-image allocator crash.
- `.github/workflows/build_release.yml` — Builds, signs, notarizes, and creates a GitHub Release on tag push (`v*`). Required secrets: `DEVELOPER_ID_CERT_P12`, `DEVELOPER_ID_CERT_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`, `TWITCH_CLIENT_ID`, `DISCORD_CLIENT_ID`, `SPARKLE_PRIVATE_KEY`.
- `.github/workflows/docs.yml` — Builds and deploys the Fumadocs site to GitHub Pages.
- `.github/workflows/update_homebrew.yml` — Opens a PR on the Homebrew tap after a GitHub Release is published.
- `.github/workflows/update_sponsors.yml` — Refreshes the GitHub Sponsors list. `.github/workflows/license-year.yml` — Keeps the `LICENSE` year current.

### Sparkle Auto-Updates

Sparkle uses EdDSA (Ed25519) signing for update verification. The public key is in `Info.plist` as `SUPublicEDKey`. The private key is stored in the developer's macOS Keychain and as the `SPARKLE_PRIVATE_KEY` GitHub secret for CI.

- **DEBUG builds**: Sparkle is instantiated with `startingUpdater: false` — no background checks. Manual "Check Now" works and the `SPUUpdaterDelegate.feedURLString(for:)` callback points Sparkle at the bundled `dev-appcast.xml` (dummy v99.0.0 entry), so the full Sparkle UI is exercisable without a real release.
- **Release builds**: Sparkle checks the remote appcast at the `SUFeedURL` in Info.plist.
- **Homebrew installs**: Sparkle is fully disabled (updates managed by Homebrew).
- **Key management**: Run `generate_keys` from Sparkle's tools to view/export/import keys. The tool is at `SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys` in DerivedData.

## Documentation

Docs site built with Fumadocs (Next.js) at `apps/docs/`. Content in `apps/docs/content/docs/` as `.mdx` files. Sidebar defined in `apps/docs/content/docs/meta.json` with Guide/Developers sections. Deployed to GitHub Pages. Run with `bun run dev --filter docs` from root.

## Marketing

Remotion-based video projects live in `apps/marketing/`. Each subfolder is a standalone Remotion project (React + TypeScript) for producing announcement/promo videos.

- **wolfwave-announcement** — v1.0 launch announcement video. Run `bun run dev --filter wolfwave-announcement` from root to open the Remotion editor.

## Known Harmless Runtime Noise

These lines appear in Xcode console / stdout but are emitted by macOS itself, not WolfWave. Safe to ignore — do not chase them as bugs:

- `Rule path is not accessible: /var/protected/xprotect/...` and `Error reading rules: (null)` — XProtect / sandbox introspection denial.
- `FSFindFolder failed with error=-43` — legacy Carbon API noise from a system framework.
- `CoreSVG has logged an error. Set environment variable "CORESVG_VERBOSE" to learn more.` — system SVG renderer; unrelated to our assets. Set `CORESVG_VERBOSE=1` only if you want to investigate.
- `Unable to obtain a task name port right for pid …: (os/kern) failure (0x5)` — sandbox blocks task-port introspection of other processes.

## Code Conventions

- Swift 5.9+ with async/await concurrency (no DispatchQueue for new async work)
- MARK sections organize every file (Properties, Public Methods, Private Helpers, etc.)
- DocC-style `///` comments on all public APIs
- No force unwrapping — use optionals and guard
- MVVM for views: ViewModels use `@Observable` macro (migrated from `ObservableObject`/`@Published`)
- Prefer structs for data models, classes for services
- camelCase for variables/functions, PascalCase for types

## Versioning

Follows [Semantic Versioning (SemVer)](https://semver.org/) — `MAJOR.MINOR.PATCH`:

- **MAJOR** — Breaking changes (API incompatibility, dropped platform support)
- **MINOR** — New features, backward-compatible
- **PATCH** — Bug fixes, security patches, code quality improvements

Version is set in `MARKETING_VERSION` in `project.pbxproj` (4 occurrences). `CURRENT_PROJECT_VERSION` (build number) must also be incremented with each release — Sparkle uses it as the primary version comparator in appcast.xml. Git tags use `v` prefix (e.g., `v1.0.1`). The release workflow triggers on `v*` tag pushes. Homebrew cask, CHANGELOG.md, and GitHub Release notes must all be updated to match.

### Release Checklist

Run through every item before pushing the release tag.

1. **`apps/native/WolfWave.xcodeproj/project.pbxproj`** — bump `MARKETING_VERSION` (4 occurrences) and `CURRENT_PROJECT_VERSION` (4 occurrences). Sparkle uses the build number as its primary comparator.
2. **`CHANGELOG.md`** — add `## [X.Y.Z] - YYYY-MM-DD` entry in Keep-a-Changelog format.
3. **`apps/docs/content/docs/changelog.mdx`** — add `## vX.Y.Z — Month DD, YYYY` entry in MDX format.
4. **Push git tag** — `git tag vX.Y.Z && git push origin vX.Y.Z` — triggers the release workflow (builds, signs, notarizes, creates GitHub Release).
5. **Homebrew cask** — auto-updated by `update_homebrew.yml` after the GitHub Release is created. Verify the workflow ran successfully.

> After tagging, verify the GitHub Actions release workflow completes cleanly before announcing.
