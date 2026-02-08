# WolfWave build & distribution commands

PROJECT     = src/wolfwave.xcodeproj
SCHEME      = WolfWave
DESTINATION = platform=macOS,arch=arm64
BUILD_DIR   = build
BUILDS_DIR  = builds

# Resolve version from Xcode project (Release config)
VERSION = $(shell xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -showBuildSettings 2>/dev/null | awk -F'= ' '/MARKETING_VERSION/ {gsub(/^[ \t]+/,"",$$2); print $$2; exit}')
DMG_NAME = WolfWave-$(VERSION)-arm64.dmg

.PHONY: help build clean test update-deps open-xcode ci prod-build prod-install notarize

help:
	@echo "Available targets:"
	@echo "  build          Debug build"
	@echo "  clean          Clean build artifacts"
	@echo "  test           Run tests"
	@echo "  prod-build     Release build + DMG  (-> builds/$(DMG_NAME))"
	@echo "  prod-install   Release build + install to /Applications"
	@echo "  notarize       Notarize builds/$(DMG_NAME)"
	@echo "  update-deps    Resolve SwiftPM dependencies"
	@echo "  open-xcode     Open the Xcode project"
	@echo "  ci             CI-friendly build"

# ---------------------------------------------------------------------------
# Development
# ---------------------------------------------------------------------------
build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' -configuration Debug build -quiet

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' clean -quiet
	rm -rf $(BUILD_DIR) $(BUILDS_DIR)

test:
	-xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' -configuration Debug test -quiet

update-deps:
	xcodebuild -project $(PROJECT) -resolvePackageDependencies -quiet

open-xcode:
	open $(PROJECT)

ci: build

# ---------------------------------------------------------------------------
# Release build + DMG
# ---------------------------------------------------------------------------
prod-build:
	@echo "🔨 Building Release..."
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-configuration Release -derivedDataPath $(BUILD_DIR) build -quiet
	@# Locate the built .app
	@APP_PATH=$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-configuration Release -derivedDataPath $(BUILD_DIR) -showBuildSettings 2>/dev/null \
		| awk -F'= ' '/CONFIGURATION_BUILD_DIR/ {dir=$$2} /WRAPPER_NAME/ {name=$$2} END {gsub(/^[ \t]+/,"",dir); gsub(/^[ \t]+/,"",name); print dir "/" name}'); \
	if [ ! -d "$$APP_PATH" ]; then echo "❌ .app not found at $$APP_PATH"; exit 1; fi; \
	echo "✅ Release build: $$APP_PATH"; \
	if security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then \
		echo "🔏 Re-signing with Developer ID..."; \
		codesign --deep --force --options runtime \
			--sign "Developer ID Application" "$$APP_PATH"; \
		echo "✅ Signed with Developer ID"; \
	else \
		echo "⚠️  No Developer ID cert found — DMG will be development-signed"; \
	fi; \
	$(MAKE) _create-dmg APP_PATH="$$APP_PATH"

_create-dmg:
	@echo "📦 Creating DMG..."
	@mkdir -p $(BUILDS_DIR)
	@rm -rf $(BUILDS_DIR)/staging $(BUILDS_DIR)/$(DMG_NAME)
	@mkdir -p $(BUILDS_DIR)/staging
	@cp -R "$(APP_PATH)" $(BUILDS_DIR)/staging/
	@ln -sf /Applications $(BUILDS_DIR)/staging/Applications
	@# Create read-write temp image
	@hdiutil create -srcfolder $(BUILDS_DIR)/staging \
		-volname "WolfWave" -fs HFS+ -format UDRW -ov \
		$(BUILDS_DIR)/_tmp.dmg >/dev/null
	@# Mount, configure Finder layout, unmount
	@MOUNTPOINT=$$(hdiutil attach -readwrite -noverify -noautoopen \
		$(BUILDS_DIR)/_tmp.dmg | awk '/\/Volumes\// {print $$NF}'); \
	sleep 1; \
	osascript \
		-e 'tell application "Finder"' \
		-e '  tell disk "WolfWave"' \
		-e '    open' \
		-e '    set current view of container window to icon view' \
		-e '    set toolbar visible of container window to false' \
		-e '    set statusbar visible of container window to false' \
		-e '    set the bounds of container window to {200, 200, 740, 520}' \
		-e '    set viewOptions to the icon view options of container window' \
		-e '    set arrangement of viewOptions to not arranged' \
		-e '    set icon size of viewOptions to 100' \
		-e '    set text size of viewOptions to 12' \
		-e '    set position of item "WolfWave.app" of container window to {140, 160}' \
		-e '    set position of item "Applications" of container window to {400, 160}' \
		-e '    close' \
		-e '    open' \
		-e '    delay 1' \
		-e '  end tell' \
		-e 'end tell' 2>/dev/null || true; \
	sync; sleep 1; \
	hdiutil detach "$$MOUNTPOINT" -quiet 2>/dev/null || true
	@# Force-detach any remaining mounts
	@LEFTOVER=$$(hdiutil info 2>/dev/null | awk '/\/Volumes\/WolfWave/ {print $$1; exit}'); \
	if [ -n "$$LEFTOVER" ]; then hdiutil detach "$$LEFTOVER" -force 2>/dev/null || true; fi
	@sleep 1
	@# Convert to compressed read-only DMG
	@hdiutil convert $(BUILDS_DIR)/_tmp.dmg -format UDZO \
		-imagekey zlib-level=9 -o $(BUILDS_DIR)/$(DMG_NAME) >/dev/null
	@rm -f $(BUILDS_DIR)/_tmp.dmg
	@rm -rf $(BUILDS_DIR)/staging
	@echo "✅ DMG created: $(BUILDS_DIR)/$(DMG_NAME)"

prod-install: prod-build
	@echo "📦 Installing to /Applications..."
	@rm -rf /Applications/WolfWave.app
	@cp -R "$$(find $(BUILD_DIR) -type d -name '*.app' -maxdepth 4 -print -quit)" /Applications/
	@echo "✅ Installed. Launch: open /Applications/WolfWave.app"

# ---------------------------------------------------------------------------
# Notarization (local)
# ---------------------------------------------------------------------------
# Requires environment variables:
#   APPLE_ID           Your Apple ID email
#   APPLE_TEAM_ID      Developer Team ID (HBB7T99U79)
#   APPLE_APP_PASSWORD App-specific password from appleid.apple.com
#
# Also requires "Developer ID Application" certificate in Keychain.
# ---------------------------------------------------------------------------
notarize:
	@if [ ! -f $(BUILDS_DIR)/$(DMG_NAME) ]; then \
		echo "❌ $(BUILDS_DIR)/$(DMG_NAME) not found. Run 'make prod-build' first."; exit 1; fi
	@for var in APPLE_ID APPLE_TEAM_ID APPLE_APP_PASSWORD; do \
		eval val=\$$$$var; \
		if [ -z "$$val" ]; then \
			echo "❌ $$var is not set."; \
			echo "   Usage: APPLE_ID=... APPLE_TEAM_ID=... APPLE_APP_PASSWORD=... make notarize"; \
			exit 1; \
		fi; \
	done
	@echo "🔏 Signing DMG..."
	codesign --force --sign "Developer ID Application" $(BUILDS_DIR)/$(DMG_NAME)
	@echo "📤 Submitting to Apple notary service (this may take a few minutes)..."
	xcrun notarytool submit $(BUILDS_DIR)/$(DMG_NAME) \
		--apple-id "$(APPLE_ID)" \
		--team-id "$(APPLE_TEAM_ID)" \
		--password "$(APPLE_APP_PASSWORD)" \
		--wait
	@echo "📎 Stapling ticket..."
	xcrun stapler staple $(BUILDS_DIR)/$(DMG_NAME)
	@echo "✅ Notarized: $(BUILDS_DIR)/$(DMG_NAME)"
