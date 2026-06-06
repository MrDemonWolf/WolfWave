# NowPlayingHeroCard

**File:** [`apps/native/WolfWave/Views/Shared/NowPlayingHeroCard.swift`](../../apps/native/WolfWave/Views/Shared/NowPlayingHeroCard.swift)

## Purpose
The "Now Playing" hero on the General tab — 92pt album art, title/artist/album, and a scrubber. Composes `AlbumArtView` for the artwork tile and the standard macOS card surface (`.cardStyleUnpadded()`) for the card background.

## API
```swift
NowPlayingHeroCard(
    track: "Anti-Hero",
    artist: "Taylor Swift",
    album: "Midnights",
    elapsed: 68,
    duration: 201
)
```

| Param | Type | Notes |
|---|---|---|
| `track` | `String?` | Nil renders the empty state ("Nothing playing right now" or "Sync Music is off"). |
| `artist` | `String?` | Combined with album into a single em-dash separated subtitle. |
| `album` | `String?` | Same — either, both, or neither can be nil. |
| `artwork` | `NSImage?` | When nil the inner `AlbumArtView` falls back to a hashed gradient. |
| `elapsed` | `TimeInterval` | Seconds. Shown as `M:SS` in monospaced caption. |
| `duration` | `TimeInterval` | Seconds. Scrubber + total time hidden when 0. |
| `trackingEnabled` | `Bool` | Drives the empty-state copy when `track == nil`. |

## Tokens used
- `DSDimension.Settings.cardCornerRadius` (14) — card corner radius via `.cardStyleUnpadded()` (opaque `controlBackgroundColor` surface)
- `DSFont.Size.sm` (11) `.semibold` `.tertiary` `.uppercase` `tracking(0.6)` — "Now playing" eyebrow label
- `DSFont.Size.lg` (17→18) `.semibold` — track title
- `DSFont.Size.base` (13) `.secondary` — artist · album subtitle
- `DSFont.Size.sm` (11) monospaced — scrubber timestamps
- `DSSpace.s6` (16) — card outer padding (rendered as 18 for hero weight)
- `DSSpace.s6` (16) — artwork ↔ text gap
- `DSMotion.Duration.base` (0.22) — track-change animation, gated by `@Environment(\.accessibilityReduceMotion)`
- Composes `AlbumArtView` (92pt) — see [album-art-view.md](album-art-view.md)

## Motion

- **Title swap** — `id(track ?? "")` + `.contentTransition(.opacity)` so each unique title gets its own identity and cross-fades into the next.
- **Subtitle swap** — same `id(subtitle)` + `.contentTransition(.opacity)` pattern for `artist · album`.
- **Timecode** — `.contentTransition(.numericText())` on the `M:SS / M:SS` text. Digits tween instead of blink-replacing every second.
- **Scrubber** — wrapped in `TimelineView(.animation(minimumInterval: 0.1, paused: reduceMotion))`. The `ProgressView(value:)` fraction is recomputed every 100ms inside the timeline, so the bar interpolates between the ~1s source updates instead of stepping.
- **Outer animation** — `.animation(reduceMotion ? nil : .easeInOut(duration: DSMotion.Duration.base), value: track)` so callers don't need to wrap track mutations in `withAnimation`.
- All motion respects `accessibilityReduceMotion`: timeline pauses, animation becomes `nil`, contentTransitions degrade to instant swaps.

## Anatomy
```mermaid
graph LR
  Card[HStack spacing 16 padding 18 .cardStyleUnpadded] --> Art[AlbumArtView 92pt or fallback music.note tile]
  Card --> Text[VStack alignment leading spacing 4]
  Text --> Eyebrow[Text — NOW PLAYING uppercase]
  Text --> Title[Text — lg semibold .contentTransition .opacity id track]
  Text --> Subtitle[Text — base secondary .contentTransition .opacity id subtitle]
  Text --> Progress[TimelineView .animation 0.1s]
  Progress --> Bar[ProgressView linear — fraction]
  Progress --> Stamp[Text M:SS / M:SS — .contentTransition .numericText]
```

## Accessibility
- `accessibilityElement(children: .combine)` — VoiceOver reads the whole card.
- Compound label: `"Now playing: <track>, by <artist>, on <album>"` — falls back to permission-state copy when no track.
- When `duration > 0` the label appends the scrubber clock: `"…, <elapsed> elapsed, <remaining> remaining"` (formatted via `HistoryFormat.clock`), so VoiceOver announces playback position that the visual scrubber otherwise conveys only graphically.
- `monospacedDigit()` keeps timestamps stable as the seconds tick.
- Reduce Motion: scrubber timeline pauses (the static fraction still renders), title/subtitle contentTransitions degrade to step swaps, outer animation drops to `nil`.

## Do / Don't
- ✅ Place at the top of the General tab, single instance per pane.
- ✅ Pass nil `track` rather than empty strings so the empty state copy renders.
- ❌ Don't use elsewhere as a "song chip" — use a `Compact` widget layout or a custom row instead.
- ❌ Don't override the card padding/radius — they're tuned to the standard card surface.

## Example
```swift
NowPlayingHeroCard(
    track: nowPlaying?.track,
    artist: nowPlaying?.artist,
    album: nowPlaying?.album,
    artwork: nowPlaying?.artwork,
    elapsed: elapsed,
    duration: nowPlaying?.duration ?? 0,
    trackingEnabled: trackingEnabled
)
```
