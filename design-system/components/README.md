# Component Catalog

One markdown entry per reusable view. Stubs marked `(stub)` need filling in as we touch each component.

## Shared (`apps/native/wolfwave/Views/Shared/`)

| Component | File | Status |
|---|---|---|
| StatusChip | [status-chip.md](status-chip.md) | drafted |
| InfoRow | [info-row.md](info-row.md) | drafted |
| ToggleSettingRow | [toggle-setting-row.md](toggle-setting-row.md) | stub |
| SuccessFeedbackRow | [success-feedback-row.md](success-feedback-row.md) | stub |
| SectionHeaderWithStatus | [section-header-with-status.md](section-header-with-status.md) | stub |
| NowPlayingHeroCard | [now-playing-hero-card.md](now-playing-hero-card.md) | stub |
| AlbumArtView | [album-art-view.md](album-art-view.md) | stub |
| IntegrationDashboardView | [integration-dashboard-view.md](integration-dashboard-view.md) | stub |
| ConnectionTestButton | [connection-test-button.md](connection-test-button.md) | stub |
| ConfigRequiredBanner | [config-required-banner.md](config-required-banner.md) | stub |
| CopyButton | [copy-button.md](copy-button.md) | stub |
| UpdateBannerView | [update-banner-view.md](update-banner-view.md) | stub |
| WhatsNewView | [whats-new-view.md](whats-new-view.md) | stub |
| TwitchGlitchShape | [twitch-glitch-shape.md](twitch-glitch-shape.md) | stub |
| ViewModifiers (cardStyle, interactiveRow, …) | [view-modifiers.md](view-modifiers.md) | drafted |

## Onboarding (`apps/native/wolfwave/Views/Onboarding/Components/`)

| Component | File | Status |
|---|---|---|
| PillButton | [pill-button.md](pill-button.md) | stub |
| BrandTile | [brand-tile.md](brand-tile.md) | stub |

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
