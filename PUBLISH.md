# Publishing Guide — WolfWave v1.0.0

Steps to build, sign, notarize, and distribute the v1.0.0 release.

## Prerequisites

- Xcode 16+ with command-line tools installed
- Active Apple Developer Program membership
- Developer ID Application certificate installed in Keychain
- `Config.xcconfig` populated with `TWITCH_CLIENT_ID` and `DISCORD_CLIENT_ID`

## 1. Code Signing

The `make prod-build` target automatically re-signs with **Developer ID Application** if the certificate is present. Verify your signing identity:

```bash
security find-identity -v -p codesigning
```

Ensure `--options runtime` (hardened runtime) is enabled — required for notarization.

## 2. Build the DMG

```bash
make prod-build
```

Produces `builds/WolfWave-1.0.0-arm64.dmg` containing the signed `.app` bundle.

## 3. Notarize

```bash
make notarize
```

Required environment variables (also used by CI):
- `APPLE_ID` — Your Apple ID email
- `APPLE_TEAM_ID` — 10-character team identifier
- `APPLE_APP_PASSWORD` — App-specific password from appleid.apple.com

Verify notarization after completion:

```bash
make verify-notarize
```

## 4. Create GitHub Release

Tag and push:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The `release.yml` workflow will automatically:
- Build and sign the app
- Notarize the DMG
- Create a GitHub Release with the DMG attached

Alternatively, create the release manually:

```bash
gh release create v1.0.0 builds/WolfWave-1.0.0-arm64.dmg \
  --title "WolfWave v1.0.0" \
  --notes-file CHANGELOG.md
```

## 5. Update Appcast XML

Sparkle checks `SUFeedURL` for updates. After the release:

1. Generate the appcast entry with Sparkle's `generate_appcast` tool or manually update `appcast.xml`
2. Include the DMG URL, version, file size, and Ed25519 signature
3. Upload `appcast.xml` as a release asset so it is available at:
   ```
   https://github.com/MrDemonWolf/wolfwave/releases/latest/download/appcast.xml
   ```

## 6. Homebrew Cask (Optional)

To submit a Homebrew cask:

1. Fork [homebrew-cask](https://github.com/Homebrew/homebrew-cask)
2. Create `Casks/w/wolfwave.rb` with the DMG URL, SHA-256, and app name
3. Open a pull request against `homebrew-cask`

Requires the DMG to be notarized and publicly downloadable.

## 7. Documentation Site

The docs site (Fumadocs / Next.js) lives in `docs/`. Deploy to GitHub Pages:

```bash
cd docs
npm install && npm run build
```

Ensure the GitHub Pages source is set to the `gh-pages` branch or GitHub Actions output. Update any version references in the docs content (`docs/content/docs/`) to reflect v1.0.0.

## CI/CD Secrets Reference

The following repository secrets must be configured for automated releases:

| Secret | Purpose |
|--------|---------|
| `DEVELOPER_ID_CERT_P12` | Base64-encoded Developer ID certificate |
| `DEVELOPER_ID_CERT_PASSWORD` | Certificate password |
| `APPLE_ID` | Apple ID for notarization |
| `APPLE_TEAM_ID` | Apple Developer team ID |
| `APPLE_APP_PASSWORD` | App-specific password |
| `TWITCH_CLIENT_ID` | Twitch application client ID |
| `DISCORD_CLIENT_ID` | Discord application client ID |
