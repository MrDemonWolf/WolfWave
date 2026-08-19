# Component Catalog

One markdown entry per reusable view. Every entry follows the template at the bottom of
this file; [`status-chip.md`](status-chip.md) is the quality bar.

Two entries document a type that is nested inside a larger file rather than living in its
own: `SectionEyebrow` (declared in `ViewModifiers.swift`) and `MonthlyWrapCard` (declared
in `MonthlyWrapView.swift`). They are grouped by the directory they belong to.

## Shared (`apps/native/WolfWave/Views/Shared/`)

| Component | File |
|---|---|
| StatusChip | [status-chip.md](status-chip.md) |
| InfoRow | [info-row.md](info-row.md) |
| ToggleSettingRow | [toggle-setting-row.md](toggle-setting-row.md) |
| CommandSettingRow | [command-setting-row.md](command-setting-row.md) |
| CommandAliasField | [command-alias-field.md](command-alias-field.md) |
| LabeledSlider | [labeled-slider.md](labeled-slider.md) |
| CooldownSliderPair | [cooldown-slider-pair.md](cooldown-slider-pair.md) |
| Binding+Sanitized | [binding-sanitized.md](binding-sanitized.md) |
| SuccessFeedbackRow | [success-feedback-row.md](success-feedback-row.md) |
| SectionHeaderWithStatus | [section-header-with-status.md](section-header-with-status.md) |
| NowPlayingHeroCard | [now-playing-hero-card.md](now-playing-hero-card.md) |
| AlbumArtView | [album-art-view.md](album-art-view.md) |
| IntegrationDashboardView | [integration-dashboard-view.md](integration-dashboard-view.md) |
| MusicPermissionBanner | [music-permission-banner.md](music-permission-banner.md) |
| AsyncActionButton | [async-action-button.md](async-action-button.md) |
| CopyButton | [copy-button.md](copy-button.md) |
| CopyableURLRow | [copyable-url-row.md](copyable-url-row.md) |
| OpenInBrowserButton | [open-in-browser-button.md](open-in-browser-button.md) |
| SharePickerButton | [share-picker-button.md](share-picker-button.md) |
| DSIconButton | [ds-icon-button.md](ds-icon-button.md) |
| CalloutBanner | [callout-banner.md](callout-banner.md) |
| ErrorCallout | [error-callout.md](error-callout.md) |
| FieldValidationRow | [field-validation-row.md](field-validation-row.md) |
| TwitchConnectionNotice | [twitch-connection-notice.md](twitch-connection-notice.md) |
| HintRow | [hint-row.md](hint-row.md) |
| LoadingRow | [loading-row.md](loading-row.md) |
| ActionGrid | [action-grid.md](action-grid.md) |
| UpdateBannerView | [update-banner-view.md](update-banner-view.md) |
| WhatsNewView | [whats-new-view.md](whats-new-view.md) |
| TwitchGlitchShape | [twitch-glitch-shape.md](twitch-glitch-shape.md) |
| ViewModifiers (cardStyle, subtleCardShell, heading ramp, …) | [view-modifiers.md](view-modifiers.md) |
| StreamerModeBadge | [streamer-mode-badge.md](streamer-mode-badge.md) |
| ResponsiveRow | [responsive-row.md](responsive-row.md) |
| SettingsNavRail | [settings-nav-rail.md](settings-nav-rail.md) |
| CardEyebrowHeader | [card-eyebrow-header.md](card-eyebrow-header.md) |
| DestructiveButton | [destructive-button.md](destructive-button.md) |
| SectionEyebrow | [section-eyebrow.md](section-eyebrow.md) |
| StatTile | [stat-tile.md](stat-tile.md) |
| QRCodeImage | [qr-code-image.md](qr-code-image.md) |

## History (`apps/native/WolfWave/Views/HistoryStats/`)

| Component | File |
|---|---|
| MonthlyWrapCard | [monthly-wrap-card.md](monthly-wrap-card.md) |

## Onboarding (`apps/native/WolfWave/Views/Onboarding/Components/`)

| Component | File |
|---|---|
| PillButton | [pill-button.md](pill-button.md) |
| BrandTile | [brand-tile.md](brand-tile.md) |
| WolfHeroMark | [wolf-hero-mark.md](wolf-hero-mark.md) |
| OnboardingStepScaffold | [onboarding-step-scaffold.md](onboarding-step-scaffold.md) |
| OnboardingToggleCard | [onboarding-toggle-card.md](onboarding-toggle-card.md) |

## Catalog entry template

```markdown
# <ComponentName>

**File:** `apps/native/WolfWave/Views/Shared/<ComponentName>.swift`

## Purpose
One sentence: what problem it solves.

## API
```swift
<init signature>
```

## Tokens used
- `DSColor.<…>`
- `DSFont.Size.<…>`
- `DSSpace.<…>`
- `DSRadius.<…>`

## Anatomy
```mermaid
graph LR
  …
```

## Accessibility
- VoiceOver label expectations
- Dynamic Type behavior
- Hover/focus states

## Do / Don't
- ✅ Use inside `Form` rows.
- ❌ Don't nest inside another `<ComponentName>`.

## Example
```swift
ComponentName(...)
```
```
