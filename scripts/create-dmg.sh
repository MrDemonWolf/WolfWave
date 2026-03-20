#!/bin/bash
# create-dmg.sh — Create a styled WolfWave DMG installer
# Usage: ./scripts/create-dmg.sh <app-path> <dmg-name> <builds-dir>
set -euo pipefail

APP_PATH="${1:?Usage: create-dmg.sh <app-path> <dmg-name> <builds-dir>}"
DMG_NAME="${2:?Usage: create-dmg.sh <app-path> <dmg-name> <builds-dir>}"
BUILDS_DIR="${3:?Usage: create-dmg.sh <app-path> <dmg-name> <builds-dir>}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BG_IMAGE="$PROJECT_DIR/assets/dmg-background.png"
BG_IMAGE_2X="$PROJECT_DIR/assets/dmg-background@2x.png"
HAS_BACKGROUND=false

if [ -f "$BG_IMAGE" ]; then
    HAS_BACKGROUND=true
fi

echo "📦 Creating DMG..."
mkdir -p "$BUILDS_DIR"
rm -rf "$BUILDS_DIR/staging" "$BUILDS_DIR/$DMG_NAME"
mkdir -p "$BUILDS_DIR/staging"
cp -R "$APP_PATH" "$BUILDS_DIR/staging/"
ln -sf /Applications "$BUILDS_DIR/staging/Applications"

# Create read-write temp image
hdiutil create -srcfolder "$BUILDS_DIR/staging" \
    -volname "WolfWave" -fs HFS+ -format UDRW -ov \
    "$BUILDS_DIR/_tmp.dmg" >/dev/null

# Mount, configure Finder layout, unmount
MOUNTPOINT=$(hdiutil attach -readwrite -noverify -noautoopen \
    "$BUILDS_DIR/_tmp.dmg" | awk '/\/Volumes\// {print $NF}')
sleep 1

# Copy background images if available
BG_APPLESCRIPT=""
if [ "$HAS_BACKGROUND" = true ]; then
    mkdir -p "$MOUNTPOINT/.background"
    cp "$BG_IMAGE" "$MOUNTPOINT/.background/dmg-background.png"
    if [ -f "$BG_IMAGE_2X" ]; then
        cp "$BG_IMAGE_2X" "$MOUNTPOINT/.background/dmg-background@2x.png"
    fi
    BG_APPLESCRIPT='set background picture of viewOptions to file ".background:dmg-background.png"'
fi

osascript \
    -e 'tell application "Finder"' \
    -e '  tell disk "WolfWave"' \
    -e '    open' \
    -e '    delay 2' \
    -e '    set current view of container window to icon view' \
    -e '    set toolbar visible of container window to false' \
    -e '    set statusbar visible of container window to false' \
    -e '    set the bounds of container window to {200, 200, 860, 600}' \
    -e '    set viewOptions to the icon view options of container window' \
    -e '    set arrangement of viewOptions to not arranged' \
    -e '    set icon size of viewOptions to 100' \
    -e '    set text size of viewOptions to 12' \
    ${BG_APPLESCRIPT:+-e "    $BG_APPLESCRIPT"} \
    -e '    set position of item "WolfWave.app" of container window to {175, 190}' \
    -e '    set position of item "Applications" of container window to {485, 190}' \
    -e '    close' \
    -e '    open' \
    -e '    delay 1' \
    -e '  end tell' \
    -e 'end tell' || true

sync; sleep 2
hdiutil detach "$MOUNTPOINT" -quiet 2>/dev/null || true
sleep 1

# Force-detach any remaining mounts
LEFTOVER=$(hdiutil info 2>/dev/null | awk '/\/Volumes\/WolfWave/ {print $1; exit}')
if [ -n "$LEFTOVER" ]; then
    hdiutil detach "$LEFTOVER" -force 2>/dev/null || true
    sleep 2
fi

# Wait for the image to be fully released before converting
for i in 1 2 3 4 5; do
    if hdiutil convert "$BUILDS_DIR/_tmp.dmg" -format UDZO \
        -imagekey zlib-level=9 -o "$BUILDS_DIR/$DMG_NAME" >/dev/null 2>&1; then
        break
    fi
    echo "⏳ Waiting for DMG to be released (attempt $i/5)..."
    sleep 2
done

# Verify the final DMG was created
if [ ! -f "$BUILDS_DIR/$DMG_NAME" ]; then
    echo "❌ Failed to create DMG after retries"
    exit 1
fi
rm -f "$BUILDS_DIR/_tmp.dmg"
rm -rf "$BUILDS_DIR/staging"

echo "✅ DMG created: $BUILDS_DIR/$DMG_NAME"
