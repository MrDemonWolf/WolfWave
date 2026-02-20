# WolfWave — Notarization & DMG Distribution Compliance

Last audited: 2026-02-20
Bundle ID: `com.mrdemonwolf.wolfwave`
Deployment target: macOS 15.6
Distribution: DMG (outside Mac App Store)

---

## Status Overview

| Category | Status | Notes |
|---|---|---|
| Hardened Runtime | PASS | Enabled, all exceptions OFF |
| App Sandbox | PASS | Enabled with scoped entitlements |
| Code Signing (Release) | PASS | Xcode + GitHub Actions sign with Developer ID Application |
| Notarization Workflow | PASS | `make notarize` + `release.yml` automated pipeline |
| Info.plist | PASS | All required keys present |
| App Icon | PASS | Present (Xcode auto-generation) |
| Third-Party Dependencies | PASS | Zero native dependencies — widget loads Google Fonts via CDN |
| Build Scripts | PASS | No custom build phase scripts |
| Private API Usage | PASS | None detected |
| Deprecated API Usage | PASS | None detected |
| Credential Security | PASS | Not tracked in git; `.gitignore` entry confirmed |
| Network Security | PASS | All external traffic HTTPS/WSS |

---

## 1. Code Signing

### Hardened Runtime
- `ENABLE_HARDENED_RUNTIME = YES` in both Debug and Release
- All runtime exceptions explicitly set to `NO`:
  - `RUNTIME_EXCEPTION_ALLOW_DYLD_ENVIRONMENT_VARIABLES = NO`
  - `RUNTIME_EXCEPTION_ALLOW_JIT = NO`
  - `RUNTIME_EXCEPTION_ALLOW_UNSIGNED_EXECUTABLE_MEMORY = NO`
  - `RUNTIME_EXCEPTION_DEBUGGING_TOOL = NO`
  - `RUNTIME_EXCEPTION_DISABLE_EXECUTABLE_PAGE_PROTECTION = NO`
  - `RUNTIME_EXCEPTION_DISABLE_LIBRARY_VALIDATION = NO`

### Signing Identity
| Config | Current | Required |
|---|---|---|
| Debug | Apple Development | Apple Development (OK) |
| Release | Developer ID Application | Developer ID Application (OK) |

Release builds are signed via Xcode (local) and GitHub Actions `release.yml` (CI), which imports the Developer ID certificate from repository secrets.

---

## 2. Entitlements

### Release (`wolfwave.entitlements`)

| Entitlement | Value | Justification |
|---|---|---|
| `app-sandbox` | `true` | Required for notarization |
| `network.client` | `true` | Twitch API, WebSocket, iTunes artwork API |
| `automation.apple-events` | `true` | ScriptingBridge to Apple Music |
| `scripting-targets` | `com.apple.Music` | Scoped to Music.app only |
| `network.server` | `true` | Local WebSocket server for stream overlay |
| `keychain-access-groups` | `$(AppIdentifierPrefix)com.mrdemonwolf.wolfwave` | Secure credential storage |
| `temporary-exception.files.absolute-path.read-write` | `/var/folders/` | Discord IPC socket file access |
| `temporary-exception.sbpl` | Unix socket regex | Discord IPC `connect()` on `/private/var/folders/.../T/discord-ipc-[0-9]` |

### Dev (`wolfwave.dev.entitlements`)
Same as Release (including `network.server`), plus:
| Entitlement | Value | Justification |
|---|---|---|
| `temporary-exception.apple-events` | `com.apple.Music` | Dev-only: broader AppleScript access |

### Notes
- The `temporary-exception.files` and `temporary-exception.sbpl` entitlements are required for Discord Rich Presence IPC socket access from within the sandbox. These will pass notarization (notarytool checks malware + signing, not entitlement scope). They would be rejected for Mac App Store submission.
- The `/var/folders/` file path exception is broad. Narrowing is not feasible with the temporary-exception format since Discord's IPC socket path contains a user-specific hash.

---

## 3. Info.plist

| Key | Present | Value |
|---|---|---|
| `CFBundleDisplayName` | Yes | "WolfWave" |
| `CFBundleIdentifier` | Yes | `com.mrdemonwolf.wolfwave` |
| `CFBundleVersion` | Yes | 1 |
| `CFBundleShortVersionString` | Yes | 1.0 |
| `LSApplicationCategoryType` | Yes | `public.app-category.music` |
| `NSAppleEventsUsageDescription` | Yes | Explains Music.app access |
| `NSAppleMusicUsageDescription` | Yes | Explains Apple Music access |
| `NSHumanReadableCopyright` | Yes | Present |
| `LSUIElement` | Yes | `NO` in Release (shows in dock) |

---

## 4. Source Code Audit

### No private API usage
All APIs are public Apple frameworks or POSIX/Darwin system calls.

### Low-level APIs used (all legitimate)
| API | File | Purpose |
|---|---|---|
| `sysctl(KERN_PROCARGS2)` | `DiscordRPCService.swift` | Read Discord's TMPDIR from process env |
| `confstr(_CS_DARWIN_USER_TEMP_DIR)` | `DiscordRPCService.swift` | Fallback temp dir resolution |
| `socket(AF_UNIX)` / `connect()` | `DiscordRPCService.swift` | Discord IPC socket connection |
| `Darwin.read()` / `Darwin.write()` | `DiscordRPCService.swift` | IPC frame I/O |

### No deprecated APIs
All `#available` checks are forward-compatibility guards for newer macOS features.

### No dynamic loading
No `dlopen`, `dlsym`, `NSBundle.load`, or similar dynamic library loading.

### No external process spawning
No `Process`, `NSTask`, or `posix_spawn` usage.

### Network endpoints
| Endpoint | Protocol | Purpose |
|---|---|---|
| `api.twitch.tv/helix` | HTTPS | Twitch Helix API |
| `id.twitch.tv/oauth2` | HTTPS | Twitch OAuth (Device Code flow) |
| `eventsub.wss.twitch.tv/ws` | WSS | Twitch EventSub WebSocket |
| `itunes.apple.com/search` | HTTPS | Album artwork for Discord Rich Presence |
| `api.github.com/repos/.../releases/latest` | HTTPS | Automatic update checker |
| Local Unix socket | IPC | Discord Rich Presence |
| `localhost:{port}` | WebSocket | Stream overlay server (local only) |
| `fonts.googleapis.com/css2` | HTTPS | Google Fonts for OBS widget (browser-side only, not native app) |

All external network traffic uses encrypted transport (HTTPS/WSS).

**Note:** The Google Fonts CDN request originates from the browser-based OBS widget (`docs/app/widget/`), not from the native macOS app binary. It has no impact on the native app's sandbox or notarization.

---

## 5. Dependencies

**Zero native dependencies.** No Swift packages, CocoaPods, Carthage, or embedded frameworks. All functionality uses native Apple frameworks:
- SwiftUI, AppKit, Foundation
- Security (Keychain)
- ScriptingBridge (Apple Music)
- Network (WebSocket server via `NWListener`)
- UserNotifications

This eliminates signing/notarization issues from third-party binaries.

**Browser-side dependencies (OBS widget only):**
- Google Fonts CSS API (`fonts.googleapis.com`) — loaded dynamically in the browser-based stream overlay. This runs in OBS Browser Source (Chromium), not in the native app. Requires internet for first load; Chromium caches fonts locally after that.

---

## 6. DMG Build & Notarization Workflow

### `make prod-build`
1. Builds Release via `xcodebuild` (signed with Developer ID Application)
2. Copies `.app` to staging directory
3. Creates DMG with `hdiutil`
4. Optionally re-signs DMG with Developer ID if certificate is found

### `make notarize`
1. Signs the DMG with Developer ID Application
2. Submits to Apple via `xcrun notarytool submit` (requires `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` env vars)
3. Waits for notarization to complete
4. Staples the notarization ticket to the DMG

### GitHub Actions (`release.yml`)
Automates the full pipeline on tag push (`v*`):
1. Imports Developer ID certificate from repository secrets
2. Builds, signs, notarizes, and staples the DMG
3. Creates a GitHub Release with the notarized DMG attached

---

## 7. Credential Security

| File | Contains | Risk |
|---|---|---|
| `Config.xcconfig` | `TWITCH_CLIENT_ID`, `DISCORD_CLIENT_ID` | None (public client IDs, not secrets) |
| `Config.xcconfig.example` | Placeholder values | None |

- `Config.xcconfig` is in `.gitignore` and has never been committed to git
- Both values are public OAuth client IDs (no client secret), not actual secrets
- All sensitive tokens (Twitch OAuth tokens) are stored in Keychain, never in UserDefaults or files

---

## 8. Apple Notarization Rules (Self-Signing for DMG Distribution)

### What Notarization Requires

Apple notarization is mandatory for all Developer ID-signed software distributed outside the Mac App Store. The `notarytool` service performs an automated scan and requires:

1. **Developer ID Application certificate** — Issued by Apple via your Developer Program membership. Used to sign the `.app` bundle.
2. **Hardened Runtime** — Must be enabled (`ENABLE_HARDENED_RUNTIME = YES`). This enforces code integrity protections (no unsigned memory, no DYLD injection, etc.).
3. **Secure timestamp** — The signing must include a secure timestamp from Apple's timestamp server (Xcode adds this automatically with `--timestamp`).
4. **No malware indicators** — Apple's automated scan checks for known malware patterns, suspicious API usage, and unsigned embedded binaries.

### What Notarization Does NOT Check

- **Entitlement scope** — Temporary exception entitlements (`temporary-exception.files`, `temporary-exception.sbpl`) pass notarization. Apple only rejects overly broad entitlements for Mac App Store review, not for notarization.
- **App Store Guidelines** — Notarization is not App Store review. It does not evaluate UI guidelines, business model, or content policies.
- **Privacy Manifest completeness** — Privacy manifests are required for App Store submissions and certain SDK categories, but notarization does not reject for missing manifests.

### WolfWave's Notarization Posture

| Requirement | Status | Details |
|---|---|---|
| Developer ID signing | PASS | Release config uses "Developer ID Application" |
| Hardened Runtime | PASS | Enabled with all runtime exceptions OFF |
| Secure timestamp | PASS | Xcode and `codesign --timestamp` in CI |
| No embedded frameworks | PASS | Zero third-party dependencies |
| Temporary exception entitlements | PASS | Discord IPC socket access — passes notarization, would fail Mac App Store review |
| `notarytool submit` workflow | PASS | Automated in `make notarize` and `release.yml` |
| DMG stapling | PASS | `xcrun stapler staple` runs after notarization |

### Key Points for Self-Signed DMG Distribution

- **`altool` is deprecated** — Apple requires `notarytool` (available since Xcode 13). WolfWave's Makefile and CI already use `notarytool`.
- **Stapling is important** — After notarization, the ticket must be stapled to the DMG so Gatekeeper can verify offline. WolfWave's pipeline handles this.
- **Temporary exceptions are fine** — The `temporary-exception.files.absolute-path.read-write` and `temporary-exception.sbpl` entitlements for Discord IPC will pass notarization. They are specifically designed for legitimate use cases that can't be addressed with standard sandbox entitlements.
- **No App Store submission planned** — If WolfWave were to submit to the Mac App Store, the temporary exception entitlements would need to be replaced (Apple would reject them in App Review). The Discord IPC approach would need an alternative like XPC or App Groups.

---

## 9. Checklist Before Release

- [x] Code signing identity set to Developer ID Application (Xcode + `release.yml`)
- [x] Notarization steps in Makefile (`make notarize` target)
- [x] `Config.xcconfig` verified not tracked in git
- [ ] Ensure Developer ID certificate is installed in Keychain
- [ ] Test full flow: `make prod-build` → `make notarize` → distribute DMG
- [ ] Verify DMG opens without Gatekeeper warnings on a fresh Mac
- [ ] Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` for release
