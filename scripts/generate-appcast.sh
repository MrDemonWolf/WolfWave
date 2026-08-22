#!/usr/bin/env bash
#
# Generate and validate a Sparkle appcast for the DMGs in a build directory.
#
# Uses the generate_appcast from the Sparkle cask, reusing it if a previous step
# already installed it. Set SPARKLE_BIN to a full path to generate_appcast to
# bypass the lookup entirely.
#
# Env:
#   SPARKLE_PRIVATE_KEY  the EdDSA private key (repo secret)
#
# Usage: scripts/generate-appcast.sh <output-xml> <download-url-prefix> [builds-dir]

set -euo pipefail

output="${1:?usage: generate-appcast.sh <output-xml> <download-url-prefix> [builds-dir]}"
url_prefix="${2:?missing download-url-prefix}"
builds_dir="${3:-builds}"

: "${SPARKLE_PRIVATE_KEY:?SPARKLE_PRIVATE_KEY is required}"

find_tool() {
  # Only one of the two Caskroom roots exists on any given Mac, so find exits 1
  # after listing the other. Under pipefail that 1 survives `head`, and the
  # `tool="$(find_tool)"` assignment turns it into a silent script death
  # before the first echo (every nightly from 2026-08-15 to 2026-08-21).
  find /opt/homebrew/Caskroom/sparkle /usr/local/Caskroom/sparkle \
    -name generate_appcast -type f 2>/dev/null | head -1 || true
}

tool="${SPARKLE_BIN:-}"
if [ -z "$tool" ]; then
  tool="$(find_tool)"
fi
if [ -z "$tool" ]; then
  echo "Sparkle CLI tools not found; installing the cask"
  brew install --cask sparkle
  tool="$(find_tool)"
fi
if [ -z "$tool" ]; then
  echo "::error::Could not locate generate_appcast after installing the Sparkle cask" >&2
  exit 1
fi
echo "Using $tool"

key_file="$(mktemp)"
trap 'rm -f "$key_file"' EXIT
printf '%s\n' "$SPARKLE_PRIVATE_KEY" > "$key_file"

# --embed-release-notes forces the notes INLINE into <description>. Without it,
# generate_appcast refuses to embed a full HTML document (release-notes.mjs
# emits <!DOCTYPE>/<body>) and instead writes a <sparkle:releaseNotesLink> to
# the .html release asset. GitHub serves release assets as
# `Content-Disposition: attachment`, so Sparkle's web view downloads the file
# instead of rendering it.
"$tool" \
  --ed-key-file "$key_file" \
  --embed-release-notes \
  --download-url-prefix "$url_prefix" \
  -o "$output" "$builds_dir/"

xmllint --noout "$output"

fail() { echo "::error::$1" >&2; exit 1; }

grep -q 'sparkle:edSignature=' "$output" \
  || fail "$output has no edSignature; the update would be rejected as unsigned"
grep -q '<description>' "$output" \
  || fail "$output has no inline <description> release notes"
# Hard guard: notes MUST be inline. A <sparkle:releaseNotesLink> means embedding
# failed and Sparkle will download the notes instead of rendering them.
if grep -q 'releaseNotesLink' "$output"; then
  fail "$output has a releaseNotesLink; the notes were not embedded"
fi

echo "Appcast generated and validated: $output"
