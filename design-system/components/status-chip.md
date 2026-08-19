# StatusChip

**File:** [`apps/native/WolfWave/Views/Shared/StatusChip.swift`](../../apps/native/WolfWave/Views/Shared/StatusChip.swift)

## Purpose
Capsule-shaped status indicator (leading glyph + label) used in settings sections to show connection or server state. The glyph is a state-varying SF Symbol when `systemImage` is supplied, or a plain colored dot otherwise.

## API
```swift
// Status chip: glyph + color carry the state together.
StatusChip(text: "Connected", color: DSColor.success, systemImage: StatusChip.StateGlyph.on)

// Category tag with no shared icon vocabulary: dot fallback.
StatusChip(text: "Twitch", color: .purple)
```

| Param | Type | Notes |
|---|---|---|
| `text` | `String` | Short status label (≤ 16 chars). |
| `color` | `Color` | Tint for the glyph + 10% background fill. Use semantic tokens. |
| `systemImage` | `String?` | Optional leading SF Symbol. When set, replaces the colored dot so state reads through shape **and** color (WCAG 1.4.1). Use `StatusChip.StateGlyph.*` for the on / off / paused / error / starting vocabulary. `nil` (default) falls back to a colored dot. |

### StateGlyph vocabulary
Shared SF Symbol names so connection state is consistent across panes. The enum is
`nonisolated` (the module defaults to `MainActor`) so pure status resolvers such as
`StreamDeckPaneStatus` can reference it from a unit-testable, non-view context.

| Case | Symbol | Meaning |
|---|---|---|
| `.on` | `checkmark.circle.fill` | connected / live / on |
| `.off` | `circle` | off / disconnected |
| `.paused` | `pause.circle.fill` | paused by system (e.g. missing permission) |
| `.error` | `exclamationmark.triangle.fill` | error state |
| `.starting` | `ellipsis.circle` | transient starting / connecting |

### State tint vocabulary
Pair each glyph with its semantic token. Status chips take tokens, never raw system
colors, so an "Off" pill renders the same wash everywhere:

| State | Glyph | Tint |
|---|---|---|
| connected / live / on | `.on` | `DSColor.success` |
| off / disconnected / stopped | `.off` | `DSColor.neutral` |
| starting / connecting / degraded | `.starting` | `DSColor.warning` |
| paused by system | `.paused` | `DSColor.warning` |
| error | `.error` | `DSColor.error` |
| signed in but not joined | `.off` | `DSColor.info` |

`DSColor.neutral` (`#8E8E93`, Apple's `systemGray`) exists for the off state. It is the
one system gray whose light and dark variants are identical, so a single flat token
reads correctly in both. Do not fall back to `Color.secondary`: it is translucent, so
the chip's own `color.opacity(0.1)` background lands near-invisible next to opaque
sibling chips.

## Tokens used
- `DSFont.Size.sm` (11) / `DSFont.Weight.semibold`
- `DSSpace.s1h` (6) for the dot-to-label gap
- `DSSpace.s3` (10) horizontal padding, `DSSpace.s2`-ish (5) vertical
- `DSRadius.pill` (clipped to `Capsule`)
- `DSMotion.Duration.base` (0.22): state-change animation, gated by `@Environment(\.accessibilityReduceMotion)`
- Color: caller passes `DSColor.success` / `.warning` / `.error` / `.info` / `.neutral`. See the state tint vocabulary above.

## Motion

- `.contentTransition(.symbolEffect(.replace))` on the leading SF Symbol (when `systemImage` is set): the glyph swaps with the symbol-replace effect on state change.
- `.contentTransition(.interpolate)` on the colored dot (dot fallback): `Circle().fill(color)` cross-fades on color swap.
- `.contentTransition(.opacity)` on the label: text fades through on string changes.
- Outer `.animation(reduceMotion ? nil : .easeInOut(duration: DSMotion.Duration.base), value: text)` and `value: color` so callers don't need to wrap mutations in `withAnimation`.
- When Reduce Motion is enabled the animation becomes `nil` and changes apply instantly; the `contentTransition` modifiers still ship to SwiftUI but degrade to step swaps under the system setting.

## Anatomy
```mermaid
graph LR
  Chip[Capsule background, color × 0.10] --> Glyph{systemImage set?}
  Glyph -- yes --> Sym[SF Symbol, sm semibold, color]
  Glyph -- no --> Dot[6×6 Circle, color]
  Sym -. contentTransition .symbolEffect .replace .-> Sym2[on state change]
  Dot -. contentTransition .interpolate .-> Dot2[on color change]
  Chip --> Label[Text, sm semibold]
  Label -. contentTransition .opacity .-> Label2[on text change]
```

## Accessibility
- Combined element; VoiceOver reads the label. The leading glyph is `.accessibilityHidden(true)` so the state isn't spoken twice.
- Fixed `minWidth: 88` keeps layout stable between state changes; animation of width doesn't fight with text update.
- Color is **never the sole signal**: the text always conveys status, and status chips pass `systemImage` so the state also reads through shape (WCAG 1.4.1). The dot fallback is reserved for non-status category tags where there is no shared icon vocabulary.
- Reduce Motion: the chip respects `accessibilityReduceMotion`; animation drops to instant.

## Do / Don't
- ✅ Use one chip per status concern (e.g. one for Twitch connection, one for WebSocket).
- ✅ Pass `systemImage` (a `StatusChip.StateGlyph.*` value) for any connection-state chip so color isn't the only cue.
- ❌ **No raw system colors for state.** `.green` / `.orange` / `.gray` / `Color.secondary` as a `color:` argument is a bug; use the token from the state tint vocabulary. Enforced by the `raw-status-color` rule in [`lint.ts`](../scripts/lint.ts) (`bun run ds:lint`). Raw colors are fine only for a non-status category tag (the dot-fallback form), e.g. `.purple` for a platform label.
- ❌ Don't use `DSColor.neutral` on a fixed-color surface. On the Discord preview card (`partnerDiscordSurface`) it drops to 1.9:1; that card uses `Color.white.opacity(0.35)` on purpose.
- ✅ Pair with `DSColor.success / warning / error / info`.
- ❌ Don't put it inline with body copy; it's a section-level indicator.
- ❌ Don't pass long strings; truncate or use a different component.
- ❌ Don't add a `systemImage` to a non-status category tag (e.g. a "Twitch" source label); the dot fallback is correct there.

## Example
```swift
StatusChip(text: "Connected", color: DSColor.success, systemImage: StatusChip.StateGlyph.on)
```
