# WolfWave maintenance commands

PROJECT=wolfwave.xcodeproj
SCHEME=WolfWave

.PHONY: help build clean test update-deps open-xcode env-check ci

help:
	@echo "Available targets:"
	@echo "  build          Build the app via xcodebuild"
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
