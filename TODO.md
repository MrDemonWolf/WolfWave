# TODO — follow-ups from PR #397

Everything here is outstanding work that PR [#397](https://github.com/MrDemonWolf/wolfwave/pull/397) either could not do in the authoring environment or deliberately left out of scope. Ordered by what blocks what.

---

## Blocking the 2.1.0 tag

### 1. Run the native test suite

Nothing in PR #397's Swift changes has ever been compiled. The authoring environment is Linux with no Xcode, and `Config.xcconfig` was absent from both the worktree and the primary checkout.

```bash
make test
```

Touched Swift files:

- `apps/native/WolfWave/Services/WebSocket/WebSocketServerService.swift` — `broadcastQueueState` signature gained `held: Bool`
- `apps/native/WolfWave/Core/AppDelegate+StreamDeck.swift` — reads `isHoldEnabled`, passes `held`
- `apps/native/WolfWave/Core/AppDelegate+Services.swift` — observer loop now covers `songRequestHoldChanged`
- `apps/native/WolfWave/Views/Shared/WhatsNewView.swift` — feature card array

Extra care warranted: the merge with `main` combined two branches' edits to the *same* function (`broadcastStreamDeckState` gained both `held` and WW-42's `upcoming`). Conflict resolution was verified by grep, not by a compiler.

### 2. Request-takeover smoke test on macOS 26

Pre-existing, not from this PR. Commit `fd37faa` (`refactor(songrequest): extract takeover/request-playback reset helpers`) says in its own message that it passes build + 2733 tests + an adversarial review, but **CI cannot exercise Apple Music playback**, and asks for a live request-takeover-while-playing test before a release is tagged. It was isolated in its own commit specifically so it can be reverted if the smoke test regresses.

Do this before `git tag v2.1.0`.

### 3. Decide whether the Stream Deck plugin ships in 2.1.0

It currently cannot (see below). Either finish it, or confirm the changelog's "Not shippable yet" framing is what you want in the release notes.

---

## Stream Deck plugin — remaining Phase B work (WW-45)

The plugin builds, typechecks, and passes 52 tests, but **has never run on a real device**. Three things need hardware or an Elgato account.

### 4. Action icons

`com.mrdemonwolf.wolfwave.sdPlugin/manifest.json` references `imgs/…` paths that do not exist. Stream Deck renders placeholders until they are added. Needed per action, in `@1x` and `@2x`:

| Action | Paths referenced |
|---|---|
| Play / Pause | `imgs/actions/playpause/icon`, `key-paused`, `key-playing` |
| Skip | `imgs/actions/skip/icon`, `key` |
| Hold Queue | `imgs/actions/queuehold/icon`, `key-running`, `key-held` |
| Approve Next | `imgs/actions/approvenext/icon`, `key-empty`, `key-pending` |
| Clear Queue | `imgs/actions/clearqueue/icon`, `key` |
| Block Song | `imgs/actions/blockcurrent/icon`, `key` |
| Overlay | `imgs/actions/overlaytoggle/icon`, `key-off`, `key-on` |
| Discord Presence | `imgs/actions/discordtoggle/icon`, `key-off`, `key-on` |
| Music Sync | `imgs/actions/musicsynctoggle/icon`, `key-off`, `key-on` |
| Cycle Theme | `imgs/actions/cycletheme/icon`, `key` |
| Status | `imgs/actions/status/icon`, `key-down`, `key-up` |

Plus plugin-level `imgs/plugin/category-icon` and `imgs/plugin/marketplace`.

### 5. Verify on a physical Stream Deck (or the Elgato simulator)

Every one of these is currently an assumption:

- Keys render and update from live state.
- Key presses produce the right command and the ok/alert flash.
- The `Offline` / `Token?` / `Update` states appear when they should.
- Two keys bound to the same action correlate acks in press order (the FIFO scheme has no correlation id — this is the case most likely to be wrong).
- The Property Inspector saves global settings and the plugin picks them up.

### 6. Package and submit to the Elgato Marketplace

`.streamDeckPlugin` packaging (`streamdeck pack`) plus Marketplace submission. Needs an Elgato account.

### 7. Deferred v1 actions

Named in WW-45, out of scope for the first pass:

- Announce song
- Now-playing dial with album art and rotation-bound volume

Both want app-side seams that don't exist yet. Revisit once the basic key set is confirmed working.

---

## Smaller follow-ups

### 8. Discord health is an is-enabled proxy

`AppDelegate+StreamDeck.swift` carries a `ponytail:` comment about this. The `health` broadcast reports `FeatureFlags.discordEnabled` rather than the live IPC connection state, so the Status key shows Discord as "up" whenever the feature is on, even if the socket is down. Wire the real state.

### 9. `sdPlugin` install is manual

`apps/docs/content/docs/streamdeck.mdx` documents copying the folder into `~/Library/Application Support/com.elgato.StreamDeck/Plugins/` by hand. That's fine pre-Marketplace, but revisit the page's install section once #6 lands.

### 10. `widget#build` turbo warning

`turbo build` emits `no output files found for task widget#build`. Pre-existing, not introduced by #397 — the committed `widget.html` was verified unchanged. Worth chasing separately so real drift isn't masked by an expected warning.

---

## Jira

Existing tickets this maps to:

- **WW-45** — Stream Deck Plugin, Phase B. Items 4, 5, 6, 7 above. Phase A is done; this PR does the buildable-without-hardware portion.

Worth filing as new tickets:

- Discord health proxy (item 8) — small, self-contained.
- `widget#build` turbo outputs warning (item 10) — build hygiene.

Backlog items untouched by this work, for reference: WW-18/19/20 (branding), WW-37 (web remote), WW-38 (iOS app), WW-39 (CloudKit sync), WW-40 (setlist recap), WW-41 (milestone flashes), WW-47 (browser capture), WW-48 (custom overlay layouts), WW-49 (DS gallery), WW-50 (drift gate), WW-51 (stale blocks links), WW-52 (wolf mark — may now be done by `a8c1c99`/`e046037` on `main`, worth checking), WW-53 (deep links), WW-54 (reply delivery modes).

WW-42 (overlay queue ticker) landed on `main` during this work.
