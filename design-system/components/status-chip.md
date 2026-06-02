# StatusChip

**File:** [`apps/native/WolfWave/Views/Shared/StatusChip.swift`](../../apps/native/WolfWave/Views/Shared/StatusChip.swift)

## Purpose
Capsule-shaped status indicator (colored dot + label) used in settings sections to show connection or server state.

## API
```swift
StatusChip(text: "Connected", color: .green)
```

| Param | Type | Notes |
|---|---|---|
| `text` | `String` | Short status label (≤ 16 chars). |
| `color` | `Color` | Tint for the dot + 10% background fill. Use semantic tokens. |

## Tokens used
- `DSFont.Size.sm` (11) / `DSFont.Weight.semibold`
- `DSSpace.s1h` (6) for the dot-to-label gap
- `DSSpace.s3` (10) horizontal padding, `DSSpace.s2`-ish (5) vertical
- `DSRadius.pill` (clipped to `Capsule`)
- `DSMotion.Duration.base` (0.22) — state-change animation, gated by `@Environment(\.accessibilityReduceMotion)`
- Color: caller passes `DSColor.success` / `.warning` / `.error` / `.info` typically

## Motion

- `.contentTransition(.interpolate)` on the colored dot — `Circle().fill(color)` cross-fades on color swap.
- `.contentTransition(.opacity)` on the label — text fades through on string changes.
- Outer `.animation(reduceMotion ? nil : .easeInOut(duration: DSMotion.Duration.base), value: text)` and `value: color` so callers don't need to wrap mutations in `withAnimation`.
- When Reduce Motion is enabled the animation becomes `nil` and changes apply instantly — the `contentTransition` modifiers still ship to SwiftUI but degrade to step swaps under the system setting.

## Anatomy
```mermaid
graph LR
  Chip[Capsule background — color × 0.10] --> Dot[6×6 Circle — color]
  Dot -. contentTransition .interpolate .-> Dot2[on color change]
  Chip --> Label[Text — sm semibold]
  Label -. contentTransition .opacity .-> Label2[on text change]
```

## Accessibility
- Combined element; VoiceOver reads the label.
- Fixed `minWidth: 88` keeps layout stable between state changes — animation of width doesn't fight with text update.
- Color is **decorative**, not the sole signal — the text always conveys status.
- Reduce Motion: the chip respects `accessibilityReduceMotion` — animation drops to instant.

## Do / Don't
- ✅ Use one chip per status concern (e.g. one for Twitch connection, one for WebSocket).
- ✅ Pair with `DSColor.success / warning / error / info`.
- ❌ Don't put it inline with body copy — it's a section-level indicator.
- ❌ Don't pass long strings; truncate or use a different component.

## Example
```swift
StatusChip(text: "Connected", color: DSColor.success)
```
