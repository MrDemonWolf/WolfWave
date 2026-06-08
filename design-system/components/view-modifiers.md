# ViewModifiers

**File:** [`apps/native/WolfWave/Views/Shared/ViewModifiers.swift`](../../apps/native/WolfWave/Views/Shared/ViewModifiers.swift)

Bundle of cross-cutting SwiftUI view modifiers. Each is exposed as a chainable extension on `View`.

---

## `.cardStyle()` / `.cardStyleUnpadded()`

Wraps content in the standard macOS card surface.

```swift
content
  .padding(DSDimension.Settings.cardPadding)   // unless cardStyleUnpadded
  .background(
    Color(nsColor: .controlBackgroundColor),
    in: RoundedRectangle(cornerRadius: DSDimension.Settings.cardCornerRadius)
  )
  .overlay(
    RoundedRectangle(cornerRadius: DSDimension.Settings.cardCornerRadius)
      .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
  )
```

- **Why opaque, not glass:** the previous `.glassEffect` version was translucent, so each card sampled a different backdrop by screen position. Wallpaper bloom made two identical cards render as different shades. `controlBackgroundColor` is the macOS default grouped-content surface. It is opaque (the same color everywhere) and adapts to light and dark on its own. A `separatorColor` hairline gives the native card edge.
- **Tokens:** `DSDimension.Settings.cardPadding` (16), `DSDimension.Settings.cardCornerRadius` (14).
- **When to use:** any grouped settings region. Default container.
- **When _not_:** inside another card (no nesting), or for full-bleed hero sections.
- **Real-color cards keep their color** (they do not route through this modifier): the Discord brand card, callout / status banners (semantic info / warn / error tints), icon and accent chips, and share-card exports (opaque `windowBackgroundColor` for image render). Tinted sub-cards (Advanced danger red, Song Request orange / quaternary, App Visibility indigo notice, WebSocket blue info) still hand-roll because the modifier has no `tint:` option. A future `CardModifier(padded:tint:)` could fold those in.

## `.interactiveRow(isEnabled:)`

Adds hover background + pointer cursor for list rows that act as buttons.

- **Tokens:** `DSRadius.sm` (6), `Color.primary.opacity(0.04)`, `DSMotion.Duration.fast` (0.15) for the hover-fade.
- **When to use:** rows in custom selection lists that aren't `Button` / `List` rows.
- **When _not_:** for `Toggle`/`Picker` controls; they have native affordance.
- **Cursor:** uses SwiftUI `.pointerStyle(isEnabled ? .link : nil)`; the system handles push/pop. No manual `NSCursor` calls.

## `.pointerCursor()`

Pointing-hand cursor on hover for clickable non-Button views (`Image`, `Text` with `.onTapGesture`, etc.).

- Wraps SwiftUI `.pointerStyle(.link)` (macOS 15+); never leaks like a manual `NSCursor.push/pop` pair would.
- (`.disabledCursor(_:)` was removed; it was unused. If you need a not-allowed cursor, gate the parent `Button` with `.disabled(true)` and let the system pick.)

## `Animation.reducedMotion(_:reduceMotion:)`

Returns the supplied animation, or `nil` when the user has Reduce Motion enabled.

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
// …
.animation(
    .reducedMotion(.easeInOut(duration: DSMotion.Duration.base), reduceMotion: reduceMotion),
    value: state
)
```

## `.reduceMotionAware(_:reduceMotion:value:)`

Sugar for the above. Applies an animation that respects Reduce Motion. Pulls the value via `@Environment(\.accessibilityReduceMotion)` at the call site.

## `.skeleton(_:)`

Renders content as a redacted placeholder while loading. Suppresses hit-testing and VoiceOver so users can't tap or hear stale data.

```swift
QueueRow(item: placeholder).skeleton(isLoading)
```

- Wraps `.redacted(reason: isLoading ? .placeholder : [])` with `.accessibilityHidden(isLoading)` + `.allowsHitTesting(!isLoading)`.
- **When to use:** first-paint loading states with content shape (lists, grids, stat cards).
- **When _not_:** for short, indeterminate spinners; `ProgressView()` is the right tool there.

## `.sectionHeader()` / sub-header

Standardized section-header typography.

- **Tokens:** `DSFont.Size.lg` (17) / `.semibold` for primary; `.md` (14) / `.semibold` reserved for sub-headers (currently `.system(size: 15, weight: .semibold)`, pending alignment to 14 in next migration pass).

---

## Do / Don't

- ✅ Reach for `cardStyle()` before drawing your own rounded rectangle.
- ✅ Combine `pointerCursor()` with any custom `.onTapGesture` to make affordance obvious.
- ❌ Don't hand-roll your own card surface. `cardStyle()` is the one neutral card chrome.
- ❌ Don't apply `interactiveRow` to disabled controls. Pass `isEnabled: false` instead so the hover state is suppressed.
