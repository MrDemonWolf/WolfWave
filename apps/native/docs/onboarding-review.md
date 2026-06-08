# UI/UX Review: WolfWave Onboarding Flow

**Reviewed:** 2026-06-06 · **Input:** Local SwiftUI code (`apps/native/WolfWave/Views/Onboarding/`) · **Method:** NN/g heuristic evaluation + Apple HIG review

## Executive summary

- The onboarding is well-built: a shared `OnboardingStepScaffold` keeps the icon→title→description→extras column at a constant Y across steps, entrance animations honor `reduceMotion`, and copy is short and ADHD-friendly.
- **Single worst problem:** the wolf hero mark is the app's primary identity, yet it renders three completely different ways across surfaces: a **partner-mashup rainbow gradient** (Twitch purple → Discord blurple → Apple Music red) in onboarding, an **adaptive monochrome template** in the menu bar, and that same gradient again on the completion screen. The menu-bar mark already does the theme-correct thing the user asked for; onboarding does not match it.
- The hero gradient is also **not WolfWave's own brand**: it is three partner brands blended. WolfWave's real brand gradient (navy → royal blue, `Brand.wolfwaveGradient`) is never used on the hero.
- **Type hierarchy is inconsistent across steps:** step titles render at 20pt (6 scaffold steps), 22pt (Menu Bar Pointer), and 26pt (Welcome/Completion), and weight flips between `.bold` and (for glyphs) `.semibold`. The project's own design-system rule reserves 26pt (`x3xl`) for "hero + Monthly Wrap" only.
- BrandTile glyph sizes vary 20/22/26 across steps with no rule.

**Findings:** 🟥 0 catastrophic · 🟧 2 major · 🟨 3 minor · ⬜ 2 cosmetic

## Findings

### 🟧 Severity 3 - Major

#### 1. Hero wolf mark is inconsistent with the menu-bar wolf and is not theme-adaptive by design

- **What:** `OnboardingWelcomeStepView` and `OnboardingCompletionView` render `WolfHeroMark(style: .brandGradient)`. That gradient is `Brand.twitch` → `Brand.discord` → `Brand.appleMusicGradientEnd` (`WolfHeroMark.swift:96-106`): a fixed mashup of three partner colors. The same wolf in the menu bar is a **template image** (`icon.isTemplate = true`, `AppDelegate+MenuBar.swift:25`), which AppKit renders as adaptive monochrome (black on a light menu bar, white on a dark one). So the identical mark looks like a rainbow on one surface and a flat silhouette on another. `WolfHeroMark`'s own doc comment says it exists so the hero "share[s] the same visual language as the tray icon and overlay widget" - today it doesn't.
- **Where:** `OnboardingWelcomeStepView.swift:40`, `OnboardingCompletionView.swift:38`, `WolfHeroMark.swift:96`.
- **Guideline:** Consistency & Standards (Heuristic #4): internal consistency: the same element should look and behave the same across a product. Also Visual Hierarchy - hierarchy comes from value/saturation contrast *against the background*; a fixed gradient with a dark navy stop recedes on a black background.
- **Evidence:** [Maintain Consistency and Adhere to Standards (Usability Heuristic #4)](https://www.nngroup.com/articles/consistency-and-standards/): internal consistency means reusing the same visual treatment for the same element across screens so users aren't made to wonder whether things mean the same thing. [Visual Hierarchy in UX: Definition](https://www.nngroup.com/articles/visual-hierarchy-ux-definition/): it is the contrast in value and saturation against the surrounding context, not the raw color, that creates emphasis.
- **Fix:**
  - [ ] Decide one identity treatment for the hero mark (see "Logo treatment recommendation" below).
  - [ ] If keeping color, switch from the partner mashup to WolfWave's own `Brand.wolfwaveGradient` and make the stops theme-adaptive (lighten in dark mode, as the navy start `#0A2540` is near-invisible on black).
  - [ ] If going monochrome, use `.mono(.primary)`, which matches the menu-bar template exactly and always passes contrast.

#### 2. Step-title sizing is not consistent across the wizard

- **What:** Titles do not follow one scale. Scaffold steps (Discord, Twitch, OBS, Preferences, Permissions, Notifications) render the title at `DSFont.Size.xl` = **20pt** bold (`OnboardingStepScaffold.swift:42`). Menu Bar Pointer renders its own title at `x2xl` = **22pt** bold (`OnboardingMenuBarPointerStepView.swift:36`). Welcome and Completion use `x3xl` = **26pt** bold. A multi-page wizard should hold the title at one size/position so each step reads as the same kind of screen.
- **Where:** `OnboardingStepScaffold.swift:42`, `OnboardingMenuBarPointerStepView.swift:36`, `OnboardingWelcomeStepView.swift:51`, `OnboardingCompletionView.swift:55`.
- **Guideline:** Consistency & Standards (#4): consistent placement and styling of repeated components (headings, CTAs) across pages of a flow/wizard.
- **Evidence:** [Maintain Consistency and Adhere to Standards (Usability Heuristic #4)](https://www.nngroup.com/articles/consistency-and-standards/): keep repeated elements such as headings and buttons consistent across the pages of a multipage form or wizard.
- **Fix:**
  - [ ] Pick one step-title size for the interior steps and apply it everywhere via the scaffold. 22pt (`x2xl`) matches the app's `.paneTitle()` H1 and respects the DS rule that 26pt is hero-only.
  - [ ] Route Menu Bar Pointer through `OnboardingStepScaffold` (or match its title to the scaffold size) so it stops being a one-off.
  - [ ] Treat Welcome + Completion as the deliberate "hero" bookends at 26pt; that is the one sanctioned use of `x3xl`.

### 🟨 Severity 2 - Minor

#### 3. BrandTile glyph sizes vary with no rule

- **What:** The SF Symbol inside `BrandTile` is sized `x3xl` (26) on Permissions/Preferences/Notifications, but `x2xl` (22) / `xl` (20) elsewhere (`OnboardingPermissionsStepView.swift:41`, `BrandTile.swift:57/65/82`). The tiles are the same size, so the glyph visually jumps step to step.
- **Where:** `BrandTile.swift`, `OnboardingPermissionsStepView.swift:41`, `OnboardingPreferencesStepView.swift:42`, `OnboardingNotificationsStepView.swift:52`.
- **Guideline:** Consistency & Standards (#4).
- **Evidence:** [Maintain Consistency and Adhere to Standards (Usability Heuristic #4)](https://www.nngroup.com/articles/consistency-and-standards/).
- **Fix:**
  - [ ] Set one glyph size as a `BrandTile` default and have callers stop overriding it.

#### 4. Title weight is mixed (bold vs semibold) for peer elements

- **What:** Step titles are `.bold`; the large status/glyph treatments use `.semibold`. NN/g treats weight as a hierarchy signal, so mixing it on same-level elements muddies the ramp.
- **Where:** scaffold `.bold` (`:42`) vs glyph `.semibold` (`:41`).
- **Guideline:** Visual Hierarchy - weight (type contrast) signals importance; reserve it for level changes.
- **Evidence:** [Visual Hierarchy in UX: Definition](https://www.nngroup.com/articles/visual-hierarchy-ux-definition/): heavy weights stand out against regular weights and are a primary tool for signaling importance; use them deliberately.
- **Fix:**
  - [ ] Standardize: titles bold, body regular, secondary labels semibold. Don't vary weight within a level.

#### 5. Too many distinct type sizes in the flow

- **What:** Onboarding uses xs(10), sm(11), body(12), base(13), md(14), lg(17), xl(20), x2xl(22), x3xl(26): nine sizes. NN/g recommends roughly three sizes (header / subheader / body) to keep hierarchy legible.
- **Where:** across all step views.
- **Guideline:** Visual Hierarchy - Scale.
- **Evidence:** [Visual Hierarchy in UX: Definition](https://www.nngroup.com/articles/visual-hierarchy-ux-definition/): use no more than ~3 sizes (small/medium/large) so hierarchical relationships stay clear.
- **Fix:**
  - [ ] Collapse onboarding to a small ramp: title (22), subhead/body (13), caption (11). Drop incidental sizes where they aren't carrying a real level.

### ⬜ Severity 1 - Cosmetic

#### 6. Completion auto-dismisses on a timer

- **What:** `OnboardingCompletionView` calls `onDismiss()` after ~1.5s. Fine as a celebration, but gives no manual "Done" affordance for users who read slowly.
- **Guideline:** User Control & Freedom (#3).
- **Fix:** [ ] Optional: add a tap-to-dismiss / Done button alongside the timer.

#### 7. `cornerRadius: 10` literal in Permissions denied card

- **What:** `OnboardingPermissionsStepView.swift:86` uses a literal `10` instead of `DSRadius.lg`. Minor DS-lint drift.
- **Fix:** [ ] Replace with `DSRadius.lg`.

## Logo treatment recommendation

The user asked: real brand colors, or white/black per theme? Both the menu-bar wolf (template/adaptive) and the dark-mode contrast math point the same way. **The mark must adapt to appearance; a fixed gradient is the one thing to avoid.** Two good directions:

| Option | What | Pros | Cons |
|---|---|---|---|
| **A. Adaptive monochrome** (`.mono(.primary)`) | Black in light, white in dark (identical to the menu-bar template) | Max contrast always; perfect consistency with the tray icon; theme-proof; cleanest | No color/personality on the most brand-forward screen |
| **B. WolfWave brand gradient, theme-adaptive** | Royal-blue brand gradient; lighten stops in dark mode | Keeps brand color on the hero; uses WolfWave's *own* identity, not partners' | Needs a light/dark stop pair; slightly more code |
| C. Keep partner mashup (current) | (no change) | Shows the 3 integrations | Not the app's identity; busy; navy-free so it "works" but reads as random |

**Recommended:** **B for the two hero bookends (Welcome + Completion)** using `Brand.wolfwaveGradient` with adaptive stops, and **A (`.mono(.primary)`) anywhere the mark appears small or inline**, so every non-hero wolf matches the menu bar. This satisfies "real colors" (WolfWave's real brand) *and* "white/black per theme" (adaptive, never sinks into the background). If you'd rather the hero be dead-simple and 100% consistent with the tray icon, pick A everywhere.

Apple HIG backs the adaptive requirement: prefer dynamic/semantic colors and provide treatments that read in both Light and Dark appearances ([Apple HIG: Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode), [Apple HIG: Color](https://developer.apple.com/design/human-interface-guidelines/color)). NN/g: let users live in either mode and keep elements legible in both ([Dark Mode vs. Light Mode](https://www.nngroup.com/articles/dark-mode/)).

## What's working well

- `OnboardingStepScaffold` pins the header at a constant offset across steps. Genuinely good wizard discipline.
- Entrance animations all honor `accessibilityReduceMotion`.
- Copy is short, plain, and on-brand. Privacy line on Welcome sets expectations up front.
- Permissions step has clear granted/denied states with actionable System Settings path.

## Quick wins

- [x] Make the hero mark adaptive (Option B chosen: WolfWave brand gradient, theme-adaptive). `WolfHeroMark.brandGradient` now lightens its stops in Dark.
- [x] Unify interior step titles to 22pt via the scaffold. Menu Bar Pointer already renders 22pt, so all interior titles now match; Welcome/Completion stay 26pt as hero bookends.
- [x] Centralize `BrandTile` glyph sizing: `BrandTile.symbolGlyphFont` (SF Symbols) + `BrandTile.assetGlyphSize` (logo images, 30pt). All 6 call sites migrated; Twitch logo went 28→30 to match siblings.
- [x] Replace the `cornerRadius: 10` literals with `DSRadius.lg` (Permissions denied card).

## Status (2026-06-07)

All findings implemented:

- #1 hero mark: theme-adaptive WolfWave brand gradient.
- #2 step titles: unified to 22pt via scaffold.
- #3 glyph sizing: centralized in `BrandTileGlyph` (`font` + `assetSize`); Twitch logo 28→30.
- #4 weight/labels: section labels routed through `.sectionEyebrow()` (drops legacy ALL-CAPS); BrandTile flattened (white inner-highlight bevel removed, flat-by-default).
- #5 type ramp: body-copy `md(14)`/`body(12)` text folded into `base(13)`. Intentionally kept: menu-bar mock clock (12pt mimics the real menu bar), OBS monospaced URL (code channel), PillButton CTA (control tier).
- #6 Completion: added tap-anywhere-to-dismiss with an idempotent `dismissOnce()` guard so the timer and a tap can't double-fire.
- #7 corner radius: `DSRadius.lg`.

Flow note: Notifications is **not** given a redundant per-step Skip button. Its toggles default off, so "Next" already proceeds without enabling anything. Adding Skip would duplicate Next and break the nav's stated rule (Skip only shown when it differs from Next-with-toggle-off, i.e. Twitch OAuth + Apple Music permission).
