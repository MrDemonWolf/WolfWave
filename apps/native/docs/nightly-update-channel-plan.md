# Nightly update channel — implementation plan

Add an opt-in **Nightly** update channel to WolfWave's Sparkle auto-updater. Users
pick a channel in Software Update settings; choosing Nightly shows a warning and,
once confirmed, points Sparkle at a separate nightly appcast so they ride builds
off `main` HEAD. Stable is the default and untouched for everyone who never opts in.

Decisions (chosen 2026-06-09):

- **Mechanism: dual-feed** (not Sparkle channels). A separate nightly appcast at a
  fixed URL; `SPUUpdaterDelegate.feedURLString(for:)` swaps feeds on opt-in. Keeps
  the stable release pipeline untouched and fits the current static GitHub-release
  hosting (no persistent-archive directory, no `latest`-excludes-prereleases trap).
- **Cadence: nightly cron + manual.** Scheduled daily build off `main` (skipped when
  no new commits) plus `workflow_dispatch`.

## Background: how Sparkle does this

Two supported approaches (Sparkle 2):

| Approach | How | Why we did NOT pick it |
|---|---|---|
| **Channels** | One appcast lists both; nightly items carry `<sparkle:channel>nightly</sparkle:channel>`; `allowedChannels(for:) -> Set(["nightly"])` lets opt-ins see them. `generate_appcast --channel nightly`. Both channels read the **same** feed URL. | Needs a single stable, rewritable appcast that always contains latest-stable **and** latest-nightly. Our `SUFeedURL` is `releases/latest/download/appcast.xml` (GitHub `latest` excludes prereleases) and each appcast is generated over a one-DMG `builds/` dir. Serving channels would force moving appcast hosting to Pages or a fixed release tag that both jobs regenerate with all versions present. Bigger change. |
| **feedURLString swap** (chosen) | `feedURLString(for:)` returns a nightly feed URL when opted in, else `nil` (falls back to `SUFeedURL`). | Sparkle docs say "prefer channels in the future," but this is fully supported and is the path of least resistance for our hosting. |

Sparkle refs: <https://sparkle-project.org/documentation/publishing/> (Channels,
Setting the feed programmatically). The deprecated `-setFeedURL:` is **not** used —
`feedURLString(for:)` avoids the user-defaults-permanence race entirely.

### Known caveat (applies to either approach)

Sparkle never offers a **lower** version. A user who rode Nightly (high build number)
and switches back to Stable will not be auto-offered the lower stable build; they stay
put until stable's build number passes their installed nightly, or they reinstall the
stable DMG manually. The warning UI must say so. This is inherent to channel switching,
not specific to dual-feed.

## Hosting model

- **Stable feed (unchanged):** `SUFeedURL` =
  `https://github.com/MrDemonWolf/wolfwave/releases/latest/download/appcast.xml`.
- **Nightly feed (new):** a single **rolling prerelease** with fixed tag `nightly`.
  Its assets (`WolfWave-nightly.dmg`, `appcast-nightly.xml`) are re-uploaded every run
  with `gh release upload nightly --clobber`, so the asset URLs are stable:
  - feed: `https://github.com/MrDemonWolf/wolfwave/releases/download/nightly/appcast-nightly.xml`
  - dmg:  `https://github.com/MrDemonWolf/wolfwave/releases/download/nightly/WolfWave-nightly.dmg`

Both feeds are signed with the **same** Sparkle EdDSA key (`SPARKLE_PRIVATE_KEY`) and
the same `SUPublicEDKey` in Info.plist, so the installed app verifies either feed.
Both DMGs are signed with the same Developer ID and notarized (Gatekeeper requirement).

## Version scheme for nightly

Sparkle's primary comparator is `CFBundleVersion` (= `CURRENT_PROJECT_VERSION`).
Nightly must be **monotonic and strictly greater** than any stable build number
(stable builds are small ints). The nightly job overrides at build time without
committing:

- `CURRENT_PROJECT_VERSION` = `$(date -u +%Y%m%d%H%M)` (e.g. `202606091430`) — always
  ascending, always far above stable's int build numbers.
- `MARKETING_VERSION` (display) = `<next-version>-nightly+<short-sha>`, e.g.
  `2.1.0-nightly+a1b2c3d`, so the About pane and update dialog read clearly as a dev build.

Set via `xcodebuild ... CURRENT_PROJECT_VERSION=... MARKETING_VERSION=...` overrides in
the nightly workflow only. The committed `project.pbxproj` is never touched by nightly.

Because the stable feed never lists nightly items, a huge nightly build number can never
leak into a stable user's comparison.

## Code changes (native app)

All Swift/SwiftUI. Service is already `@MainActor`; `SPUUpdaterDelegate` is MainActor
(`NS_SWIFT_UI_ACTOR`), so the new delegate logic stays on the main actor — no concurrency
work needed.

### 1. `Core/AppConstants.swift`

- New `enum Update` members:
  - `nightlyFeedURL = "https://github.com/MrDemonWolf/wolfwave/releases/download/nightly/appcast-nightly.xml"`
  - channel id strings `channelStable = "stable"`, `channelNightly = "nightly"`.
- New `UserDefaults` key `updateChannel = "updateChannel"` (default `stable`).
- Classify `updateChannel` in the backup coverage arrays (`exportableKeys` /
  `accountLinkedKeys` / `runtimeStateKeys`). Recommend **exportableKeys** (it's a genuine
  user preference, alongside `updateCheckEnabled`). `SettingsBackupKeyCoverageTests` will
  fail until it is placed — add it there and add the matching assertion.

### 2. New `Core/UpdateChannel.swift`

```swift
enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable
    case nightly
    var id: String { rawValue }
    var title: String { self == .stable ? "Stable" : "Nightly (dev)" }
    var isPrerelease: Bool { self == .nightly }
}
```

### 3. `Services/UpdateChecker/SparkleUpdaterService.swift`

- Add a persisted channel property:
  ```swift
  var channel: UpdateChannel {
      get { UpdateChannel(rawValue: UserDefaults.standard.string(forKey: .updateChannel) ?? "stable") ?? .stable }
      set {
          UserDefaults.standard.set(newValue.rawValue, forKey: .updateChannel)
          Log.info("Update channel set to \(newValue.rawValue)", category: "Update")
          // Consult the new feed immediately on the next manual check.
      }
  }
  ```
- **Extract a pure resolver** so feed selection is unit-testable without `#if DEBUG`
  fighting the test target:
  ```swift
  static func resolveFeedURLString(channel: UpdateChannel, isDebug: Bool, nightlyURL: String, devAppcastURL: String?) -> String?
  ```
  - `isDebug == true` → `devAppcastURL` (preserves today's dev-appcast behavior; DEBUG
    branch wins regardless of channel).
  - `channel == .nightly` → `nightlyURL`.
  - else → `nil` (use `SUFeedURL`).
- Rewrite `feedURLString(for:)` to call the resolver. Keep the existing DEBUG-first order.
- After a channel change, trigger `checkForUpdates()` (or
  `checkForUpdatesInBackground()` in release) so the switch takes effect without waiting
  for the 24h timer. `feedURLString(for:)` is consulted on each check, so no Sparkle state
  needs clearing.
- Optional hardening: call `updater.clearFeedURLFromUserDefaults()` once right after the
  updater starts, to wipe any stale feed a prior `-setFeedURL:` may have left (defensive;
  we never set it, but cheap insurance per Sparkle's migration note).

### 4. `Views/SoftwareUpdate/SoftwareUpdateSettingsView.swift`

- Add an **Update Channel** control to `sparkleUpdateCard` (above the Divider):
  a segmented `Picker` (`Stable` / `Nightly (dev)`), bound through `appDelegate?.sparkleUpdater`.
- Selecting **Nightly** does NOT persist immediately. Present a confirmation
  `.alert`/sheet first:
  - Title: "Switch to Nightly builds?"
  - Body (ADHD-friendly, short): "Nightly builds come straight off `main`. They're
    newer but can be buggy or unstable, get no support, and update often. To go back to
    Stable later, pick Stable here, then reinstall the latest Stable DMG."
  - Buttons: destructive-styled **"Switch to Nightly"** (persists `channel = .nightly`,
    fires a check) + **Cancel** (reverts the picker).
- Selecting **Stable** persists immediately (downgrade is safe, no warning needed) and
  shows a one-line note about the "won't auto-downgrade" caveat.
- Show a persistent **"Nightly channel — dev builds"** warning banner
  (`CalloutBanner(style: .warning)`) whenever `channel == .nightly`.
- **Homebrew installs:** hide the channel picker entirely (Sparkle is disabled there;
  `isHomebrewInstall` already gates the card).
- **DEBUG:** the picker can show but stays disabled with the existing
  "uses dev-appcast.xml" note, matching how Check Now is disabled in DEBUG.

### 5. `Views/Debug/DebugServiceControlsCard.swift`

Add a quick channel toggle + "force nightly check" button for dev testing (DEBUG-only,
optional).

## CI: new `.github/workflows/nightly.yml`

Mirrors `build_release.yml`'s build → sign → notarize steps; differs only in version
override, output naming, and publish target. Reads the same secrets
(`DEVELOPER_ID_CERT_*`, `APPLE_*`, `TWITCH_CLIENT_ID`, `DISCORD_CLIENT_ID`,
`SPARKLE_PRIVATE_KEY`), which are repo-level and therefore already available. No
GitHub environment is used: the cron must run unattended, and an environment would
only add the `release` env's manual-approval gate without scoping any secret we need.
So there is no environment to create — the only one-time step is seeding the rolling
release (rollout step 3).

```yaml
on:
  schedule:
    - cron: '0 8 * * *'   # daily 08:00 UTC
  workflow_dispatch:
```

Steps:

1. Checkout `main`. **Skip-if-no-new-commits guard:** compare HEAD sha against the sha
   stored on the existing `nightly` release (e.g. in its body or a `sha.txt` asset);
   exit early if unchanged. (Only for the `schedule` trigger; `workflow_dispatch` always
   builds.)
2. Same prep as release: Bun install, build widget, write `Config.xcconfig`, regenerate
   `SponsorConfig`, cache SwiftPM.
3. **Version override:** compute `NIGHTLY_BUILD=$(date -u +%Y%m%d%H%M)` and
   `NIGHTLY_VERSION="<next>-nightly+$(git rev-parse --short HEAD)"`; pass both as
   `xcodebuild` overrides. (Derive `<next>` from current `MARKETING_VERSION` via
   `-showBuildSettings`.)
4. Import Developer ID cert, build Release (arm64), code-sign inside-out (copy the exact
   step from `build_release.yml`), notarize + staple, build DMG named
   `WolfWave-nightly.dmg`.
5. Generate nightly release notes (reuse `scripts/release-notes.mjs` with a
   "nightly / latest `main`" header, or a short generated changelog from
   `git log <lastNightlySha>..HEAD`).
6. **Generate nightly appcast:**
   ```bash
   "$SPARKLE_BIN/generate_appcast" \
     --ed-key-file "$RUNNER_TEMP/sparkle_key" \
     --download-url-prefix "https://github.com/MrDemonWolf/wolfwave/releases/download/nightly/" \
     -o builds/appcast-nightly.xml builds/
   ```
   No `--channel` flag (dual-feed = separate file). Validate `xmllint` + assert
   `sparkle:edSignature=` present, same as the release job.
7. **Publish to the rolling prerelease:**
   ```bash
   gh release view nightly >/dev/null 2>&1 || \
     gh release create nightly --prerelease --title "WolfWave Nightly" \
       --notes "Automated builds off main. Unstable."
   gh release upload nightly \
     builds/WolfWave-nightly.dmg builds/appcast-nightly.xml --clobber
   # record HEAD sha for the skip-guard
   echo "$(git rev-parse HEAD)" > sha.txt && gh release upload nightly sha.txt --clobber
   ```
8. Path filter: only run on native changes (mirror `test.yml`'s filter) so doc-only
   commits don't spin a nightly.

> `--clobber` keeps the `nightly` release object (and its fixed asset URLs) stable while
> replacing the bytes. Do **not** delete+recreate; that can briefly 404 the feed URL.

## Docs

- New docs page `apps/docs/content/docs/nightly.mdx` (Guide section in `meta.json`):
  what nightly is, the risks, how to opt in, how to get back to stable, that Homebrew
  installs can't use it. Frontmatter per the SEO template (ogTitle/ogChips/keywords).
- Update `apps/docs/content/docs/changelog.mdx` + `CHANGELOG.md` when shipped.
- Mention the nightly channel in the Software Update section of existing update docs.

## Tests (`apps/native/WolfWaveTests/`)

- `UpdateChannelTests` — raw values, `CaseIterable`, default fallback for an unknown
  stored string.
- `SparkleUpdaterServiceTests` (extend) — `resolveFeedURLString(...)` matrix:
  - DEBUG=true → dev-appcast regardless of channel.
  - DEBUG=false, channel=nightly → nightly URL.
  - DEBUG=false, channel=stable → `nil`.
- `SettingsBackupKeyCoverageTests` (extend) — `updateChannel` is classified.
- No Keychain/network in tests (house rule). Keep the resolver pure so no Sparkle
  instance is needed.

## Rollout order

1. Native: `UpdateChannel`, AppConstants keys, pure resolver + `feedURLString` rewrite,
   coverage classification, tests. (Channel persists but the nightly feed 404s until CI
   exists — harmless; Sparkle just reports no update.)
2. UI: picker + warning alert + nightly banner.
3. CI: `nightly.yml`; run once via `workflow_dispatch` to seed the `nightly` release so
   the feed URL resolves.
4. Docs page + changelog, then ship in the next stable release so users can discover it.

## Open questions to confirm before coding

- `<next>` derivation for the nightly display version — hardcode bump rule (minor) or
  read a `VERSION` file? (Plan assumes derive-from-MARKETING_VERSION minor bump.)
- Whether to also surface the channel switch in onboarding (plan says no — keep
  onboarding stable-only; advanced users find it in Settings).
