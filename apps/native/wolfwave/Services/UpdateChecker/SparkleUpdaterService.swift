//
//  SparkleUpdaterService.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 3/16/26.
//

/// Service that manages automatic updates via the Sparkle framework.
///
/// Sparkle handles:
/// - Automatic update checking on a configurable schedule
/// - Downloading and verifying update packages
/// - Installing updates with user confirmation
/// - Delta updates (only downloading changed files)
/// - Code signature verification for security
///
/// Architecture:
/// - Wraps Sparkle's `SPUStandardUpdaterController`
/// - Provides a simplified API for the app to trigger manual checks
/// - Respects user preferences for automatic checking
/// - Posts notifications to keep UI in sync
///
/// Thread Safety:
/// - The class is `@MainActor` (matches `SPUUpdaterDelegate`'s `NS_SWIFT_UI_ACTOR`).
/// - All Sparkle APIs and notification posts run on the main actor.
///
/// DEBUG builds:
/// - Sparkle is initialized with `startingUpdater: false` (no background checks).
/// - The delegate points the feed at the bundled `dev-appcast.xml` so manual
///   "Check for Updates" exercises the full Sparkle UI against a dummy entry.

import Foundation
import Sparkle

// MARK: - SparkleUpdaterService

@MainActor
final class SparkleUpdaterService: NSObject {
    // MARK: - Properties

    /// Sparkle's updater controller (manages the update process)
    private var updaterController: SPUStandardUpdaterController?

    /// The updater instance (for manual checks and configuration)
    private var updater: SPUUpdater? {
        updaterController?.updater
    }

    /// Whether automatic update checking is enabled
    var automaticCheckEnabled: Bool {
        get {
            updater?.automaticallyChecksForUpdates ?? true
        }
        set {
            guard let updater else {
                Log.warn("SparkleUpdaterService: automaticCheckEnabled ignored — updater not initialized", category: "Update")
                return
            }
            updater.automaticallyChecksForUpdates = newValue
            UserDefaults.standard.set(newValue, forKey: AppConstants.UserDefaults.updateCheckEnabled)
            Log.info("SparkleUpdaterService: Automatic checking \(newValue ? "enabled" : "disabled")", category: "Update")
        }
    }

    /// Update check interval in seconds (default: 24 hours)
    var updateCheckInterval: TimeInterval {
        get {
            updater?.updateCheckInterval ?? AppConstants.Update.checkInterval
        }
        set {
            guard let updater else {
                Log.warn("SparkleUpdaterService: updateCheckInterval ignored — updater not initialized", category: "Update")
                return
            }
            updater.updateCheckInterval = newValue
            Log.info("SparkleUpdaterService: Check interval set to \(Int(newValue))s", category: "Update")
        }
    }

    /// Whether the app was installed via Homebrew (Sparkle should be disabled in this case)
    private let isHomebrewInstall: Bool

    /// True when Sparkle is wired and ready to drive a real update check.
    /// False for Homebrew installs or when `setupSparkle()` never produced an `SPUUpdater`.
    var isAvailable: Bool { !isHomebrewInstall && updater != nil }

    // MARK: - Initialization

    override init() {
        // Detect install method before initializing Sparkle
        self.isHomebrewInstall = Bundle.main.isHomebrewInstall

        super.init()

        if isHomebrewInstall {
            Log.info("SparkleUpdaterService: Homebrew installation detected — Sparkle disabled", category: "Update")
            return
        }

        setupSparkle()
    }

    // MARK: - Setup

    /// Initializes and configures the Sparkle updater controller.
    private func setupSparkle() {
        Log.info("SparkleUpdaterService: Initializing Sparkle framework", category: "Update")

        // In DEBUG, instantiate the controller but don't start the background
        // update cycle — manual "Check for Updates" still works and is routed
        // at the bundled dev-appcast.xml via `feedURLString(for:)`.
        #if DEBUG
        let startingUpdater = false
        #else
        let startingUpdater = true
        #endif

        updaterController = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: self,
            userDriverDelegate: nil
        )

        // Configure updater preferences
        if let updater = updater {
            // Respect user's update check preference (defaults to true)
            let checkEnabled = UserDefaults.standard.object(forKey: AppConstants.UserDefaults.updateCheckEnabled) as? Bool ?? true
            updater.automaticallyChecksForUpdates = checkEnabled

            // Set check interval (24 hours)
            updater.updateCheckInterval = AppConstants.Update.checkInterval

            // Require explicit user consent before downloading. Combined with
            // `updaterShouldPromptForPermissionToCheck` returning false, this
            // ensures Sparkle never moves bytes onto the user's disk until they
            // click "Install" in the update dialog. Auto-download would silently
            // commit network + storage before consent.
            updater.automaticallyDownloadsUpdates = false

            Log.info("SparkleUpdaterService: Configuration complete (auto-check: \(checkEnabled), interval: \(Int(AppConstants.Update.checkInterval))s, starting: \(startingUpdater))", category: "Update")
        }
    }

    // MARK: - Public API

    /// Manually triggers an update check.
    ///
    /// Shows Sparkle's update dialog with results. If an update is available,
    /// the user can choose to download and install it immediately.
    ///
    /// - Returns: `true` when Sparkle handled the request and presented its UI;
    ///   `false` when the call was a no-op (Homebrew install or uninitialized
    ///   updater) so callers can open a fallback URL instead of failing silently.
    @discardableResult
    func checkForUpdates() -> Bool {
        guard !isHomebrewInstall else {
            Log.warn("SparkleUpdaterService: Manual check ignored — app is managed by Homebrew", category: "Update")
            return false
        }

        guard let updater = updater else {
            Log.error("SparkleUpdaterService: Cannot check for updates — updater not initialized", category: "Update")
            return false
        }

        Log.info("SparkleUpdaterService: Manual update check triggered", category: "Update")
        updater.checkForUpdates()
        return true
    }

    /// Checks for updates silently in the background.
    ///
    /// If an update is available, Sparkle will download it and notify the user.
    /// No dialog is shown if the app is already up to date.
    func checkForUpdatesInBackground() {
        guard !isHomebrewInstall else { return }

        #if DEBUG
        Log.debug("SparkleUpdaterService: Background check skipped — debug build", category: "Update")
        #else
        guard let updater = updater else {
            Log.error("SparkleUpdaterService: Cannot check for updates — updater not initialized", category: "Update")
            return
        }

        Log.debug("SparkleUpdaterService: Background update check triggered", category: "Update")
        updater.checkForUpdatesInBackground()
        #endif
    }

    /// Returns the URL for the Sparkle appcast feed.
    ///
    /// Resolved from `SUFeedURL` in Info.plist (release builds) or the
    /// bundled `dev-appcast.xml` (DEBUG builds, via `feedURLString(for:)`).
    var feedURL: URL? {
        #if DEBUG
        return Bundle.main.url(forResource: "dev-appcast", withExtension: "xml")
        #else
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String else {
            return nil
        }
        return URL(string: raw)
        #endif
    }
}

// MARK: - SPUUpdaterDelegate

extension SparkleUpdaterService: SPUUpdaterDelegate {
    /// Returns the appcast feed URL for the given updater.
    ///
    /// - DEBUG: returns the bundled `dev-appcast.xml` so manual checks
    ///   exercise the Sparkle UI against a dummy v99.0.0 entry.
    /// - Release: returns `nil` to use `SUFeedURL` from Info.plist.
    func feedURLString(for updater: SPUUpdater) -> String? {
        #if DEBUG
        return Bundle.main.url(forResource: "dev-appcast", withExtension: "xml")?.absoluteString
        #else
        return nil // Use SUFeedURL from Info.plist
        #endif
    }

    /// Called when Sparkle is about to check for updates.
    ///
    /// We can use this to post notifications, update UI, or cancel the check.
    func updater(_ updater: SPUUpdater, willScheduleUpdateCheckAfterDelay delay: TimeInterval) {
        Log.debug("SparkleUpdaterService: Next check scheduled in \(Int(delay))s", category: "Update")
    }

    /// Called when an update check finds a newer version.
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Log.info("SparkleUpdaterService: Update found — v\(version)", category: "Update")

        NotificationCenter.default.post(
            name: NSNotification.Name(AppConstants.Notifications.updateStateChanged),
            object: nil,
            userInfo: [
                "isUpdateAvailable": true,
                "latestVersion": version,
                "releaseURL": item.infoURL?.absoluteString ?? ""
            ]
        )
    }

    /// Called when an update check completes without finding a newer version.
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Log.info("SparkleUpdaterService: No update available — app is up to date", category: "Update")

        NotificationCenter.default.post(
            name: NSNotification.Name(AppConstants.Notifications.updateStateChanged),
            object: nil,
            userInfo: [
                "isUpdateAvailable": false,
                "latestVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
            ]
        )
    }

    /// Called when an update check fails (network error, malformed feed, etc.)
    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        Log.error("SparkleUpdaterService: Failed to download update — \(error.localizedDescription)", category: "Update")
    }

    /// Called when an update is about to be installed.
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Log.info("SparkleUpdaterService: Installing update — v\(version)", category: "Update")
    }

    /// Determines whether Sparkle should postpone an update that's ready to install.
    ///
    /// Return true to delay installation (e.g., if user is in the middle of something).
    /// Return false to allow installation to proceed.
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        return false
    }

    /// Called after an update has been successfully installed and the app is about to relaunch.
    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        Log.info("SparkleUpdaterService: Update installed successfully — relaunching app", category: "Update")
    }

    /// Allows customization of update permission prompts.
    ///
    /// Return false — `SUEnableAutomaticChecks` in Info.plist provides the
    /// answer, and onboarding handles user consent explicitly.
    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool {
        return false
    }

    /// Disables Sparkle's system-profile telemetry beam.
    ///
    /// Sparkle can attach OS version, CPU arch, and bundle metadata to the
    /// appcast request as query parameters. Returning an empty array opts out
    /// entirely so no environmental data leaves the user's machine on update
    /// checks. The release pipeline already publishes a static appcast, so the
    /// telemetry would only inform analytics — not update targeting.
    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? {
        return []
    }

    /// Called when the user is prompted for update permission.
    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate updateItem: SUAppcastItem, state: SPUUserUpdateState) {
        switch choice {
        case .skip:
            Log.info("SparkleUpdaterService: User skipped update v\(updateItem.displayVersionString)", category: "Update")
        case .install:
            Log.info("SparkleUpdaterService: User chose to install update v\(updateItem.displayVersionString)", category: "Update")
        case .dismiss:
            Log.info("SparkleUpdaterService: User dismissed update dialog", category: "Update")
        @unknown default:
            break
        }
    }
}
