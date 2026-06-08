# WolfWave Design System

Single source of truth for WolfWave's visual language across the native app, the docs site, the OBS widget overlay, and Remotion marketing videos.

## Layout

```
design-system/
  tokens.json          # canonical token source; edit this
  tokens.schema.json   # (optional) JSON schema for editor validation
  scripts/generate.ts  # bun script that emits per-platform outputs
  README.md            # this file
  components/          # markdown catalog (one .md per shared component)
```

## Generated outputs

`bun run tokens` regenerates five files. All are committed so consumers don't need to run the generator.

| Platform | Output | Consumed by |
|---|---|---|
| Native macOS | `apps/native/WolfWave/Core/DesignSystem/Tokens.generated.swift` | `DSColor`, `DSFont`, `DSSpace`, `DSRadius`, `DSMotion`, `DSDimension` |
| Docs site | `apps/docs/app/tokens.generated.css` | CSS custom properties (`--ds-*`) imported by `global.css` |
| Widget overlay | `apps/native/WolfWave/Resources/widget-tokens.generated.js` | `window.WW_TOKENS` global in `widget.html` |
| Marketing | `apps/marketing/shared/tokens.generated.ts` | Typed `tokens` export for Remotion projects |
| Docs widget themes | `apps/docs/app/(home)/_widgets/widget-themes.generated.ts` | `USER_THEMES`, `WIDGET_THEMES`, `WIDGET_LAYOUTS`, `DEFAULT_THEME`, `DEFAULT_LAYOUT` for the landing-page OBS overlay preview |

## Token namespaces

| Namespace | Purpose | Examples |
|---|---|---|
| `color.brand.{50…900}` | Primary brand scale (Apple blue) | `brand500 = #0A84FF` |
| `color.brandDark` | Brand overrides for dark mode | `brand600 = #409CFF` |
| `color.semantic` | Status colors | `success`, `warning`, `error`, `info` |
| `color.surface.{light,dark}` | Backgrounds, elevation, dividers | `base`, `surface`, `elev`, `hairline` |
| `color.text.{light,dark}` | Text hierarchy | `primary`, `secondary`, `muted` |
| `color.partner` | Third-party brand colors | `twitch`, `discord`, `appleMusic*`, `obs*` |
| `font.family` | Typeface stacks | `display`, `sans`, `serif`, `mono`, `systemAppleDisplay` |
| `font.size` | Type scale (px, mapped to CGFloat for Swift) | `xs=10`, `sm=11`, `body=12`, `base=13`, `md=14`, `lg=17`, `xl=20`, `2xl=22` |
| `font.weight` | Numeric weights | `regular=400` … `bold=700` |
| `space` | 4-step spacing scale | `1=4 … 9=28` |
| `radius` | Corner radii | `xs=4 … 2xl=16`, `pill=9999` |
| `motion.duration` | Animation durations (ms) | `fast=150`, `base=220`, `slow=320` |
| `motion.easing` | Cubic-beziers | `standard`, `emphasized` |
| `shadow` | Drop shadows incl. brand glow | `xs … lg`, `glow` |
| `dimension.settings` | Settings window sizing | `minWidth`, `cardPadding`, `cardCornerRadius`, … |
| `dimension.onboarding` | Onboarding window sizing | `windowWidth`, `brandTileSize`, … |

## Change process

1. Edit `design-system/tokens.json`.
2. Run `bun run tokens` from repo root.
3. Commit `tokens.json` **and** all five generated files in the same commit. CI verifies they are in sync (`bun run tokens && git diff --exit-code`).
4. If the change is breaking (rename, removed key, value drift), bump `meta.version` in `tokens.json` and call it out in the PR description.

## Brand primary

WolfWave's primary brand color is **Apple System Blue `#0A84FF`** (matches macOS native accent). The docs site already uses this color; v1 of the design system promotes it system-wide. Partner colors (Twitch purple, Discord blurple, Apple Music gradient, OBS dark) live under `color.partner.*`. These are partner identities, not WolfWave brand.

## Component catalog

Every reusable SwiftUI view under `apps/native/WolfWave/Views/Shared/` and `apps/native/WolfWave/Views/Onboarding/Components/` has a corresponding markdown file in `components/`. Each entry covers: purpose, props, tokens used, accessibility notes, do/don't, and an example snippet. The docs site renders these as a live styleguide at `/docs/design-system/components`.

## Out of scope (for now)

- Figma library mirror (can be derived from `tokens.json` later).
- Widget overlay light mode (current themes assume OBS-style dark canvas).
- Full Fumadocs theme replacement (we layer on top of the `ocean` preset).
