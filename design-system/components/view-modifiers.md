# ViewModifiers

**File:** [`apps/native/WolfWave/Views/Shared/ViewModifiers.swift`](../../apps/native/WolfWave/Views/Shared/ViewModifiers.swift)

## Purpose

Bundle of cross-cutting SwiftUI view modifiers, each exposed as a chainable extension on
`View`: the card surfaces, the heading ramp, the pointer cursor, the loading skeleton, the
width-stabilizer, and the optional accessibility identifier. Plus two `Color` helpers for
hex round-tripping. Every settings pane reaches for at least one of these, so the file is
the single place the neutral card chrome and the type ramp are defined.

## API

```swift
extension View {
    func cardStyle() -> some View
    func cardStyleUnpadded() -> some View
    func subtleCardShell(cornerRadius: CGFloat = AppConstants.SettingsUI.cardCornerRadius) -> some View
    func pointerCursor() -> some View
    func skeleton(_ isLoading: Bool) -> some View
    func paneTitle() -> some View        // H1
    func sectionHeader() -> some View    // H2
    func sectionEyebrow() -> some View   // H3
    func fieldSubtitle() -> some View    // body
    func captionText() -> some View      // caption
    func stableWidth<Ghost: View>(@ViewBuilder ghosts: () -> Ghost) -> some View
    @ViewBuilder func accessibilityIdentifier(optional identifier: String?) -> some View
}

extension Color {
    nonisolated init?(hex: String)
    func toHex() -> String?
}
```

### `.cardStyle()` / `.cardStyleUnpadded()`

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
- **When to use:** any grouped settings region. Default container.
- **When _not_:** inside another card (no nesting), or for full-bleed hero sections.
- **Real-color cards keep their color** (they do not route through this modifier): the Discord brand card, callout / status banners (semantic info / warn / error tints), icon and accent chips, and share-card exports (opaque `windowBackgroundColor` for image render). Tinted sub-cards (Advanced danger red, Song Request orange / quaternary, App Visibility indigo notice, WebSocket blue info) still hand-roll because the modifier has no `tint:` option. A future `CardModifier(padded:tint:)` could fold those in.

### `.subtleCardShell(cornerRadius:)`

Quieter sibling of `cardStyle()`: the same opaque `controlBackgroundColor` surface, but on a continuous-corner shape with a faint `Color.primary.opacity(0.06)` 0.5pt stroke instead of the 1pt `separatorColor` hairline. Adds no padding; callers own their internal padding.

```swift
content
  .background(
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      .fill(Color(nsColor: .controlBackgroundColor))
  )
  .overlay(
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
  )
```

- **When to use:** onboarding rows (`OnboardingToggleCard`), grouped toggle stacks (the Notifications step's alert group), and the Song Requests setup sheet's step/recap groups. These sites used to hand-roll identical fill + overlay pairs.
- **When _not_:** standard settings cards; use `cardStyle()`. The onboarding smart-toggle cards (Discord, OBS) use `.onboardingTintedToggleShell(...)` (see [`onboarding-toggle-card.md`](onboarding-toggle-card.md)), whose off state matches this shell exactly.

### `.pointerCursor()`

Pointing-hand cursor on hover for clickable non-Button views (`Image`, `Text` with `.onTapGesture`, etc.).

- Wraps SwiftUI `.pointerStyle(.link)` (macOS 15+); never leaks like a manual `NSCursor.push/pop` pair would.
- (`.disabledCursor(_:)` was removed; it was unused. If you need a not-allowed cursor, gate the parent `Button` with `.disabled(true)` and let the system pick.)
- (`.interactiveRow(isEnabled:)` was also removed in the 2.1.0 dead-code sweep. For a row that acts as a button, use a real `Button` with `.buttonStyle(.plain)` and pair it with `pointerCursor()`.)

### `.skeleton(_:)`

Renders content as a redacted placeholder while loading. Suppresses hit-testing and VoiceOver so users can't tap or hear stale data.

```swift
QueueRow(item: placeholder).skeleton(isLoading)
```

- Wraps `.redacted(reason: isLoading ? .placeholder : [])` with `.accessibilityHidden(isLoading)` + `.allowsHitTesting(!isLoading)`.
- **When to use:** first-paint loading states with content shape (lists, grids, stat cards).
- **When _not_:** for short, indeterminate spinners; `ProgressView()` is the right tool there.

### Heading ramp: `.paneTitle()` / `.sectionHeader()` / `.sectionEyebrow()`

Standardized heading typography. Each adds `.isHeader` for VoiceOver where appropriate and
scales via `@ScaledMetric` for Dynamic Type.

- `.paneTitle()` (H1): `DSFont.Size.x2xl` (22) / `.bold`.
- `.sectionHeader()` (H2): `DSFont.Size.lg` (17) / `.semibold`.
- `.sectionEyebrow()` (H3): sentence-case micro-header inside cards. See [`section-eyebrow.md`](section-eyebrow.md).
- Body text: `.fieldSubtitle()` (13) and `.captionText()` (10).

The old `.sectionSubHeader()` (15) was retired 2026-06-05 because it collided with the
17pt pane title. Do not reintroduce a size between 14 and 17.

### `.stableWidth(ghosts:)`

Sizes a view to the widest of a set of invisible ghost variants, so a label that swaps text
("Connect" to "Disconnect") does not resize its container mid-animation. `AsyncActionButton`
uses it to pin its width across the idle / running / success phases.

### `.accessibilityIdentifier(optional:)`

Applies an identifier only when the string is non-nil, so callers can pass an optional
without an `if let` at every call site.

### `Color(hex:)` / `Color.toHex()`

Parse a `#RRGGBB` / `#RRGGBBAA` string into a `Color`, and back. Used by the widget
appearance settings (`WebSocketSettingsView`), which persist user-picked overlay colors as
hex strings. `init?(hex:)` is `nonisolated` so it can be called off the main actor.

## Tokens used

- `DSDimension.Settings.cardPadding` (16) and `DSDimension.Settings.cardCornerRadius` (14) for `cardStyle()` and the `subtleCardShell` default. Call sites reach them through the `AppConstants.SettingsUI` alias, which re-exports the generated `DSDimension.Settings` values; `tokens.json` is still the source of truth.
- `DSRadius.lg2` (12) is what onboarding-language cards pass to `subtleCardShell(cornerRadius:)`.
- `DSFont.Size.x2xl` / `.lg` / `.sm` / `.base` / `.xs` for the five text modifiers, each behind `@ScaledMetric`.
- `Color(nsColor: .controlBackgroundColor)` and `Color(nsColor: .separatorColor)` for the card surface and hairline. System colors on purpose: they are the macOS grouped-content surface and adapt to appearance.

## Anatomy

```mermaid
graph LR
    Content["any View"]
    Content -. .cardStyle() .-> Card["padding 16 → controlBackgroundColor fill → separator hairline, radius 14"]
    Content -. .subtleCardShell() .-> Shell["controlBackgroundColor fill → primary 6% stroke 0.5pt, continuous corners"]
    Content -. .paneTitle() / .sectionHeader() / .sectionEyebrow() .-> Heading["scaled size + weight + .isHeader"]
    Content -. .skeleton(true) .-> Redacted["redacted + hit-testing off + VoiceOver hidden"]
    Content -. .stableWidth(ghosts:) .-> Stable["ZStack of hidden ghosts, widest wins"]
```

## Accessibility

- `paneTitle()` and `sectionHeader()` add `.accessibilityAddTraits(.isHeader)`, so VoiceOver users can jump between panes and sections with the rotor. `sectionEyebrow()` does not; add the trait on the container when the eyebrow labels a section.
- All five text modifiers size through `@ScaledMetric`, so they follow the user's text size setting.
- `skeleton(true)` hides the content from VoiceOver and disables hit testing, so a placeholder is never read aloud or tapped.
- `pointerCursor()` is a hover affordance only; it does not change focus or keyboard behavior.
- `accessibilityIdentifier(optional:)` exists so UI tests can target rows without every call site branching on an optional.

## Do / Don't

- ✅ Reach for `cardStyle()` before drawing your own rounded rectangle.
- ✅ Combine `pointerCursor()` with any custom `.onTapGesture` to make affordance obvious.
- ✅ Use the three-step heading ramp. A heading that needs a size not on the ramp is a sign the hierarchy is wrong, not that the ramp is missing a step.
- ❌ Don't hand-roll your own card surface. `cardStyle()` is the neutral settings-card chrome; `subtleCardShell()` is the quieter onboarding/setup variant.
- ❌ Don't hand-roll hover states on rows. Use a `Button` with `.buttonStyle(.plain)`.
- ❌ Don't nest `cardStyle()` inside `cardStyle()`.

## Example

```swift
VStack(alignment: .leading, spacing: DSSpace.s2) {
    Text("Bundle & build")
        .sectionEyebrow()
    Text("Opaque surface, internal padding, rounded corners.")
        .fieldSubtitle()
    Text("Caption / footnote level.")
        .captionText()
}
.cardStyle()
```

The Debug tab's Components gallery renders this ramp, both card shells, the skeleton, and
the pointer cursor live (`Views/Debug/DesignSystem/ComponentGallery+Status.swift`).
