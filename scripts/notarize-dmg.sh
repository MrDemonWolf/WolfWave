#!/usr/bin/env bash
#
# Sign, notarize, and staple a DMG. Shared by the Release and Nightly workflows
# and by `make notarize`.
#
# Env:
#   APPLE_ID            Apple ID email
#   APPLE_TEAM_ID       Developer Team ID
#   APPLE_APP_PASSWORD  app-specific password from appleid.apple.com
#   SIGN_IDENTITY       codesign identity (default "Developer ID Application")
#
# Usage: scripts/notarize-dmg.sh <path-to-dmg>

set -uo pipefail

dmg="${1:?usage: notarize-dmg.sh <path-to-dmg>}"
identity="${SIGN_IDENTITY:-Developer ID Application}"

: "${APPLE_ID:?APPLE_ID is required}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
: "${APPLE_APP_PASSWORD:?APPLE_APP_PASSWORD is required}"

if [ ! -f "$dmg" ]; then
  echo "::error::DMG not found at $dmg" >&2
  exit 1
fi

echo "Signing $dmg"
codesign --force --sign "$identity" --timestamp "$dmg" || exit 1

# Deliberately no `set -e` around the submit: a non-Accepted status makes
# `notarytool submit --wait` exit non-zero, and aborting here would lose the
# notary log — the only place the actual reason appears (see the 2026-06 v2.0.0
# Invalid block).
echo "Submitting to the Apple notary service (up to 30m)"
submit_json="$(xcrun notarytool submit "$dmg" \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" --wait --timeout 30m \
  --output-format json)"
echo "$submit_json"

submission_id="$(echo "$submit_json" | jq -r '.id')"
status="$(echo "$submit_json" | jq -r '.status')"
echo "Notarization status: $status (submission $submission_id)"

if [ "$status" != "Accepted" ]; then
  echo "::error::Notarization $status — fetching notary log for $submission_id"
  xcrun notarytool log "$submission_id" \
    --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" || true
  exit 1
fi

xcrun stapler staple "$dmg" || exit 1
echo "Notarized and stapled: $dmg"
