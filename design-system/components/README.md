# Component Catalog

One markdown entry per reusable view. Stubs marked `(stub)` need filling in as we touch each component.

## Shared (`apps/native/wolfwave/Views/Shared/`)

| Component | File | Status |
|---|---|---|
| StatusChip | [status-chip.md](status-chip.md) | drafted |
| InfoRow | [info-row.md](info-row.md) | drafted |
| ToggleSettingRow | [toggle-setting-row.md](toggle-setting-row.md) | drafted |
| SuccessFeedbackRow | [success-feedback-row.md](success-feedback-row.md) | drafted |
| SectionHeaderWithStatus | [section-header-with-status.md](section-header-with-status.md) | drafted |
| NowPlayingHeroCard | [now-playing-hero-card.md](now-playing-hero-card.md) | drafted |
| AlbumArtView | [album-art-view.md](album-art-view.md) | drafted |
| IntegrationDashboardView | [integration-dashboard-view.md](integration-dashboard-view.md) | drafted |
| ConnectionTestButton | [connection-test-button.md](connection-test-button.md) | drafted |
| ConfigRequiredBanner | [config-required-banner.md](config-required-banner.md) | drafted |
| MusicPermissionBanner | [music-permission-banner.md](music-permission-banner.md) | drafted |
| CopyButton | [copy-button.md](copy-button.md) | drafted |
| DSIconButton | [ds-icon-button.md](ds-icon-button.md) | drafted |
| WarningBanner | [warning-banner.md](warning-banner.md) | drafted |
| LoadingRow | [loading-row.md](loading-row.md) | drafted |
| ActionGrid | [action-grid.md](action-grid.md) | drafted |
| UpdateBannerView | [update-banner-view.md](update-banner-view.md) | drafted |
| WhatsNewView | [whats-new-view.md](whats-new-view.md) | drafted |
| AboutView | [about-view.md](about-view.md) | drafted |
| TwitchGlitchShape | [twitch-glitch-shape.md](twitch-glitch-shape.md) | drafted |
| ViewModifiers (cardStyle, interactiveRow, …) | [view-modifiers.md](view-modifiers.md) | drafted |

## History (`apps/native/wolfwave/Views/HistoryStats/`)

| Component | File | Status |
|---|---|---|
| MonthlyWrapCard | [monthly-wrap-card.md](monthly-wrap-card.md) | drafted |

## Onboarding (`apps/native/wolfwave/Views/Onboarding/Components/`)

| Component | File | Status |
|---|---|---|
| PillButton | [pill-button.md](pill-button.md) | drafted |
| BrandTile | [brand-tile.md](brand-tile.md) | drafted |
| WolfHeroMark | [wolf-hero-mark.md](wolf-hero-mark.md) | drafted |

## Catalog entry template

```markdown
# <ComponentName>

**File:** `apps/native/wolfwave/Views/Shared/<ComponentName>.swift`

## Purpose
One sentence — what problem it solves.

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
