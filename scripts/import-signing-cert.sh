#!/usr/bin/env bash
#
# Import the Developer ID Application certificate into a throwaway keychain and
# make it the default search list, so xcodebuild/codesign can find the identity.
#
# The keychain is NOT removed here — the caller owns its lifetime and should
# delete it in an `if: always()` step:
#   security delete-keychain "$RUNNER_TEMP/build.keychain-db" || true
#
# Env:
#   CERT_P12       base64-encoded .p12 (repo secret DEVELOPER_ID_CERT_P12)
#   CERT_PASSWORD  its password        (repo secret DEVELOPER_ID_CERT_PASSWORD)
#   RUNNER_TEMP    where to put the keychain; defaults to a fresh mktemp dir
#
# Usage: scripts/import-signing-cert.sh

set -euo pipefail

: "${CERT_P12:?CERT_P12 is required (base64-encoded .p12)}"
: "${CERT_PASSWORD:?CERT_PASSWORD is required}"

work_dir="${RUNNER_TEMP:-$(mktemp -d)}"
keychain_path="$work_dir/build.keychain-db"
cert_path="$work_dir/certificate.p12"

trap 'rm -f "$cert_path"' EXIT

printf '%s\n' "$CERT_P12" | base64 --decode > "$cert_path"

security create-keychain -p "" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "" "$keychain_path"
security import "$cert_path" \
  -k "$keychain_path" \
  -P "$CERT_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple: -k "" "$keychain_path"
security list-keychains -d user -s "$keychain_path" login.keychain-db

echo "Developer ID certificate imported into $keychain_path"
