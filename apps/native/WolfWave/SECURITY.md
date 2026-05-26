# 🔒 Security & Configuration Guide

## ⚠️ CRITICAL: API Key Management

### First-Time Setup

1. **Copy the configuration template:**
   ```bash
   cp Config.xcconfig.example Config.xcconfig
   ```

2. **Fill in your API keys** in `Config.xcconfig`:
   - **Twitch Client ID**: Get from https://dev.twitch.tv/console/apps
   - **Discord Application ID**: Get from https://discord.com/developers/applications
   - **GitHub Repository**: Set your fork's owner and repo name

3. **Verify `.gitignore`** includes `Config.xcconfig`:
   ```bash
   git check-ignore Config.xcconfig
   # Should output: Config.xcconfig
   ```

### ⚠️ What NOT to Do

❌ **NEVER commit `Config.xcconfig` with real API keys**
❌ **NEVER share your Client IDs publicly** (GitHub, Discord, forums)
❌ **NEVER hardcode API keys** in source files

### ✅ What TO Do

✅ **Use `Config.xcconfig.example`** as a template for contributors
✅ **Store real keys** only in your local `Config.xcconfig` (gitignored)
✅ **Rotate keys immediately** if accidentally exposed
✅ **Use environment variables** for CI/CD pipelines

---

## 🔐 Keychain Security

WolfWave stores OAuth tokens securely in the macOS Keychain:

- **Service**: `com.mrdemonwolf.wolfwave`
- **Account**: User-specific (Twitch username)
- **Access**: Protected by macOS Keychain Access Control

### Clearing Tokens

Tokens are automatically cleared when you:
- Sign out in Settings → Twitch → Disconnect
- Reset all settings in Settings → Advanced → Reset All

Manual clearing (for debugging):
```bash
security delete-generic-password -s "com.mrdemonwolf.wolfwave" -a "YOUR_TWITCH_USERNAME"
```

---

## 🛡️ App Sandbox

WolfWave runs in the **macOS App Sandbox** with these entitlements:

- ✅ **Network (Client)**: Required for Twitch/Discord/API calls
- ✅ **User Selected Files (Read/Write)**: For log export
- ✅ **Apple Music Access**: Via MusicKit entitlement

### Why Sandbox Matters

The App Sandbox restricts what the app can access:
- **Cannot** read files outside its container (except user-selected)
- **Cannot** access other apps' data
- **Cannot** execute arbitrary code

This protects you even if a dependency is compromised.

---

## 🔑 API Key Rotation

### If You Accidentally Commit Keys

**Act immediately:**

1. **Twitch Client ID:**
   - Go to https://dev.twitch.tv/console/apps
   - Delete the compromised application
   - Create a new application with a new Client ID
   - Update `Config.xcconfig` with the new ID

2. **Discord Application ID:**
   - Go to https://discord.com/developers/applications
   - Delete the compromised application
   - Create a new application with a new ID
   - Update `Config.xcconfig` with the new ID

3. **Git History Cleanup:**
   ```bash
   # Remove from current commit
   git rm --cached Config.xcconfig
   git commit --amend -m "Remove accidentally committed credentials"
   
   # Force push (if already pushed)
   git push --force
   
   # For complete removal from history, use git-filter-repo:
   # https://github.com/newren/git-filter-repo
   ```

4. **GitHub Security:**
   - Check GitHub's secret scanning alerts
   - Verify no forks exist with your keys

---

## 🔍 Security Audit Checklist

### Before Every Commit

- [ ] `Config.xcconfig` is NOT in staging area
- [ ] No API keys in source files
- [ ] No OAuth tokens in test fixtures
- [ ] `.gitignore` is up to date

### Before Every Release

- [ ] All dependencies up to date
- [ ] No DEBUG code paths in Release build
- [ ] Code signing certificate valid
- [ ] Sparkle update feed uses HTTPS
- [ ] All API endpoints use HTTPS

### Periodic Review

- [ ] Rotate API keys every 6–12 months
- [ ] Audit Keychain entries
- [ ] Review third-party dependencies for vulnerabilities
- [ ] Check for leaked credentials on GitHub

---

## 🚨 Reporting Security Issues

**Do NOT open a public GitHub issue for security vulnerabilities.**

Instead:
1. Email security concerns to: [your-email@domain.com]
2. Use GitHub's private security advisories feature
3. Allow 90 days for responsible disclosure

---

## 📚 Additional Resources

- [OWASP API Security](https://owasp.org/www-project-api-security/)
- [Apple Security Best Practices](https://developer.apple.com/documentation/security)
- [Twitch Security Guidelines](https://dev.twitch.tv/docs/authentication/security)
- [Discord Security](https://discord.com/developers/docs/topics/oauth2#security)

---

**Last Updated**: 2026-05-22  
**Maintained By**: WolfWave Security Team
