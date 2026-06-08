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

Two `UserDefaults` keys (both `runtimeStateKeys`, machine-local, never exported):

- `songRequestSetupComplete` (Bool) — the gate. Set by the wizard, or by a
  one-time migration that grandfathers anyone who already had the feature on.
- `songRequestPlaylistStatus` (String) — raw value of `PlaylistSetupStatus`
  (`ok` / `playlistMissing` / `linkUnshared` / `musicAccessLost`). Drives the
  banner. Mirrors `songRequestRedemptionStatus`.

`PlaylistSetupStatus` (in `SongRequestAccess.swift`, beside `RedemptionStatus`)
exposes `bannerMessage`, `isEssential`, `actionLabel`.

## Health check

`AppleMusicLibraryService.probeRequestsPlaylist()` returns a `PlaylistProbe`
(`ok(shareURL:)` / `missing` / `notPublic` / `unreachable`). It never creates the
playlist (so a deletion is visible) and treats a transport failure as
`.unreachable`. The decision is split out into the pure
`classifyProbe(foundPlaylistID:resolvedShareURL:)`.

`SongRequestService.runSetupHealthCheck()` orchestrates: skip if setup not done →
`musicAccessLost` if not authorized → probe (rebuild a `missing` playlist once) →
`resolveHealth(probe:storedShareURL:)` (pure, returns `nil` for `.unreachable` so
a blip changes nothing) → `applyHealth`. Runs on app launch
(`AppDelegate.setupSongRequestService`) and on pane `.onAppear` / sheet dismiss.
`SongListCommand` needs no change: the check turns `songListCommandEnabled` off,
and the command already returns `nil` when disabled.

The **false-alarm guard** is the key correctness property: `resolveHealth`
returns `nil` on `.unreachable`, so a network failure never clears a banner or
flips a toggle.

## Key files

- `Core/AppConstants.swift` — the two keys + `allKeys`/`runtimeStateKeys`.
- `Core/FeatureFlags.swift` — `songRequestSetupComplete` accessor.
- `Services/SongRequest/SongRequestAccess.swift` — `PlaylistSetupStatus`.
- `Services/SongRequest/AppleMusicLibraryService.swift` — `PlaylistProbe`,
  `probeRequestsPlaylist`, `classifyProbe`, `resetCachedPlaylistID`.
- `Services/SongRequest/SongRequestService.swift` — `migrateSetupState`,
  `resolveHealth`, `runSetupHealthCheck`, `applyHealth`, `HealthOutcome`.
- `Core/AppDelegate+Services.swift` — migration + startup health-check wiring.
- `Views/SongRequest/Setup/SongRequestSetupViewModel.swift` + `SongRequestSetupView.swift`
  — the wizard (steps: intro → appleMusic → playlist → shareLink → done).
- `Views/SongRequest/SongRequestSettingsView.swift` — health banner, Setup CTA
  gate on the master toggle, slimmed Commands card (Manage button), `.sheet` host.

## Tests

`PlaylistSetupStatusTests`, `SongRequestSetupHealthTests` (resolveHealth +
classifyProbe + migration), `SongRequestSetupViewModelTests`. All pure, no network
or Keychain, isolated `UserDefaults` suites.
