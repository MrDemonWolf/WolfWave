# TODO — follow-ups from PR #397

Follow-ups that PR [#397](https://github.com/MrDemonWolf/wolfwave/pull/397) either could not do in the authoring environment or deliberately left out of scope. Ordered by what blocks what. Items closed since are kept in place and marked `(DONE)` rather than deleted, so the reasoning stays readable.

**Blocking the 2.1.0 tag: 2 of 3 remain.** Item 1 is done; items 2 and 3 both need a human, not CI.

---

## Blocking the 2.1.0 tag

### 1. Run the native test suite (DONE)

Run on `18f85b9` (current `main`) with Xcode 26.6:

```
1364 tests, 0 failures (426 via Swift Testing)
```

The original concern was that nothing in PR #397's Swift changes had ever been
compiled: the authoring environment was Linux with no Xcode, and
`Config.xcconfig` was absent from both the worktree and the primary checkout.
That no longer holds. #397 merged as `0fbc07b`, three fix commits followed, and
the suite is now green on main, so the four touched files
(`WebSocketServerService.swift`, `AppDelegate+StreamDeck.swift`,
`AppDelegate+Services.swift`, `WhatsNewView.swift`) are compiled and covered.

The specific risk called out here was the merge that combined two branches'
edits to the *same* function, `broadcastStreamDeckState` gaining both `held` and
WW-42's `upcoming`, with the conflict resolution verified by grep rather than by
a compiler. A green build resolves that: the function compiles and its callers
type-check.

Note this is the suite only. It does **not** cover item 2 below, which needs
live Apple Music playback that no test host can exercise.

### 2. Request-takeover smoke test on macOS 26

Pre-existing, not from this PR. Commit `fd37faa` (`refactor(songrequest): extract takeover/request-playback reset helpers`) says in its own message that it passes build + 2733 tests + an adversarial review, but **CI cannot exercise Apple Music playback**, and asks for a live request-takeover-while-playing test before a release is tagged. It was isolated in its own commit specifically so it can be reverted if the smoke test regresses.

Do this before `git tag v2.1.0`.

### 3. Decide whether the Stream Deck plugin ships in 2.1.0

It currently cannot (see below). Either finish it, or confirm the changelog's "Not shippable yet" framing is what you want in the release notes.

---

## Stream Deck plugin — remaining Phase B work (WW-45)

The plugin builds, typechecks, and passes 52 tests, but **has never run on a real device**. Three things need hardware or an Elgato account.

### 4. Action icons (DONE)

Every `imgs/…` path the manifest references now exists, generated from the brand
mark by `apps/streamdeck/scripts/generate-icons.ts` (`bun run --filter streamdeck
icons`). SVG for the action icons, key art and category icon; PNG at 256/512 for
the plugin icon, which is the only slot Elgato requires raster for. A manifest
test asserts every referenced path resolves, and CI fails on drift between the
committed icons and the generator.

### 5. Verify on a physical Stream Deck (or the Elgato simulator)

Every one of these is currently an assumption:

- Keys render and update from live state.
- Key presses produce the right command and the ok/alert flash.
- The `Offline` / `Token?` / `Update` states appear when they should.
- Two keys bound to the same action correlate acks in press order (the FIFO scheme has no correlation id — this is the case most likely to be wrong).
- The Property Inspector saves global settings and the plugin picks them up.

### 6. Submit to the Elgato Marketplace

Packaging is done: `bun run --filter streamdeck pack` emits
`apps/streamdeck/dist/com.mrdemonwolf.wolfwave.streamDeckPlugin` (gitignored), and
CI runs it as a shippability check because packing validates the manifest and
every asset it points at.

What is left is the submission itself, which needs an Elgato Maker account. Do it
after item 5. Once it lands, drop the "not on the Marketplace yet" callout in
`apps/docs/content/docs/streamdeck.mdx` and close item 9.

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
