# WolfWave maintenance commands

PROJECT=src/wolfwave.xcodeproj
SCHEME=WolfWave

.PHONY: help build clean test update-deps open-xcode ci prod-build prod-install

help:
	@echo "Available targets:"
	@echo "  build          Build the app via xcodebuild (Debug)"
	@echo "  prod-build     Build Release version for testing"
	@echo "  prod-install   Build Release and install to /Applications"
	@echo "  clean          Clean build artifacts"
	@echo "  test           Run tests (if a test target exists)"
	@echo "  update-deps    Resolve SwiftPM dependencies"
	@echo "  open-xcode     Open the Xcode project"
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

ci: build



prod-build:
	@TWITCH_CLIENT_ID="$(TWITCH_CLIENT_ID)" xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -derivedDataPath build build -quiet
	@BUILD_DIR=$$(TWITCH_CLIENT_ID="$(TWITCH_CLIENT_ID)" xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -derivedDataPath build -showBuildSettings | awk -F'= ' '/CONFIGURATION_BUILD_DIR/ {print $$2; exit}'); \
	WRAPPER=$$(TWITCH_CLIENT_ID="$(TWITCH_CLIENT_ID)" xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -derivedDataPath build -showBuildSettings | awk -F'= ' '/WRAPPER_NAME/ {print $$2; exit}'); \
	APP_PATH=$$BUILD_DIR/$$WRAPPER; \
	if [ -z "$$BUILD_DIR" ] || [ -z "$$WRAPPER" ] || [ ! -d "$$APP_PATH" ]; then echo "❌ Release build finished but .app not found at: $$APP_PATH"; exit 1; fi; \
	echo "✅ Release build complete. App located at: $$APP_PATH"
	@mkdir -p builds
	@echo "📦 Creating fancy DMG in builds/ ..."
	@rm -rf builds/staging || true
	@mkdir -p builds/staging
	@APP_PATH=$$(TWITCH_CLIENT_ID="$(TWITCH_CLIENT_ID)" xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -derivedDataPath build -showBuildSettings | awk -F'= ' '/CONFIGURATION_BUILD_DIR/ {dir=$$2} /WRAPPER_NAME/ {name=$$2} END {print dir "/" name}'); \
	if [ -z "$$APP_PATH" ] || [ ! -d "$$APP_PATH" ]; then echo "❌ .app not found at: $$APP_PATH; aborting"; exit 1; fi; \
	cp -R "$$APP_PATH" builds/staging/
	@# create an Applications link in staging (will be recreated inside mounted image for correct Finder metadata)
	@ln -sf /Applications builds/staging/Applications || true
	@if [ -f assets/dmg-background.png ]; then \
		mkdir -p builds/staging/.background; \
		cp assets/dmg-background.png builds/staging/.background/background.png; \
	fi
	@if [ -f assets/VolumeIcon.icns ]; then \
		cp assets/VolumeIcon.icns builds/staging/.VolumeIcon.icns; \
	fi
	# create a read-write image we can customize
	set -e; hdiutil create -srcfolder builds/staging -volname "WolfWave" -fs HFS+ -format UDRW -ov "builds/WolfWave-temp.dmg" >/dev/null; \
	# attach and capture mount point
	MOUNTPOINT=$$(hdiutil attach -readwrite -noverify -noautoopen "builds/WolfWave-temp.dmg" | egrep '/Volumes/' | sed -n '1p' | awk '{print $$3}'); \
	sleep 1; \
	# attach and capture mount point
	MOUNTPOINT=$$(hdiutil attach -readwrite -noverify -noautoopen "builds/WolfWave-temp.dmg" | egrep '/Volumes/' | sed -n '1p' | awk '{print $$3}'); \
	sleep 1; \
	# create Applications alias inside the mounted image so Finder stores proper metadata/icon
	osascript -e 'tell application "Finder" to make alias file to POSIX file "/Applications" at POSIX file "'"$$MOUNTPOINT"'"' || true; \
	# configure Finder window via AppleScript (use -e to avoid heredoc parsing issues)
	osascript \
		-e 'tell application "Finder"' \
		-e 'tell disk "WolfWave"' \
		-e 'open' \
		-e 'set current view of container window to icon view' \
		-e 'set toolbar visible of container window to false' \
		-e 'set statusbar visible of container window to false' \
		-e 'set the bounds of container window to {100, 100, 660, 360}' \
		-e 'set viewOptions to the icon view options of container window' \
		-e 'set arrangement of viewOptions to not arranged' \
		-e 'set icon size of viewOptions to 128' \
		-e 'try' \
		-e 'set background picture of viewOptions to file ".background:background.png"' \
		-e 'end try' \
		-e 'try' \
		-e 'set position of item "WolfWave.app" of container window to {140, 170}' \
		-e 'end try' \
		-e 'try' \
		-e 'set position of item "Applications" of container window to {490, 170}' \
		-e 'end try' \
		-e 'close' \
		-e 'open' \
		-e 'delay 1' \
		-e 'end tell' \
		-e 'end tell' || true
	# flush and detach
	sync; sleep 1; hdiutil detach "$$MOUNTPOINT" -quiet || true; \
	# If a custom volume icon was provided, attach again to set it
	if [ -f builds/staging/.VolumeIcon.icns ]; then \
		MOUNTPOINT2=$$(hdiutil attach -readwrite -noverify -noautoopen "builds/WolfWave-temp.dmg" | egrep '/Volumes/' | sed -n '1p' | awk '{print $$3}'); \
		cp builds/staging/.VolumeIcon.icns "$$MOUNTPOINT2"/.VolumeIcon.icns || true; \
		/usr/bin/SetFile -a C "$$MOUNTPOINT2" || true; \
		hdiutil detach "$$MOUNTPOINT2" -quiet || true; \
	fi; \
	# convert to compressed, read-only DMG
	# ensure any leftover mounts are detached
	MOUNTID=$$(hdiutil info | awk '/\/Volumes\/WolfWave/ {print $$1; exit}'); \
	if [ -n "$$MOUNTID" ]; then hdiutil detach "$$MOUNTID" -force || true; fi; \
	sync; sleep 1; \
	# convert to compressed, read-only DMG; keep output visible for troubleshooting
	if hdiutil convert "builds/WolfWave-temp.dmg" -format UDZO -imagekey zlib-level=9 -o builds/WolfWave.dmg; then \
		rm -f "builds/WolfWave-temp.dmg"; \
		rm -rf builds/staging; \
		echo "✅ DMG created at: builds/WolfWave.dmg"; \
	else \
		echo "❌ hdiutil convert failed. preserved temp image at: builds/WolfWave-temp.dmg"; \
		hdiutil info | egrep '/Volumes/|builds/WolfWave-temp.dmg' || true; \
		exit 1; \
	fi; \

prod-install: prod-build
	@echo "📦 Installing WolfWave to /Applications..."
	@APP_PATH=$$(find build -type d -name "*.app" -maxdepth 4 -print -quit); \
	if [ -z "$$APP_PATH" ]; then echo "❌ .app not found; run 'make prod-build' first"; exit 1; fi; \
	rm -rf /Applications/WolfWave.app; \
	cp -R "$$APP_PATH" /Applications/; \
	echo "✅ WolfWave installed to /Applications"; \
	echo "🚀 Launch with: open /Applications/WolfWave.app"
