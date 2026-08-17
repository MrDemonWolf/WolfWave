# WolfWave build & distribution commands

PROJECT     = apps/native/WolfWave.xcodeproj
SCHEME      = WolfWave
DESTINATION = platform=macOS,arch=arm64
PROD_DESTINATION = generic/platform=macOS
PROD_ARCHS = arm64
BUILD_DIR   = build
BUILDS_DIR  = builds
TEST_DERIVED_DATA = $(CURDIR)/DerivedData/Tests
# SwiftLint 0.65.0, pinned by immutable official-image digest.
SWIFTLINT_IMAGE = ghcr.io/realm/swiftlint:0.65.0@sha256:a482729f4b58741875af1566f23397f3f6db300372756fc31606d0a4527fab9e
SWIFTLINT_DOCKER = docker run --rm -v "$(CURDIR):/work" -w /work $(SWIFTLINT_IMAGE)

# Resolve version from Xcode project (Release config)
VERSION = $(shell xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -showBuildSettings 2>/dev/null | awk -F'= ' '/MARKETING_VERSION/ {gsub(/^[ \t]+/,"",$$2); print $$2; exit}')
DMG_NAME = WolfWave-$(VERSION).dmg

.SHELLFLAGS = -ec

# Signing for LOCAL Debug builds and tests.
#
# Ad-hoc signing ("-") derives the code signature from the binary's own hash, so
# every rebuild looks like a different application to macOS. That invalidates the
# Keychain ACL and the TCC Automation grant each time, which is why a locally
# built app pops "WolfWave wants to use your confidential information stored in
# com.mrdemonwolf.wolfwave.dev" on launch after every build, and why Apple Events
# permission has to be re-granted. Signing with a real Apple Development identity
# keeps the signature stable across rebuilds, so both grants stick.
#
# DEVELOPMENT_TEAM already lives in project.pbxproj, so only the identity is set
# here. Falls back to ad-hoc when no identity is present (CI runners have none).
LOCAL_SIGN_ID := $(shell security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ { print $$2; exit }')

ifeq ($(strip $(LOCAL_SIGN_ID)),)
LOCAL_SIGN = CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
else
LOCAL_SIGN = CODE_SIGN_IDENTITY="$(LOCAL_SIGN_ID)" CODE_SIGN_STYLE=Manual
endif

# Signing for the UI tests, which differ from every other target in one way that
# matters: XCUITest launches the product and attaches to it, and a wholly
# unsigned app cannot be attached to. So the no-identity fallback here is ad-hoc
# signing, NOT `CODE_SIGNING_ALLOWED=NO`. On a machine with a real identity this
# is identical to LOCAL_SIGN, which keeps the app's TCC and Keychain grants
# stable across rebuilds.
ifeq ($(strip $(LOCAL_SIGN_ID)),)
UI_SIGN = CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
else
UI_SIGN = CODE_SIGN_IDENTITY="$(LOCAL_SIGN_ID)" CODE_SIGN_STYLE=Manual
endif

.PHONY: help build clean test test-verbose test-ui test-ci check-drift lint lint-baseline lint-crash-safety lint-headers update-deps open-xcode ci prod-build prod-install notarize verify-notarize sponsor-config widget

help:
	@echo "Available targets:"
	@echo "  build          Debug build"
	@echo "  widget         Rebuild the OBS overlay widget (apps/widget -> Resources/widget.html)"
	@echo "  clean          Clean build artifacts"
	@echo "  test           Run tests"
	@echo "  lint           Run pinned SwiftLint in Docker"
	@echo "  lint-baseline  Regenerate the pinned SwiftLint baseline"
	@echo "  lint-crash-safety  Run crash-safety SwiftLint (blocking CI gate)"
	@echo "  lint-headers   Verify Swift file headers match the Xcode template"
	@echo "  prod-build     Release build + DMG  (-> builds/$(DMG_NAME))"
	@echo "  prod-install   Release build + install to /Applications"
	@echo "  notarize       Notarize builds/$(DMG_NAME)"
	@echo "  update-deps    Resolve SwiftPM dependencies"
	@echo "  open-xcode     Open the Xcode project"
	@echo "  verify-notarize Verify notarization of builds/$(DMG_NAME)"
	@echo "  test-verbose   Run tests with full output"
	@echo "  test-ui        Run the XCUITest suite (launches the real app)"
	@echo "  test-ci        Run tests exactly as CI does (no signing, result bundle)"
	@echo "  check-drift    Regenerate widget/tokens/SponsorConfig and fail on drift"
	@echo "  ci             Run CI test suite"

# ---------------------------------------------------------------------------
# Development
# ---------------------------------------------------------------------------
build: sponsor-config
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' -configuration Debug \
		$(LOCAL_SIGN) \
		build -quiet

# Regenerate apps/native/WolfWave/Core/SponsorConfig.generated.swift from
# .github/FUNDING.yml. Idempotent; safe to run as a build prerequisite.
sponsor-config:
	@bash scripts/generate-sponsor-config.sh

# Rebuild the OBS overlay widget (Tailwind + TypeScript -> single inlined
# apps/native/WolfWave/Resources/widget.html). Run this after editing any
# file under apps/widget/. The output is committed; CI fails on drift.
widget:
	bun run --filter widget build

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' clean -quiet
	rm -rf $(BUILD_DIR) $(BUILDS_DIR)

test: sponsor-config
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' -configuration Debug \
		-derivedDataPath '$(TEST_DERIVED_DATA)' \
		-only-testing WolfWaveTests \
		$(LOCAL_SIGN) \
		test 2>/dev/null | scripts/check-test-results.sh

test-verbose: sponsor-config
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' -configuration Debug \
		-derivedDataPath '$(TEST_DERIVED_DATA)' \
		-only-testing WolfWaveTests \
		test 2>/dev/null | tee /dev/stderr | scripts/check-test-results.sh

# XCUITests: launches the real app and drives its windows. Kept on its own
# scheme and out of every `-only-testing WolfWaveTests` target above, so the
# release path's `make test-ci` stays unit-only and is never gated on a UI run.
#
# Needs a real signing identity (an unsigned app cannot be launched and attached
# to) and its own DerivedData, same as the unit targets, so the signed Debug app
# Xcode installs is left alone. The app isolates itself once launched: see
# `UITestMode` for the storage and service seams the launch environment trips.
test-ui: sponsor-config
	@bash scripts/check-ui-test-preflight.sh
	xcodebuild -project $(PROJECT) -scheme WolfWaveUITests \
		-destination '$(DESTINATION)' -configuration Debug \
		-derivedDataPath '$(TEST_DERIVED_DATA)' \
		-parallel-testing-enabled NO \
		$(UI_SIGN) \
		test

# The single test entry point for CI. All three workflows (CI, Release,
# Nightly) run exactly this, so a green `make test-ci` locally means the same
# thing it means on a runner.
#
# Serial testing is cheap insurance against the macos-26 runner's historical
# malloc nano-zone abort of the xctest host (paired with MallocNanoZone=0 in
# the workflows); that runner bug is fixed, but the guard stays.
test-ci: sponsor-config
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' -configuration Debug \
		-derivedDataPath '$(TEST_DERIVED_DATA)' \
		-clonedSourcePackagesDirPath SourcePackages \
		-only-testing WolfWaveTests \
		-parallel-testing-enabled NO \
		-disable-concurrent-destination-testing \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO \
		-resultBundlePath TestResults.xcresult \
		test

# Regenerate every committed generated artifact, then fail if any of them moved.
# Mirrors the CI drift gate; run it before pushing a change to tokens.json,
# apps/widget/, or FUNDING.yml.
check-drift: sponsor-config
	@bun turbo run build --filter=widget
	@bash scripts/check-generated-drift.sh

# Full SwiftLint pass against the committed baseline. Hard errors block while
# advisory warning debt stays visible. Mirrors the CI `lint` job.
lint:
	@if ! command -v docker >/dev/null 2>&1; then \
		echo "❌ Docker not found. Install Docker Desktop."; exit 1; fi
	$(SWIFTLINT_DOCKER) lint --config .swiftlint.yml --baseline swiftlint-baseline.json

# Regenerate the SwiftLint baseline of grandfathered legacy violations.
# The baseline is a ratchet: it should only ever SHRINK as legacy violations
# get fixed. Regenerate and commit after any change that moves code between
# files or shifts line numbers (the baseline is keyed by file + line).
lint-baseline:
	@if ! command -v docker >/dev/null 2>&1; then \
		echo "❌ Docker not found. Install Docker Desktop."; exit 1; fi
	$(SWIFTLINT_DOCKER) lint --config .swiftlint.yml --write-baseline swiftlint-baseline.json

# Blocking crash-class gate: force-unwrap / try! / as! on production source.
# Mirrors the CI `lint-crash-safety` job. Must stay clean.
lint-crash-safety:
	@if ! command -v docker >/dev/null 2>&1; then \
		echo "❌ Docker not found. Install Docker Desktop."; exit 1; fi
	$(SWIFTLINT_DOCKER) lint --strict --config .swiftlint-crash-safety.yml

# Blocking header gate: every Swift file must carry the canonical Xcode header
# that IDETemplateMacros.plist generates, with a Created-by date matching the
# file's git creation date. Mirrors the CI `lint-headers` job.
lint-headers:
	node scripts/check-headers.mjs

update-deps:
	xcodebuild -project $(PROJECT) -resolvePackageDependencies -quiet

open-xcode:
	open $(PROJECT)

ci: test-ci

# ---------------------------------------------------------------------------
# Release build + DMG
# ---------------------------------------------------------------------------
prod-build: sponsor-config
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
		codesign --deep --force --options runtime --timestamp \
			--sign "Developer ID Application" "$$APP_PATH"; \
		echo "✅ Signed with Developer ID"; \
	else \
		echo "⚠️  No Developer ID cert found. DMG will be development-signed"; \
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
# Same script the Release and Nightly workflows run, so a local notarization
# failure reproduces the CI one (including the notary-log dump on rejection).
notarize:
	@if [ ! -f $(BUILDS_DIR)/$(DMG_NAME) ]; then \
		echo "❌ $(BUILDS_DIR)/$(DMG_NAME) not found. Run 'make prod-build' first."; exit 1; fi
	@if [ -z "$(APPLE_ID)" ] || [ -z "$(APPLE_TEAM_ID)" ] || [ -z "$(APPLE_APP_PASSWORD)" ]; then \
		echo "❌ APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_PASSWORD must all be set."; \
		echo "   Usage: APPLE_ID=... APPLE_TEAM_ID=... APPLE_APP_PASSWORD=... make notarize"; \
		exit 1; fi
	@APPLE_ID="$(APPLE_ID)" \
		APPLE_TEAM_ID="$(APPLE_TEAM_ID)" \
		APPLE_APP_PASSWORD="$(APPLE_APP_PASSWORD)" \
		bash scripts/notarize-dmg.sh "$(BUILDS_DIR)/$(DMG_NAME)"

verify-notarize:
	@if [ ! -f $(BUILDS_DIR)/$(DMG_NAME) ]; then \
		echo "❌ $(BUILDS_DIR)/$(DMG_NAME) not found."; exit 1; fi
	@echo "🔍 Verifying notarization..."
	spctl --assess --type open --context context:primary-signature $(BUILDS_DIR)/$(DMG_NAME)
	@echo "✅ Notarization verified: $(BUILDS_DIR)/$(DMG_NAME)"
