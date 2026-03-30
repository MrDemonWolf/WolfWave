# WolfWave build & distribution commands

PROJECT     = apps/native/wolfwave.xcodeproj
SCHEME      = WolfWave
DESTINATION = platform=macOS,arch=arm64
PROD_DESTINATION = generic/platform=macOS
PROD_ARCHS = arm64 x86_64
BUILD_DIR   = build
BUILDS_DIR  = builds

# Resolve version from Xcode project (Release config)
VERSION = $(shell xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -showBuildSettings 2>/dev/null | awk -F'= ' '/MARKETING_VERSION/ {gsub(/^[ \t]+/,"",$$2); print $$2; exit}')
DMG_NAME = WolfWave-$(VERSION).dmg

.SHELLFLAGS = -ec

.PHONY: help build clean test test-verbose test-ci update-deps open-xcode ci prod-build prod-install notarize verify-notarize

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
	@echo "  verify-notarize Verify notarization of builds/$(DMG_NAME)"
	@echo "  test-verbose   Run tests with full output"
	@echo "  test-ci        Run tests in CI mode (no signing, result bundle)"
	@echo "  ci             Run CI test suite"

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
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' -configuration Debug \
		-only-testing WolfWaveTests \
		CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
		test 2>/dev/null | scripts/check-test-results.sh

test-verbose:
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' -configuration Debug \
		-only-testing WolfWaveTests \
		test 2>/dev/null | tee /dev/stderr | scripts/check-test-results.sh

test-ci:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' -configuration Debug \
		-only-testing WolfWaveTests \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO \
		-resultBundlePath TestResults.xcresult \
		test

update-deps:
	xcodebuild -project $(PROJECT) -resolvePackageDependencies -quiet

open-xcode:
	open $(PROJECT)

ci: test-ci

# ---------------------------------------------------------------------------
# Release build + DMG
# ---------------------------------------------------------------------------
prod-build:
	@echo "🔨 Building Release..."
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(PROD_DESTINATION)' ARCHS="$(PROD_ARCHS)" \
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
	@./scripts/create-dmg.sh "$(APP_PATH)" "$(DMG_NAME)" "$(BUILDS_DIR)"

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
	@if [ -z "$(APPLE_ID)" ]; then \
		echo "❌ APPLE_ID is not set."; \
		echo "   Usage: APPLE_ID=... APPLE_TEAM_ID=... APPLE_APP_PASSWORD=... make notarize"; \
		exit 1; fi
	@if [ -z "$(APPLE_TEAM_ID)" ]; then \
		echo "❌ APPLE_TEAM_ID is not set."; \
		echo "   Usage: APPLE_ID=... APPLE_TEAM_ID=... APPLE_APP_PASSWORD=... make notarize"; \
		exit 1; fi
	@if [ -z "$(APPLE_APP_PASSWORD)" ]; then \
		echo "❌ APPLE_APP_PASSWORD is not set."; \
		echo "   Usage: APPLE_ID=... APPLE_TEAM_ID=... APPLE_APP_PASSWORD=... make notarize"; \
		exit 1; fi
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

verify-notarize:
	@if [ ! -f $(BUILDS_DIR)/$(DMG_NAME) ]; then \
		echo "❌ $(BUILDS_DIR)/$(DMG_NAME) not found."; exit 1; fi
	@echo "🔍 Verifying notarization..."
	spctl --assess --type open --context context:primary-signature $(BUILDS_DIR)/$(DMG_NAME)
	@echo "✅ Notarization verified: $(BUILDS_DIR)/$(DMG_NAME)"
