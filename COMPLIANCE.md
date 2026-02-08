# WolfWave — Notarization & DMG Distribution Compliance

Last audited: 2026-02-08
Bundle ID: `com.mrdemonwolf.wolfwave`
Deployment target: macOS 15.6
Distribution: DMG (outside Mac App Store)

---

## Status Overview

| Category | Status | Notes |
|---|---|---|
| Hardened Runtime | PASS | Enabled, all exceptions OFF |
| App Sandbox | PASS | Enabled with scoped entitlements |
| Code Signing (Release) | **NEEDS FIX** | Must use "Developer ID Application" |
| Notarization Workflow | **NEEDS FIX** | Missing from Makefile |
| Info.plist | PASS | All required keys present |
| App Icon | PASS | Present (Xcode auto-generation) |
| Third-Party Dependencies | PASS | Zero — no frameworks, SPM, or pods |
| Build Scripts | PASS | No custom build phase scripts |
| Private API Usage | PASS | None detected |
| Deprecated API Usage | PASS | None detected |
| Credential Security | WARN | Config.xcconfig may be git-tracked |
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
| Release | Apple Development | **Developer ID Application** |

**Action:** Change Release `CODE_SIGN_IDENTITY[sdk=macosx*]` to `"Developer ID Application"` in `project.pbxproj`.

---

## 2. Entitlements

### Release (`wolfwave.entitlements`)

| Entitlement | Value | Justification |
|---|---|---|
| `app-sandbox` | `true` | Required for notarization |
| `network.client` | `true` | Twitch API, WebSocket, iTunes artwork API |
| `automation.apple-events` | `true` | ScriptingBridge to Apple Music |
| `scripting-targets` | `com.apple.Music` | Scoped to Music.app only |
| `keychain-access-groups` | `$(AppIdentifierPrefix)com.mrdemonwolf.wolfwave` | Secure credential storage |
| `temporary-exception.files.absolute-path.read-write` | `/var/folders/` | Discord IPC socket file access |
| `temporary-exception.sbpl` | Unix socket regex | Discord IPC `connect()` on `/private/var/folders/.../T/discord-ipc-[0-9]` |

### Dev (`wolfwave.dev.entitlements`)
Same as Release, plus:
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
| Local Unix socket | IPC | Discord Rich Presence |

All external network traffic uses encrypted transport (HTTPS/WSS).

---

## 5. Dependencies

**Zero external dependencies.** No Swift packages, CocoaPods, Carthage, or embedded frameworks. All functionality uses native Apple frameworks:
- SwiftUI, AppKit, Foundation
- Security (Keychain)
- ScriptingBridge (Apple Music)
- UserNotifications

This eliminates signing/notarization issues from third-party binaries.

---

## 6. DMG Build & Notarization Workflow

### Current (`make prod-build`)
1. Builds Release via `xcodebuild`
2. Copies `.app` to staging directory
3. Creates DMG with `hdiutil`

### Missing steps for notarization
After DMG creation, the Makefile must:
1. Sign the `.app` with Developer ID: `codesign --deep --force --options runtime --sign "Developer ID Application: ..." WolfWave.app`
2. Sign the DMG: `codesign --force --sign "Developer ID Application: ..." WolfWave.dmg`
3. Submit to Apple: `xcrun notarytool submit WolfWave.dmg --apple-id ... --team-id ... --password ... --wait`
4. Staple the ticket: `xcrun stapler staple WolfWave.dmg`

---

## 7. Credential Security

| File | Contains | Risk |
|---|---|---|
| `Config.xcconfig` | `TWITCH_CLIENT_ID`, `DISCORD_CLIENT_ID` | Low (public client IDs, not secrets) |
| `Config.xcconfig.example` | Placeholder values | None |

- `Config.xcconfig` is in `.gitignore` but may have been tracked before the gitignore entry was added
- Both values are public OAuth client IDs (no client secret), not actual secrets
- All sensitive tokens (Twitch OAuth tokens) are stored in Keychain, never in UserDefaults or files

---

## 8. Checklist Before Release

- [ ] Change Release `CODE_SIGN_IDENTITY` to `"Developer ID Application"`
- [ ] Ensure Developer ID certificate is installed in Keychain
- [ ] Add notarization steps to Makefile `prod-build` target
- [ ] Verify `Config.xcconfig` is not tracked in git history with real credentials
- [ ] Test full flow: `make prod-build` -> notarize -> staple -> distribute DMG
- [ ] Verify DMG opens without Gatekeeper warnings on a fresh Mac
- [ ] Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` for release
