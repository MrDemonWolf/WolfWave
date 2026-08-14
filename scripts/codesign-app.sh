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
#   SIGN_IDENTITY  codesign identity (default "Developer ID Application")
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
