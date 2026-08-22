# SectionEyebrow (modifier)

**File:** [`apps/native/WolfWave/Views/Shared/ViewModifiers.swift`](../../apps/native/WolfWave/Views/Shared/ViewModifiers.swift) (`SectionEyebrowModifier`, exposed as `.sectionEyebrow()`)

Sentence-case micro-header used inside cards to label sub-sections. There is no
`SectionEyebrow.swift`: the modifier lives in `ViewModifiers.swift`, and
[`CardEyebrowHeader`](card-eyebrow-header.md) is the icon-plus-eyebrow view built on it.

## Purpose

Replaces the legacy ALL-CAPS + letter-spacing (`.textCase(.uppercase) .tracking(0.5)`) pattern that was scattered across 14 call-sites. macOS 26 HIG prefers sentence case for in-card labels; ALL-CAPS is reserved for the tiny eyebrow tag above a hero card (e.g. the Discord Preview card's `LISTENING TO APPLE MUSIC`, which mirrors Discord's real UI).

## API

```swift
View.sectionEyebrow() -> some View
```

## Tokens used

| Token | Where |
|---|---|
| `DSFont.Size.sm` (11) | size |
| `Font.Weight.semibold` | weight |
| `Color.secondary` | foreground |

## Anatomy

```mermaid
flowchart LR
    Text["Text(\"Recently played\")"]
    Text -. .sectionEyebrow() .-> Styled["sm semibold secondary"]
```

## Accessibility

- Pure visual modifier; pair the parent container with `.accessibilityAddTraits(.isHeader)` when the eyebrow labels a section.

## Do / Don't

- ✅ Use sentence-case ("Recently played", "Top artists", "Bundle & build").
- ✅ Pair with a leading SF Symbol via `Label(_, systemImage:)`.
- ❌ Don't combine with `.textCase(.uppercase)` or `.tracking(...)`; it defeats the purpose.
- ❌ Don't use for the Discord Preview card's `LISTENING TO APPLE MUSIC` label; that's an intentional mirror of Discord's UI.

## Example

```swift
HStack(spacing: DSSpace.s1h) {
    Image(systemName: "clock.arrow.circlepath")
        .font(.system(size: DSFont.Size.sm, weight: .semibold))
        .foregroundStyle(.secondary)
    Text("Recently played")
        .sectionEyebrow()
}
.accessibilityAddTraits(.isHeader)
```
