# Build & version standard

House standard for marketing versions and build numbers across every MrDemonWolf app: iOS,
Android, macOS desktop, notarized DMG, and store builds. Written to be copied into another repo
unchanged — only `scripts/version.sh` needs a per-repo tweak for where the marketing version lives.

WolfWave is the reference implementation.

## The rules

**1. Two axes, never conflated.**

| Axis | What it is | iOS / macOS | Android |
|---|---|---|---|
| Marketing version | SemVer `MAJOR.MINOR.PATCH`, hand-set, what users see | `CFBundleShortVersionString` | `versionName` |
| Build number | One opaque ascending integer. Never semantic, never reset | `CFBundleVersion` | `versionCode` |

The build number carries no meaning. Do not encode the date, the version, or the platform in it.
Every attempt to make it meaningful collides with one of the platform limits below.

**2. One counter, all channels, all platforms.** Stable, beta, and nightly draw from the *same*
counter. Separate counters are how you strand users: an updater that never offers a lower build
number will never move someone from the channel with the bigger number back to the one with the
smaller.

One counter is necessary but not sufficient — a stable release must resolve *strictly greater*
than the newest prerelease, and a tag placed on the exact commit a prerelease was built from
resolves equal. The release commit normally guarantees a later commit; assert it in CI rather than
trusting it.

**3. Resolve once, pass down.** A single script emits both values; every platform job consumes its
output. Nothing downstream computes its own.

**4. Build numbers are computed, not committed.** The value in the project file is a dev placeholder
that CI always overrides. Marketing version stays hand-maintained and authoritative.

**5. Suffixes are for non-store channels only.** `2.1.0-nightly+a1b2c3d` is fine on a DMG or an
internal track. Anything bound for the App Store or Play Store ships the bare `MAJOR.MINOR.PATCH`.

**6. A prerelease advertises the *next* release, not the last one.** `2.1.0-nightly+a1b2c3d` means
"heading into 2.1.0". This falls out for free if the committed marketing version is bumped to the
next version immediately after tagging a release, rather than at the start of the next cycle — the
prerelease channel then reads the right number for the whole window. Make that a release-checklist
step, and have the resolver warn when the committed version still equals the newest release tag,
which is exactly the signal that the bump-ahead was skipped.

## The constraints these rules exist to satisfy

| Platform | Field | Hard rule |
|---|---|---|
| iOS / macOS | `CFBundleVersion` | one to three period-separated integers, ≤18 chars, digits and periods only; must increase per upload. **macOS App Store requires it unique across *all* marketing versions**; iOS permits reuse across different marketing versions |
| iOS / macOS | `CFBundleShortVersionString` | at most three period-separated integers — no `-nightly`, no `+sha` |
| Android | `versionCode` | positive integer, **max 2,100,000,000**, must increase per upload |
| Android | `versionName` | free-form string |
| Sparkle (macOS DMG) | `sparkle:version` | reads `CFBundleVersion`; never offers a lower build number |

Two consequences worth stating outright, because both have already bitten:

- **A timestamp build number is disqualified.** `YYYYMMDDHHMM` is ~2×10¹¹ — roughly 100× over
  Android's `versionCode` cap. It also floats so far above a hand-set integer that no normal release
  can ever overtake it, which permanently strands anyone who installed such a build.
- **Per-release resets are disqualified.** macOS's cross-version uniqueness rule forbids them.

## Counter source

**`git rev-list --count HEAD`.**

Stateless and reproducible from any checkout, identical across every platform job in a monorepo, and
far under the Android cap. A release commit (version bump + changelog) always advances it, so a
stable tag automatically outranks the last prerelease built before it — no manual reconciliation.

Rejected alternatives:

| Source | Why not |
|---|---|
| CI run number (`github.run_number`) | Per-*workflow*, not per-repo. Stable and nightly would keep separate counters — the exact collision this standard exists to prevent. Also resets if a workflow file is recreated. |
| UTC timestamp | Over the Android cap; strands users. See above. |
| Hand-committed integer | Must be bumped for every prerelease too, or the channels diverge again. Highest discipline cost, and the failure is silent. |

**The one hazard: shallow clones.** `actions/checkout` defaults to `fetch-depth: 1`, which makes the
commit count `1`. Every job that resolves a version must set `fetch-depth: 0`. The resolver hard-fails
on a shallow repo rather than emitting a wrong number.

### Floors

A repo that has already published a build number above its own commit count needs a floor to clear
it. Raising a floor is a one-way door — it can only go up, because every store and updater rejects a
regression. Keep it as a named constant in the resolver with a comment explaining what it clears.

## Reference implementation

[`scripts/version.sh`](../scripts/version.sh) emits:

```json
{"marketing":"2.1.0","build":660,"short_sha":"c1e012e","channel":"stable"}
```

```bash
scripts/version.sh                    # stable, JSON
scripts/version.sh --channel nightly  # appends -nightly+<sha> to marketing
scripts/version.sh --format env       # KEY=value, for eval or $GITHUB_OUTPUT
```

Marketing version comes from the `v*` tag when building one, else from the committed value. Set
`MARKETING_VERSION_OVERRIDE` to force it.

Wiring, per platform:

| Platform | How to apply |
|---|---|
| Xcode | Pass `MARKETING_VERSION=` and `CURRENT_PROJECT_VERSION=` on the `xcodebuild` command line. Do not rewrite the pbxproj. |
| Gradle | Read both into `versionName` / `versionCode` in `build.gradle`, sourced from an env var or a `gradle.properties` written by CI. |
| Electron / Tauri | Marketing version into `package.json` / `tauri.conf.json`; build number into the platform-specific bundle fields. |

In WolfWave both [`.github/workflows/build_release.yml`](../.github/workflows/build_release.yml) and
[`.github/workflows/nightly.yml`](../.github/workflows/nightly.yml) call it in a `Resolve version`
step and inject the results at build time.

## Adopting this in a new repo

1. Copy `scripts/version.sh`; adjust the marketing-version lookup for that project's manifest.
2. Set the floor to clear anything already published, or leave it at the default if nothing has been.
3. Add `fetch-depth: 0` to every checkout in a job that resolves a version.
4. Inject both values at build time; stop hand-bumping the build number.
5. If a build number was already published above the new counter, that channel takes a one-time
   break — those installs need a manual reinstall. Say so in the release notes.
