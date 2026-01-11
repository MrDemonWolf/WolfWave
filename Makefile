# WolfWave maintenance commands

PROJECT=src/wolfwave/wolfwave.xcodeproj
SCHEME=WolfWave

.PHONY: help build clean test update-deps open-xcode env-check ci prod-build prod-install

help:
	@echo "Available targets:"
	@echo "  build          Build the app via xcodebuild (Debug)"
	@echo "  prod-build     Build Release version for testing"
	@echo "  prod-install   Build Release and install to /Applications"
	@echo "  clean          Clean build artifacts"
	@echo "  test           Run tests (if a test target exists)"
	@echo "  update-deps    Resolve SwiftPM dependencies"
	@echo "  open-xcode     Open the Xcode project"
	@echo "  env-check      Check required environment vars"
	@echo "  ci             Run build (CI-friendly)"

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug build -quiet

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean -quiet

# Runs tests if the scheme has a Test action. Will not fail CI if none.
# macOS destination is inferred; adjust if needed.
test:
	- xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug test -quiet

update-deps:
	xcodebuild -project $(PROJECT) -resolvePackageDependencies -quiet

open-xcode:
	open $(PROJECT)

env-check:
	@if [ -z "$$TWITCH_CLIENT_ID" ]; then \
		echo "TWITCH_CLIENT_ID is NOT set (required for Twitch auth)"; \
	else \
		echo "TWITCH_CLIENT_ID is set: $$TWITCH_CLIENT_ID"; \
	fi

ci: build

prod-build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release build -quiet
	@echo "✅ Release build complete. App located at: build/Release/WolfWave.app"

prod-install: prod-build
	@echo "📦 Installing WolfWave to /Applications..."
	@rm -rf /Applications/WolfWave.app
	@cp -r build/Release/WolfWave.app /Applications/
	@echo "✅ WolfWave installed to /Applications"
	@echo "🚀 Launch with: open /Applications/WolfWave.app
