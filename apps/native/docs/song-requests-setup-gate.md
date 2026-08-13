# Song Requests: setup gate + "playlist nuked" fallback

Shipped 2026-06. Adds a guided setup that must complete before Song Requests can
be enabled, plus a health check that catches a deleted or un-shared requests
playlist and surfaces a "set up again" banner.

## Why

The Song Requests pane mixed one-time setup with live mid-stream controls, and
the most fragile piece (the public `!playlist` share link) was buried at the
bottom of the Commands card. Nothing gated enabling, and nothing noticed when the
Apple Music "WolfWave Requests" playlist was deleted or un-shared, so `!playlist`
silently posted a dead link.

## Two playlists, do not conflate

- **WolfWave Requests** library playlist (`AppConstants.Music.requestsPlaylistName`):
  where requested songs are added and played from. Auto-created by
  `AppleMusicLibraryService.ensureRequestsPlaylist()` and self-heals if deleted.
  Essential to the feature.
- **Public share link** (`songRequestSongListURL`): only used by the `!playlist`
  chat command (`SongListCommand`). Optional.

## Product decisions

- **Gate = essentials only**: Twitch connected + Apple Music access + the
  requests playlist created. The public share link stays optional.
- **Form**: a dedicated setup **sheet wizard** launched from the pane, not the
  first-launch onboarding wizard (the feature is opt-in and Twitch-dependent).
- **Fallback (hybrid)**: an *essential* break (playlist gone and unrebuildable,
  or Apple Music access lost) re-engages the gate / holds the feature; a
  *cosmetic* break (share link un-shared) only turns off `!playlist`. A dead link
  never kills a live `!sr` stream.

## Data model

Three `UserDefaults` keys (all `runtimeStateKeys`, machine-local, never exported):

- `songRequestSetupComplete` (Bool): the gate. Set by the wizard, or by a
  one-time migration that grandfathers anyone who already had the feature on.
- `songRequestPlaylistStatus` (String): raw value of `PlaylistSetupStatus`
  (`ok` / `playlistMissing` / `linkUnshared` / `musicAccessLost` /
  `playlistNotInMusic`). Drives the banner. Mirrors `songRequestRedemptionStatus`.
- `songRequestPlaylistID` (String): last verified library-playlist ID. Discovery
  validates that exact resource's ID and name before use, allowing the streamer
  to edit its description after WolfWave established ownership. If that resource
  is gone or renamed, discovery follows pagination to exhaustion (with a loop
  guard for repeated paths) and requires the exact WolfWave description marker so it never
  adopts a same-name user playlist.

`PlaylistSetupStatus` (in `SongRequestAccess.swift`, beside `RedemptionStatus`)
exposes `bannerMessage`, `isEssential`, `actionLabel`.

## Health check

`AppleMusicLibraryService.probeRequestsPlaylist()` returns a `PlaylistProbe`
(`ok(shareURL:)` / `missing` / `notPublic` / `unreachable`). It never creates the
playlist (so a deletion is visible) and treats a transport failure as
`.unreachable`. The decision is split out into the pure
`classifyProbe(foundPlaylistID:shareURL:)`.

`ensureRequestsPlaylist()` shares one lookup/create task across concurrent
callers and persists the verified ID. Reset cancels and invalidates that task,
clears the ID, and forces the next call to revalidate or rebuild.

### The cloud / local split

`probeRequestsPlaylist()` only sees the Apple Music **cloud** library, because
that is the layer `MusicDataRequest` writes to. Playback does not read that
layer at all: `AppleMusicController.playFromRequestsPlaylist` runs
`every track of playlist "WolfWave Requests"` through AppleScript against
Music.app's **local** library, which the cloud playlist only reaches via Sync
Library. So a fully green cloud probe is compatible with playback having
nothing to play from, which is exactly the state that shipped.

`AppleMusicController.requestsPlaylistLocalVisibility()` closes that gap by
asking Music.app in the same terminology playback uses, returning
`PlaylistLocalVisibility` (`visible` / `notVisible` / `unknown`). It counts
matching playlists rather than using `reveal` or a property read, because those
fail `-1708` on a name that does not exist, which reads like "Music does not
understand the command" (PR #425 misdiagnosed exactly this). A closed Music.app
yields `.unknown` and never launches Music.

`SongRequestService.runSetupHealthCheck()` orchestrates: skip if setup not done →
`musicAccessLost` if not authorized → cloud probe (rebuild a `missing` playlist
once) → local visibility probe →
`resolveHealth(probe:storedShareURL:localVisibility:)` (pure, returns `nil` for
`.unreachable` so a blip changes nothing) → `applyHealth`. Runs on app launch
(`AppDelegate.setupSongRequestService`) and on pane `.onAppear` / sheet dismiss.
`SongListCommand` needs no change: the check turns `songListCommandEnabled` off,
and the command already returns `nil` when disabled.

A definitive `.notVisible` **relabels** an otherwise-cosmetic outcome to
`.playlistNotInMusic` and leaves every side effect intact. It deliberately does
not escalate to an essential break: Sync Library latency (and possibly an
empty-playlist edge case, see below) can produce a `.notVisible` that clears
itself, and holding the whole feature on that would be worse than a banner.
Only the streamer can turn Sync Library on, so the banner action is "Check
Again", which just re-probes. The wizard's playlist step warns the same way
without blocking Next.

> **Open question.** It is unconfirmed whether an *empty* cloud playlist
> materializes in Music.app at all, or only once it holds a track. If it is the
> latter, a fresh setup will legitimately show `playlistNotInMusic` until the
> first request lands. That is why nothing here blocks or disables on it. The
> probe itself is the cheapest way to settle this: add one song and watch the
> banner clear.

The **false-alarm guard** is the key correctness property: `resolveHealth`
returns `nil` on `.unreachable`, and `.unknown` local visibility changes
nothing, so neither a network failure nor a closed Music.app ever clears a
banner or flips a toggle.

## Key files

- `Core/AppConstants+UserDefaults.swift`: the three keys + `allKeys`/`runtimeStateKeys`.
- `Core/FeatureFlags.swift`: `songRequestSetupComplete` accessor.
- `Services/SongRequest/SongRequestAccess.swift`: `PlaylistSetupStatus`.
- `Services/SongRequest/AppleMusicLibraryService.swift`: `PlaylistProbe`,
  `probeRequestsPlaylist`, `classifyProbe`, `resetCachedPlaylistID`. Cloud layer.
- `Services/SongRequest/AppleMusicController.swift`: `PlaylistLocalVisibility`,
  `requestsPlaylistLocalVisibility`, `parseLocalVisibility`. Local layer, the
  one playback actually reads.
- `Services/SongRequest/SongRequestService.swift`: `migrateSetupState`,
  `resolveHealth`, `runSetupHealthCheck`, `applyHealth`, `HealthOutcome`.
- `Core/AppDelegate+Services.swift`: migration + startup health-check wiring.
- `Views/SongRequest/Setup/SongRequestSetupViewModel.swift` + `SongRequestSetupView.swift`:
  the wizard (steps: intro → appleMusic → playlist → shareLink → done).
- `Views/SongRequest/SongRequestSettingsView.swift`: health banner, Setup CTA
  gate on the master toggle, slimmed Commands card (Manage button), `.sheet` host.

## Tests

`PlaylistSetupStatusTests` (swept over `allCases`, so a new status cannot ship
without banner copy), `SongRequestSetupHealthTests` (resolveHealth including the
local-visibility precedence + classifyProbe + migration),
`SongRequestSetupViewModelTests`, `AppleMusicControllerTests`
(`parseLocalVisibility`), and `AppleMusicLibraryServiceTests` (transport seams;
no live network). No Keychain; isolated `UserDefaults` suites.
