# Release Guide

Step-by-step checklist for publishing a new WolfWave release.

## Pre-Release Checklist

- [ ] All tests pass (`make test`)
- [ ] Build succeeds (`make build`)
- [ ] CHANGELOG.md updated — move [Unreleased] items to versioned section
- [ ] Version bumped in Xcode project (`CFBundleShortVersionString` + `CFBundleVersion`)
- [ ] README.md test count matches actual (`make test` output)
- [ ] No debug code or hardcoded secrets left in source
- [ ] `Config.xcconfig.example` is up to date with any new keys
- [ ] Documentation site builds (`cd docs && bun run build`)
- [ ] Sparkle appcast feed URL configured (if using Sparkle for auto-updates)

## Build & Sign

- [ ] Run `make prod-build` — creates DMG in `builds/`
- [ ] Run `make notarize` — signs DMG, submits to Apple notary, staples ticket
- [ ] Run `make verify-notarize` — confirms notarization succeeded

### Notarization Environment Variables

```bash
APPLE_ID=you@example.com \
APPLE_TEAM_ID=YOUR_TEAM_ID \
APPLE_APP_PASSWORD=xxxx-xxxx-xxxx-xxxx \
make notarize
```

> Generate an app-specific password at [appleid.apple.com](https://appleid.apple.com/account/manage) under **Sign-In and Security > App-Specific Passwords**.

## Release

- [ ] Create git tag: `git tag v<VERSION>`
- [ ] Push tag: `git push origin v<VERSION>`
- [ ] CI creates draft GitHub Release (`.github/workflows/release.yml`)
- [ ] Upload notarized DMG to the GitHub Release
- [ ] Edit release notes (copy from CHANGELOG.md)
- [ ] Publish the release (un-draft)

## Post-Release

- [ ] Verify download works from GitHub Releases page
- [ ] Test fresh install from DMG on a clean machine
- [ ] Deploy docs site (push to `main` triggers GitHub Pages)
- [ ] Announce release (Discord, socials)
- [ ] Update Homebrew cask if applicable

## Required Secrets & Credentials

### Local (for manual builds)

| Credential | Where to get it |
| --- | --- |
| Developer ID Application certificate | Apple Developer portal > Certificates |
| Apple ID | Your Apple Developer account email |
| Apple Team ID | Apple Developer portal > Membership |
| App-specific password | [appleid.apple.com](https://appleid.apple.com) > App-Specific Passwords |

### GitHub Actions (for CI releases)

| Secret | Description |
| --- | --- |
| `DEVELOPER_ID_CERT_P12` | Base64-encoded Developer ID certificate |
| `DEVELOPER_ID_CERT_PASSWORD` | Password for the P12 certificate |
| `APPLE_ID` | Apple Developer account email |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `APPLE_APP_PASSWORD` | App-specific password for notarization |
| `TWITCH_CLIENT_ID` | Twitch application Client ID |
| `DISCORD_CLIENT_ID` | Discord application ID |

> `GITHUB_TOKEN` is provided automatically by GitHub Actions.

## Troubleshooting

### Certificate expired or missing

- Open Keychain Access and check for a valid "Developer ID Application" certificate
- Re-download from [Apple Developer portal](https://developer.apple.com/account/resources/certificates/list) if expired
- For CI, re-export the P12 and update the `DEVELOPER_ID_CERT_P12` secret

### Notarization rejected

- Run `xcrun notarytool log <submission-id>` to see rejection details
- Common causes: unsigned frameworks, hardened runtime not enabled, missing entitlements
- Ensure `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` is set for release builds

### CI workflow fails

- Check that all required secrets are configured in repo Settings > Secrets
- Verify the tag matches the `v*` pattern (e.g., `v1.2.0`)
- Review the Actions log for specific build or signing errors

### DMG won't open on other machines

- Verify notarization: `make verify-notarize`
- Check stapling: `xcrun stapler validate builds/WolfWave-*.dmg`
- If Gatekeeper still blocks, the DMG may not be properly stapled — re-run `xcrun stapler staple`
