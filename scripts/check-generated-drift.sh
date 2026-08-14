#!/usr/bin/env bash
#
# Verify that every committed generated artifact matches its source of truth.
#
# This only INSPECTS the working tree; the generators must have run first
# (`make check-drift` does both). CI calls it after the setup-native-build
# action, which regenerates all three groups as a side effect of preparing the
# build.
#
# Usage: scripts/check-generated-drift.sh

set -euo pipefail

cd "$(dirname "$0")/.."

failed=0

# check <hint> <path>...
#
# Prints the offending diff and an ::error:: annotation naming the command that
# fixes it, then keeps going so one run reports every drifted group at once.
check() {
  local hint="$1"
  shift
  if ! git diff --exit-code -- "$@"; then
    echo "::error::Generated files above are out of sync. Run \`$hint\` and commit the result."
    failed=1
  fi
}

check 'make widget' \
  apps/native/WolfWave/Resources/widget.html

check 'bun run tokens' \
  apps/native/WolfWave/Core/DesignSystem/Tokens.generated.swift \
  apps/docs/app/tokens.generated.css \
  apps/native/WolfWave/Resources/widget-tokens.generated.js \
  apps/marketing/shared/tokens.generated.ts \
  'apps/docs/app/(home)/_widgets/widget-themes.generated.ts'

check 'make sponsor-config' \
  apps/native/WolfWave/Core/SponsorConfig.generated.swift

if [ "$failed" -eq 0 ]; then
  echo "✅ Generated artifacts are in sync with their sources."
fi

exit "$failed"
