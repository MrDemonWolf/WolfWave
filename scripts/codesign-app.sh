#!/usr/bin/env bash
#
# Sign a built WolfWave.app inside-out with the Developer ID identity.
#
# Never use --deep. --deep re-signs nested bundles but attaches NO per-bundle
# entitlements, which strips a sandboxed helper's grant (Sparkle's updater apps,
# or a future .xpc that needs network.server). We sign the deepest nested code
# first, then the outer app, so each bundle's seal stays valid.
#
# Env:
#   SIGN_IDENTITY             codesign identity (default "Developer ID Application")
#   PROVISIONING_PROFILE_B64  optional base64 Developer ID provisioning profile
#                             with the iCloud capability. When set, it is embedded
#                             and the iCloud KVS entitlement is added so
#                             "Sync with iCloud" works in the shipped build.
#                             Unset: no profile, no iCloud key, sync stays inert.
#
# Usage: scripts/codesign-app.sh <app-bundle> [entitlements-plist]

set -euo pipefail

app_path="${1:?usage: codesign-app.sh <app-bundle> [entitlements-plist]}"
entitlements="${2:-apps/native/WolfWave/WolfWave.entitlements}"
identity="${SIGN_IDENTITY:-Developer ID Application}"

if [ ! -d "$app_path" ]; then
  echo "::error::App bundle not found at $app_path" >&2
  exit 1
fi
if [ ! -f "$entitlements" ]; then
  echo "::error::Entitlements file not found at $entitlements" >&2
  exit 1
fi

# 0. Optional iCloud: embed the profile and extend the entitlements. The key is
#    not in the committed plist because Xcode refuses to build a target that
#    carries it without a matching profile, which would break every local and
#    CI build that has none.
if [ -n "${PROVISIONING_PROFILE_B64:-}" ]; then
  profile="$(mktemp -t wolfwave-profile).provisionprofile"
  echo "$PROVISIONING_PROFILE_B64" | base64 --decode > "$profile"
  team_id="$(security cms -D -i "$profile" | plutil -extract TeamIdentifier.0 raw -)"
  cp "$profile" "$app_path/Contents/embedded.provisionprofile"
  icloud_entitlements="$(mktemp -t wolfwave-entitlements).plist"
  cp "$entitlements" "$icloud_entitlements"
  /usr/libexec/PlistBuddy -c \
    "Add :com.apple.developer.ubiquity-kvstore-identifier string ${team_id}.com.mrdemonwolf.wolfwave" \
    "$icloud_entitlements"
  entitlements="$icloud_entitlements"
  echo "Embedded provisioning profile (team $team_id) and enabled iCloud KVS entitlement"
fi

# 1. Nested code (frameworks, XPC services, helper apps, dylibs), deepest path
#    first. --preserve-metadata=entitlements keeps each bundle's own
#    entitlements from the xcodebuild signature instead of dropping them.
#
#    "Autoupdate" is Sparkle's bare, extension-less helper tool
#    (Sparkle.framework/Versions/B/Autoupdate). The name globs miss it, so it
#    kept xcodebuild's ad-hoc signature (no Developer ID, no secure timestamp)
#    and was the sole binary failing notarization (statusCode 4000). Match it by
#    name; -type f skips the framework's Autoupdate symlink so the real Mach-O
#    signs exactly once.
find "$app_path/Contents" \
  \( -name "*.framework" -o -name "*.xpc" -o -name "*.app" -o -name "*.dylib" -o -name "Autoupdate" -type f \) \
  -print0 \
  | while IFS= read -r -d '' nested; do
      printf '%s\t%s\0' "$(printf '%s' "$nested" | tr -cd '/' | wc -c)" "$nested"
    done \
  | sort -z -rn -k1,1 \
  | while IFS=$'\t' read -r -d '' _depth nested; do
      echo "Signing nested: $nested"
      codesign --force --options runtime --timestamp \
        --preserve-metadata=entitlements,flags,runtime \
        --sign "$identity" "$nested"
    done

# 2. Outer app bundle WITH its entitlements (no --deep).
codesign --force --options runtime --timestamp \
  --entitlements "$entitlements" \
  --sign "$identity" "$app_path"

# 3. Verify the whole tree, strictly.
codesign --verify --deep --strict --verbose=2 "$app_path"
echo "App signed inside-out: $app_path"
