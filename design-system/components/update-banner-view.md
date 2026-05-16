# UpdateBannerView

**File:** [`apps/native/wolfwave/Views/Shared/UpdateBannerView.swift`](../../apps/native/wolfwave/Views/Shared/UpdateBannerView.swift)

## Purpose
Gradient banner shown in Settings when Sparkle has detected a newer version. Self-listening — call `.listening()` to wire it to `updateStateChanged` notifications and forget it.

## API
```swift
UpdateBannerView().listening()
```

No init parameters. The banner observes `NotificationCenter` for `AppConstants.Notifications.updateStateChanged` posts:

```swift
NotificationCenter.default.post(
    name: NSNotification.Name(AppConstants.Notifications.updateStateChanged),
    object: nil,
    userInfo: [
        "isUpdateAvailable": true,
        "latestVersion": "1.2.0",
        "releaseURL": "https://github.com/.../releases/tag/v1.2.0"
    ]
)
```

| userInfo key | Type | Notes |
|---|---|---|
| `isUpdateAvailable` | `Bool` | Required. False hides the banner. |
| `latestVersion` | `String` | Required. Rendered as "WolfWave v\(version) is ready to download." |
| `releaseURL` | `String?` | Optional. Falls back to `AppConstants.URLs.githubReleases`. |

## Tokens used
- `DSColor.brand500` (`#0A84FF`) → purple `LinearGradient` — banner background (currently `.blue` → `.purple` literals; align to brand on next pass)
- `DSFont.Size.body` (12) `.semibold` — title `"Update Available"`
- `DSFont.Size.sm` (11) `.white@85%` — body line
- `DSRadius.lg` (10) — clip shape
- `.move(edge: .top).combined(with: .opacity)` — entry transition

## Anatomy
```mermaid
graph LR
  Banner[HStack spacing 10 padding 14×10 .clipShape] --> Icon[arrow.down.circle.fill — 16pt white]
  Banner --> Text[VStack spacing 2]
  Text --> Title[Text — Update Available 12 semibold]
  Text --> Body[Text — WolfWave v… ready to download 11]
  Banner --> Spacer
  Banner --> Download[Button — .bordered .tint white .small]
  Banner --> Dismiss[Button — xmark 10 semibold plain]
```

## Accessibility
- Download button has `accessibilityHint("Downloads the latest version of WolfWave")`.
- Dismiss button has `accessibilityLabel("Dismiss update banner")`.
- User-dismissed via `isDismissed` local state — re-posted notifications with `isUpdateAvailable: false` also hide it.

## Do / Don't
- ✅ Place at the top of the Settings shell (above the section header for the active tab).
- ✅ Always call `.listening()` — without it the view never sees the notification and stays hidden.
- ❌ Don't trigger the notification from app code outside `SparkleUpdaterService` — that's the contract.
- ❌ Don't render multiple banners; this is a singleton-by-convention UI element.

## Example
```swift
VStack(spacing: 16) {
    UpdateBannerView().listening()
    SettingsContent()
}
```
