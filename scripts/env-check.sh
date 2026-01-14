#!/usr/bin/env bash
set -euo pipefail

echo "Running env-check..."
fail=0

check_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1"; fail=1; }
}

check_cmd xcodebuild
check_cmd swift
check_cmd xcode-select
check_cmd git

os_ver=$(sw_vers -productVersion)
os_major=$(echo "$os_ver" | cut -d. -f1)
os_minor=$(echo "$os_ver" | cut -d. -f2)
if [ "$os_major" -lt 12 ]; then
  echo "macOS $os_ver detected — macOS 12+ required"
  fail=1
else
  echo "macOS $os_ver OK"
fi

xcode_ver_raw=$(xcodebuild -version 2>/dev/null | head -n1 || true)
xcode_ver=$(printf '%s' "$xcode_ver_raw" | grep -oE '[0-9]+(\.[0-9]+)*' || true)
if [ -z "$xcode_ver" ]; then
  echo "Unable to detect Xcode version (raw: $xcode_ver_raw)"
  fail=1
else
  xcode_major=$(echo "$xcode_ver" | cut -d. -f1)
  if ! printf '%s' "$xcode_major" | grep -qE '^[0-9]+$'; then
    echo "Unable to parse Xcode major version: $xcode_major"
    fail=1
  elif [ "$xcode_major" -lt 15 ]; then
    echo "Xcode $xcode_ver detected — Xcode 15+ recommended"
    fail=1
  else
    echo "Xcode $xcode_ver OK"
  fi
fi

swift_ver_raw=$(swift --version 2>/dev/null || true)
swift_ver=$(printf '%s
' "$swift_ver_raw" | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1 || true)
if [ -z "$swift_ver" ]; then
  echo "Unable to detect Swift version (raw: $swift_ver_raw)"
  fail=1
else
  swift_major=$(echo "$swift_ver" | cut -d. -f1)
  swift_minor=$(echo "$swift_ver" | cut -d. -f2)
  if ! printf '%s' "$swift_major" | grep -qE '^[0-9]+$'; then
    echo "Unable to parse Swift major version: $swift_major"
    fail=1
  elif [ "$swift_major" -lt 5 ] || { [ "$swift_major" -eq 5 ] && [ "$swift_minor" -lt 9 ]; }; then
    echo "Swift $swift_ver detected — Swift 5.9+ required"
    fail=1
  else
    echo "Swift $swift_ver OK"
  fi
fi

# Note: Xcode scheme environment variables are applied only to the app launched by Xcode
# and are not visible to this shell. Set `TWITCH_CLIENT_ID` in your shell if you
# want the variable available to `make env-check`.

if [ "$fail" -ne 0 ]; then
  echo "✖ env-check failed"
  exit 1
else
  echo "✔ env-check OK"
  exit 0
fi
