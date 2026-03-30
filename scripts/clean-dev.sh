#!/bin/bash
# Wipes WolfWave Dev build state for a fresh start.
# Run this to reset the dev build without affecting your production install.

set -euo pipefail

DEV_BUNDLE_ID="com.mrdemonwolf.wolfwave.dev"
DEV_APP_NAME="WolfWave Dev"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "🧹 Cleaning WolfWave Dev..."

# Kill running dev app
if pgrep -f "$DEV_APP_NAME" >/dev/null 2>&1; then
    echo "  Stopping $DEV_APP_NAME..."
    pkill -f "$DEV_APP_NAME" 2>/dev/null || true
    sleep 1
fi

# Clear UserDefaults
echo "  Clearing UserDefaults for $DEV_BUNDLE_ID..."
defaults delete "$DEV_BUNDLE_ID" 2>/dev/null || true

# Clear Keychain entries
echo "  Removing Keychain entries..."
security delete-generic-password -s "$DEV_BUNDLE_ID" 2>/dev/null || true

# Clean Xcode build artifacts
echo "  Cleaning build artifacts..."
cd "$PROJECT_DIR"
make clean 2>/dev/null || true

# Remove DerivedData for this project
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
if [ -d "$DERIVED_DATA" ]; then
    echo "  Removing DerivedData..."
    rm -rf "$DERIVED_DATA"/wolfwave-* 2>/dev/null || true
fi

# Remove app from /Applications if installed
if [ -d "/Applications/$DEV_APP_NAME.app" ]; then
    echo "  Removing /Applications/$DEV_APP_NAME.app..."
    rm -rf "/Applications/$DEV_APP_NAME.app"
fi

echo "✅ WolfWave Dev cleaned. Run 'make build' for a fresh start."
