# TODO

## CI/CD

- [ ] **Automate Homebrew tap update** — Add a step to `build_release.yml` that clones `MrDemonWolf/homebrew-den`, updates `version`, `sha256`, and `depends_on macos` in `Casks/wolfwave.rb`, and pushes. Requires a `HOMEBREW_TAP_TOKEN` secret (fine-grained PAT with `contents: write` on homebrew-den).

## App Icon

- [ ] **Fix AppIcon.icon not compiling on CI** — The Xcode 16 `.icon` format (SVG-based) produces `AppIcon.icon` (raw folder) instead of `AppIcon.icns` (compiled) on CI runners running macOS 15. Either pre-compile the `.icns` locally and commit it, or migrate to a traditional `AppIcon.appiconset` in `Assets.xcassets` with pre-rendered PNGs for CI compatibility.

## Testing

- [ ] **Add SwiftUI view tests** — SettingsViewTests, OnboardingViewTests, AdvancedSettingsViewTests, GeneralSettingsViewTests
- [ ] **Add integration/E2E tests** — TwitchIntegrationTests, DiscordIntegrationTests, AppLifecycleTests with mock servers
- [ ] **Add protocol-based mocks** — Extract service protocols, create MockTwitchChatService and MockDiscordRPCService
- [ ] **Centralize hardcoded values** — Move window sizes to `AppConstants.Dimensions`, brand colors to `AppConstants.Colors`
