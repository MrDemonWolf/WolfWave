# History & Stats settings layout redesign

Research + mockups for reworking `HistoryStatsSettingsView` from a tall single
column into a responsive two-column dashboard. Proposal only. No view code
changed yet.

- View: `apps/native/WolfWave/Views/HistoryStats/HistoryStatsSettingsView.swift`
- Charts: `apps/native/WolfWave/Views/HistoryStats/StatsChartsView.swift`
- Data: `apps/native/WolfWave/Services/ListeningHistory/StatsAggregator.swift`
  (`StatsSnapshot`), `MonthlyWrap.swift`

## The canvas (measured, not guessed)

The settings detail pane (`SettingsView.standardDetailScroll`) is a `ScrollView`
with this frame chain:

- `maxContentWidth = 720pt`, centered.
- `contentPaddingH = 28pt` each side.
- `sectionSpacing = 24pt` between cards.
- Window: `minWidth 880`, `idealWidth 1240`.

Effective content band, after the sidebar (~200-250pt) and padding, is roughly
**600pt at the minimum window, up to the 720pt cap when wide**. Two columns of
~300pt + a 24pt gutter need ~624pt. So the page *wants* one column at min
window size and two columns once the user widens it. That is the responsive
rule the redesign should follow, not a fixed split.

## What is wrong with the current layout

Render order today (fully enabled):

1. intro text
2. permission banner (conditional)
3. toggles card (History + Stats)
4. **Recently played** (min height 160)
5. summary card (3 stat tiles: This week / Today / All time)
6. charts: Last 7 days, then When you listen, **stacked** (two cards, ~260pt tall combined)
7. top artists (top 5)
8. !stats command card
9. retention card
10. actions row (Monthly Wrap / Clear History)

Problems:

- **One tall column, lots of scroll.** At 720pt wide, full-width cards waste
  horizontal space. The two charts stacked is the worst offender: ~260pt of
  height for content that fits side by side in ~150pt.
- **Order is backwards.** The long "Recently played" scroll list sits *above*
  the headline numbers and charts. Insights should lead; the raw log is a
  detail.
- **Computed data is thrown away.** `StatsSnapshot` already carries
  `topTracks`, `topAlbums`, and `topTrackToday`. The page shows only
  `topArtists`. Three of the most interesting fields never reach the user.
- **No visual hierarchy.** Config (toggles, !stats, retention) and insights
  (numbers, charts, leaderboards) are interleaved in one flat stack.

## Information architecture (shared by every option)

Split the page into three bands. Config bands stay single column; the insight
band is where two-column lives.

```
A. SETUP            intro, permission banner, toggles        (1 col, always)
B. DASHBOARD        numbers, charts, leaderboards, recent     (2 col when wide)
C. CONFIG TAIL      !stats, retention, actions                (1 col)
```

Band B only renders when `historyEnabled && statsEnabled && snapshot.hasData`,
same gate as today.

---

## Option 1 - Two-column dashboard (recommended)

Keep the existing cards. Pair them into rows that collapse to one column on
narrow windows. Surface the unused data with a segmented leaderboard.

```
 intro: "WolfWave can remember what you play, kept on this Mac..."
 [ Apple Music permission banner if denied ]

 +--------------------------------------------------------------+
 |  Listening History                                  ( ●)     |
 |  Keep a private log of the tracks you play.                  |
 |  ----------------------------------------------------------  |
 |  Stats & Charts                                     ( ●)     |
 |  Top artists, listening time, charts, and a monthly wrap.    |
 +--------------------------------------------------------------+

 === DASHBOARD =================================================

 +------------------------------+-------------------------------+
 |  129       22       129      |  TODAY'S TOP TRACK            |
 |  week      today    all-time |  [art] Howl at Dawn          |
 |  27m       4m       27m      |        Grey Wolf · 4 plays    |
 +------------------------------+-------------------------------+
   summary tiles (StatTile x3)     topTrackToday (NEW, was unused)

 +------------------------------+-------------------------------+
 |  Last 7 days                 |  When you listen              |
 |  ▁ ▃ ▂ ▅ █ ▄ ▆               |  ▁ ▁ ▃ ▅ █ ▆ ▄ ▂              |
 |  (BarMark, height 150)       |  (BarMark, height 150)        |
 +------------------------------+-------------------------------+
   charts side by side: ~260pt of stacked height becomes ~190pt

 +--------------------------------------------------------------+
 |  Top  [ Artists | Tracks | Albums ]      <- segmented        |
 |  1  Grey Wolf .................................. 42 plays     |
 |  2  Timber Pack ................................ 31 plays     |
 |  3  Night Howler ............................... 24 plays     |
 |  4  Frost Fang ................................. 19 plays     |
 |  5  Moon Chorus ................................ 15 plays     |
 +--------------------------------------------------------------+
   one card, picker swaps topArtists / topTracks / topAlbums
   (surfaces all three lists in the footprint of the old one)

 +--------------------------------------------------------------+
 |  Recently played                                             |
 |  ♪ Howl at Dawn        Grey Wolf            2 min ago        |
 |  ♪ Lone Ridge          Timber Pack          8 min ago        |
 |  ...                                                          |
 |  [ Load 10 more ]                                            |
 +--------------------------------------------------------------+
   full width on purpose: long rows need the horizontal room

 === SETTINGS ==================================================

 +--------------------------------------------------------------+
 |  !stats Twitch command                              ( ●)     |
 |  (expands to cooldowns + aliases when on)                    |
 +--------------------------------------------------------------+

 +------------------------------+-------------------------------+
 |  History retention           |  [ ✦ Monthly Wrap ]           |
 |  Keep for [ Forever ▾ ]      |  [ 🗑 Clear History ]          |
 +------------------------------+-------------------------------+
   retention is tiny; pair it with the actions instead of two rows
```

Why this one:

- **Smallest change, biggest payoff.** Reuses every existing card. The only new
  view is the "Today's top track" tile and the segmented header on the
  leaderboard.
- **Halves the chart height** and surfaces three previously-dead data fields.
- **Fixes the order**: numbers, then charts, then leaderboards, then the raw
  log, then config.
- Collapses cleanly to the current single-column stack on a narrow window, so
  small displays are not worse off.

Risk: the `!stats` card must stay full width (it grows when toggled on). Do not
pair it, or the row will jiggle when expanded.

---

## Option 2 - Hero + stat rail

A magazine layout. A tall hero on the left (~60%) anchored by "Today's top
track" with album art and the monthly-wrap CTA; a compact stat rail on the
right (~40%) stacking the three numbers vertically.

```
 +-----------------------------------+--------------------------+
 |  NOW THIS MONTH                   |  This week               |
 |                                   |    129  plays · 27m      |
 |   [ album ]   Howl at Dawn        |  ----------------------  |
 |   [  art  ]   Grey Wolf           |  Today                   |
 |               42 plays this month |    22   plays · 4m       |
 |                                   |  ----------------------  |
 |   [ ✦ See your Monthly Wrap ]     |  All time                |
 |                                   |    129  plays · 27m      |
 +-----------------------------------+--------------------------+

 +--------------------------------------------------------------+
 |  Last 7 days        ▁ ▃ ▂ ▅ █ ▄ ▆                            |
 +--------------------------------------------------------------+
 +------------------------------+-------------------------------+
 |  Top artists                 |  When you listen              |
 +------------------------------+-------------------------------+
 (recent + config bands as in Option 1)
```

Why consider it: gives the page a clear focal point and makes the Monthly Wrap
feature discoverable (today it hides in a button at the very bottom).

Cost: the hero is a genuinely new component, the 60/40 split is harder to make
collapse gracefully, and album art means wiring `ArtworkService` into this pane
(it is not here today). More work than Option 1 for a similar density win.

---

## Option 3 - Bento grid

Mixed-size tiles in a `LazyVGrid`, dashboard-style. Small number tiles, wide
chart tiles, tall leaderboard tiles, packed.

```
 +--------+--------+--------+         +--------------------------+
 | 129    | 22     | 129    |         |  Top artists             |
 | week   | today  | all    |         |  1 Grey Wolf       42    |
 +--------+--------+--------+         |  2 Timber Pack     31    |
 +---------------------------+        |  3 Night Howler    24    |
 |  Last 7 days  ▁▃▂▅█▄▆     |        |  4 Frost Fang      19    |
 +---------------------------+        |  5 Moon Chorus     15    |
 +---------------------------+        +--------------------------+
 |  When you listen ▁▃▅█▆▄   |        |  Today's top track       |
 +---------------------------+        |  Howl at Dawn · 4        |
```

Why consider it: most visually striking, best raw density, scales if more
metrics get added later.

Cost: most engineering. Bento grids are fiddly on macOS (uneven tile heights,
alignment, reflow). `LazyVGrid` with `.adaptive` reflows by *count*, not by a
designed layout, so getting the "designed" bento look means fixed
`GridItem` tracks and manual `gridCellColumns`-style spans. Highest risk of the
macOS Tahoe layout bugs the skill warns about. Overkill for ~6 metrics.

---

## Recommendation

Ship **Option 1**. It is the right ratio of payoff to risk: it reuses the
existing, already-tested cards, halves the worst vertical offender (the stacked
charts), fixes the lead-with-insights ordering, and unlocks `topTracks`,
`topAlbums`, and `topTrackToday` that are already computed and currently wasted.
Pull the "Today's top track" hero idea from Option 2 into the summary row.
Leave Option 3's bento for later if the metric set grows.

## SwiftUI implementation notes

### Responsive collapse: `ViewThatFits` with a width floor

The clean idiom is a reusable row that offers a two-column candidate first and
falls back to a stack. The key detail: give the wide candidate a `minWidth`
floor so `ViewThatFits` only picks it when the container is genuinely wide
enough, instead of always picking two columns (flexible `.infinity` children
otherwise "fit" at any width).

```swift
/// Two cards side by side, collapsing to a stack when the pane is narrow.
/// `floor` is the minimum container width that justifies two columns.
struct ResponsiveRow<Left: View, Right: View>: View {
    var floor: CGFloat = 624          // 2 x ~300pt + 24pt gutter
    var spacing: CGFloat = AppConstants.SettingsUI.sectionSpacing
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: spacing) {
                left.frame(maxWidth: .infinity)
                right.frame(maxWidth: .infinity)
            }
            .frame(minWidth: floor)    // only chosen when >= floor is available
            VStack(spacing: spacing) {
                left
                right
            }
        }
    }
}
```

Usage in the dashboard band:

```swift
ResponsiveRow { summaryCard } right: { todaysTopTrackCard }
ResponsiveRow { weekChartCard } right: { hourChartCard }
```

Why `ViewThatFits` over the alternatives here:

- `Grid` is for cells that must align across rows. Our pairs are independent, so
  Grid buys nothing and does not collapse on its own.
- `LazyVGrid(.adaptive)` reflows by item count and forces equal-width columns;
  good for a uniform list of tiles (Option 3), wrong for designed pairs that
  must drop to a *specific* stacked order.
- `ViewThatFits` expresses exactly "two columns if it fits, else stack," which
  is the requirement.

Per the macOS skill's Tahoe note, be explicit with frames and add
`.fixedSize(horizontal: false, vertical: true)` on multi-line text inside the
paired cards so they do not mis-measure during the fit check.

### Chart split

`StatsChartsView` currently stacks `weekChart` then `hourChart` in a `VStack`.
Change it to expose the two charts separately (or accept a `layout` parameter)
so the parent can place them in a `ResponsiveRow`. Normalize both to the same
height (150) so the paired row reads as one band.

### Segmented leaderboard

Replace `topArtistsCard` with a single card whose header carries a segmented
`Picker`:

```swift
enum TopList: String, CaseIterable { case artists, tracks, albums }
@State private var topList: TopList = .artists

var items: [CountedItem] {
    switch topList {
    case .artists: snapshot.topArtists
    case .tracks:  snapshot.topTracks
    case .albums:  snapshot.topAlbums
    }
}
```

`topTracks` / `topAlbums` rows already carry a `detail` field (the artist) that
`topArtists` leaves nil. Render it as a secondary line when present.

### Design-system compliance (enforced by `ds:lint`)

- No literal numbers in `font(.system(size:))`, `spacing:`, or `.padding(N)`.
  Use `DSFont.Size.*`, `DSSpace.*`. The `floor: 624` and chart `height: 150`
  above are layout constants, not spacing/padding/font tokens; if they recur,
  add `DSDimension.HistoryStats.*` entries (e.g. `twoColumnFloor`,
  `chartHeight`) rather than inlining.
- Cards keep `cardStyleUnpadded()` (opaque `controlBackgroundColor` + hairline).
  Do **not** switch the neutral cards to glass. The "Today's top track" tile may
  use real album-art color since it is a real-content card, same rule as the
  Discord/share cards.
- Card sub-headers stay sentence case via `.sectionEyebrow()`.
- Keep the existing stable-size behavior: the unified recent card pins a
  `recentCardMinHeight`. Apply the same min-height discipline to the new paired
  rows so flipping a toggle does not resize the window.

## Suggested build order

1. Extract `weekChart` / `hourChart` into standalone cards in `StatsChartsView`.
2. Add `ResponsiveRow` to `Views/Shared/` (+ a catalog entry under
   `design-system/components/`).
3. Add the "Today's top track" tile (reads `snapshot.topTrackToday`).
4. Convert `topArtistsCard` to the segmented leaderboard.
5. Reorder band B: summary+today, charts, leaderboard, recent.
6. Pair retention with the actions row.
7. Update the History & Stats screenshots in docs if any.

Each step is independently shippable; 1-3 already improve the page before the
reorder lands.
