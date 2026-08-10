#!/usr/bin/env bash
#
# version.sh — single source of truth for marketing version + build number.
#
# Implements the house build/version standard documented in
# docs/build-versioning-standard.md. Every platform job in every pipeline calls
# this once and consumes the result; nothing downstream invents its own number.
#
# Usage:
#   scripts/version.sh                       # stable channel, JSON
#   scripts/version.sh --channel nightly     # nightly channel, JSON
#   scripts/version.sh --format env          # KEY=value, for `eval` or $GITHUB_OUTPUT
#
# Output keys: marketing, build, short_sha, channel
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Build-number floor.
#
# The build number is the commit count, which only ever needs a floor when a
# repo has already published a build number above its own commit count. Raising
# this is a one-way door: it can only ever go up, never down, because Sparkle
# and both app stores reject a build number that regresses.
#
# WolfWave note: the retired nightly scheme published build 202608051034 (a UTC
# minute stamp). That value is ~100x over Android's 2,100,000,000 versionCode
# cap and can never be part of this standard, so it was deliberately abandoned
# rather than floored past. Nightly is opt-in and unsupported; testers running
# that one build reinstall the DMG once. Stable's published build was 8, which
# the commit count clears on its own.
# ---------------------------------------------------------------------------
readonly BUILD_FLOOR=100

CHANNEL="stable"
FORMAT="json"

while [ $# -gt 0 ]; do
  case "$1" in
    --channel) CHANNEL="${2:?--channel needs a value}"; shift 2 ;;
    --format)  FORMAT="${2:?--format needs a value}";  shift 2 ;;
    -h|--help) sed -n '3,14p' "$0"; exit 0 ;;
    *) echo "version.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

case "$CHANNEL" in
  stable|nightly) ;;
  *) echo "version.sh: --channel must be 'stable' or 'nightly' (got '$CHANNEL')" >&2; exit 2 ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# ---------------------------------------------------------------------------
# Build number: commit count on HEAD.
#
# A shallow clone silently reports 1, which would publish a catastrophically
# low build number. Fail loudly instead — CI checkouts must set fetch-depth: 0.
# ---------------------------------------------------------------------------
if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
  echo "version.sh: refusing to run in a shallow clone — the commit count would be wrong." >&2
  echo "            Set 'fetch-depth: 0' on actions/checkout, or run 'git fetch --unshallow'." >&2
  exit 1
fi

COMMIT_COUNT="$(git rev-list --count HEAD)"
if [ "$COMMIT_COUNT" -gt "$BUILD_FLOOR" ]; then
  BUILD="$COMMIT_COUNT"
else
  BUILD="$BUILD_FLOOR"
fi

# Android's versionCode cap is the tightest ceiling across our platforms; a
# breach here means the scheme itself has gone wrong, not that a bump is due.
if [ "$BUILD" -gt 2100000000 ]; then
  echo "version.sh: build number $BUILD exceeds Android's versionCode cap (2100000000)." >&2
  exit 1
fi

SHORT_SHA="$(git rev-parse --short HEAD)"

# ---------------------------------------------------------------------------
# Marketing version: the release tag when building one, else the committed
# MARKETING_VERSION. Parsed out of the pbxproj directly rather than via
# xcodebuild so this script stays runnable on any platform and in any repo.
# ---------------------------------------------------------------------------
MARKETING="${MARKETING_VERSION_OVERRIDE:-}"

if [ -z "$MARKETING" ]; then
  REF="${GITHUB_REF:-}"
  case "$REF" in
    refs/tags/v*) MARKETING="${REF#refs/tags/v}" ;;
  esac
fi

if [ -z "$MARKETING" ]; then
  MARKETING="$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' \
    apps/native/WolfWave.xcodeproj/project.pbxproj | head -1 | tr -d '[:space:]')"
fi

if [ -z "$MARKETING" ]; then
  echo "version.sh: could not resolve a marketing version (no v* tag, no MARKETING_VERSION)." >&2
  exit 1
fi

# Both sources are trusted inputs that can still be wrong: a mistyped tag
# (`v2.1`, `vfoo`) or a hand-edited pbxproj would otherwise flow straight into
# CFBundleShortVersionString, which Apple requires to be period-separated
# integers. Reject it here rather than at notarization time.
if ! [[ "$MARKETING" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "version.sh: marketing version must be MAJOR.MINOR.PATCH (got '$MARKETING')." >&2
  exit 1
fi

# Store-bound builds must ship a bare MAJOR.MINOR.PATCH; only non-store
# channels carry a suffix.
if [ "$CHANNEL" = "nightly" ]; then
  # A nightly advertises the NEXT release, so the committed MARKETING_VERSION
  # must already be bumped past the last shipped tag. It normally is — the
  # release checklist bumps it right after tagging — but if someone forgets,
  # nightlies would claim a version that already shipped. Warn rather than
  # fail: a broken build is worse than a stale label, and the fix is a
  # one-line pbxproj edit.
  LAST_TAG="$(git tag --list 'v*' --sort=-v:refname | head -1)"
  if [ -n "$LAST_TAG" ] && [ "${LAST_TAG#v}" = "$MARKETING" ]; then
    echo "version.sh: WARNING — MARKETING_VERSION ($MARKETING) matches the last shipped" >&2
    echo "            tag ($LAST_TAG). Nightlies are supposed to advertise the NEXT" >&2
    echo "            release. Bump MARKETING_VERSION in project.pbxproj." >&2
  fi
  MARKETING="${MARKETING}-nightly+${SHORT_SHA}"
fi

case "$FORMAT" in
  json)
    printf '{"marketing":"%s","build":%s,"short_sha":"%s","channel":"%s"}\n' \
      "$MARKETING" "$BUILD" "$SHORT_SHA" "$CHANNEL"
    ;;
  env)
    printf 'marketing=%s\nbuild=%s\nshort_sha=%s\nchannel=%s\n' \
      "$MARKETING" "$BUILD" "$SHORT_SHA" "$CHANNEL"
    ;;
  *)
    echo "version.sh: --format must be 'json' or 'env' (got '$FORMAT')" >&2
    exit 2
    ;;
esac
