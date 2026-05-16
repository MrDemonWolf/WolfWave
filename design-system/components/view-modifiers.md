# ViewModifiers

**File:** [`apps/native/wolfwave/Views/Shared/ViewModifiers.swift`](../../apps/native/wolfwave/Views/Shared/ViewModifiers.swift)

Bundle of cross-cutting SwiftUI view modifiers. Each is exposed as a chainable extension on `View`.

---

## `.cardStyle()` / `.cardStyleUnpadded()`

Wraps content in a macOS 26 Liquid Glass card.

```swift
content
  .padding(DSDimension.Settings.cardPadding)   // unless cardStyleUnpadded
  .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DSDimension.Settings.cardCornerRadius))
```

- **Tokens:** `DSDimension.Settings.cardPadding` (16), `DSDimension.Settings.cardCornerRadius` (14).
- **When to use:** any grouped settings region. Default container.
- **When _not_:** inside another card (no nesting), or for full-bleed hero sections.

## `.interactiveRow(isEnabled:)`

Adds hover background + pointer cursor for list rows that act as buttons.

- **Tokens:** `DSRadius.sm` (6), `Color.primary.opacity(0.04)`.
- **When to use:** rows in custom selection lists that aren't `Button` / `List` rows.
- **When _not_:** for `Toggle`/`Picker` controls — they have native affordance.

## `.pointerCursor()`

Sets `NSCursor.pointingHand` on hover. Use on clickable non-Button views (`Image`, `Text` with `.onTapGesture`, etc.).

## `.disabledCursor(_:)`

Sets `NSCursor.operationNotAllowed` when `isDisabled == true`.

## `.sectionHeader()` / sub-header

Standardized section-header typography.

- **Tokens:** `DSFont.Size.lg` (17) / `.semibold` for primary; `.md` (14) / `.semibold` reserved for sub-headers (currently `.system(size: 15, weight: .semibold)` — pending alignment to 14 in next migration pass).

---

## Do / Don't

- ✅ Reach for `cardStyle()` before drawing your own rounded rectangle.
- ✅ Combine `pointerCursor()` with any custom `.onTapGesture` to make affordance obvious.
- ❌ Don't manually re-implement glass surfaces — `cardStyle()` already routes through macOS 26 `.glassEffect`.
- ❌ Don't apply `interactiveRow` to disabled controls — pass `isEnabled: false` instead so the hover state is suppressed.
