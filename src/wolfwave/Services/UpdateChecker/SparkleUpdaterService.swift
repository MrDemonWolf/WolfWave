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
/// - All Sparkle APIs are called on the main thread
/// - Notification posting is already main-thread safe

import Foundation
import Sparkle

// MARK: - SparkleUpdaterService

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
            updater?.automaticallyChecksForUpdates = newValue
            UserDefaults.standard.set(newValue, forKey: AppConstants.UserDefaults.updateCheckEnabled)
            Log.info("SparkleUpdater: Automatic checking \(newValue ? "enabled" : "disabled")", category: "Update")
        }
    }
    
    /// Update check interval in seconds (default: 24 hours)
    var updateCheckInterval: TimeInterval {
        get {
            updater?.updateCheckInterval ?? AppConstants.Update.checkInterval
        }
        set {
            updater?.updateCheckInterval = newValue
            Log.info("SparkleUpdater: Check interval set to \(Int(newValue))s", category: "Update")
        }
    }
    
    /// Whether the app was installed via Homebrew (Sparkle should be disabled in this case)
    private let isHomebrewInstall: Bool
    
    // MARK: - Initialization
    
    override init() {
        // Detect install method before initializing Sparkle
        let path = Bundle.main.bundlePath
        let homebrewPaths = ["/opt/homebrew/", "/usr/local/Cellar/", "/Homebrew/"]
        self.isHomebrewInstall = homebrewPaths.contains { path.contains($0) }
        
        super.init()
        
        if isHomebrewInstall {
            Log.info("SparkleUpdater: Homebrew installation detected — Sparkle disabled", category: "Update")
            return
        }
        
        setupSparkle()
    }
    
    // MARK: - Setup
    
    /// Initializes and configures the Sparkle updater controller.
    private func setupSparkle() {
        Log.info("SparkleUpdater: Initializing Sparkle framework", category: "Update")
        
        // Create the updater controller
        // startingUpdater: true means Sparkle will start checking immediately if enabled
        // updaterDelegate: self allows us to customize behavior
        // userDriverDelegate: nil uses Sparkle's default UI
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
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
            
            // Automatically download updates in background (user still confirms install)
            updater.automaticallyDownloadsUpdates = false
            
            Log.info("SparkleUpdater: Configuration complete (auto-check: \(checkEnabled), interval: \(Int(AppConstants.Update.checkInterval))s)", category: "Update")
        }
    }
    
    // MARK: - Public API
    
    /// Manually triggers an update check.
    ///
    /// Shows Sparkle's update dialog with results. If an update is available,
    /// the user can choose to download and install it immediately.
    func checkForUpdates() {
        guard !isHomebrewInstall else {
            Log.warn("SparkleUpdater: Manual check ignored — app is managed by Homebrew", category: "Update")
            return
        }
        
        guard let updater = updater else {
            Log.error("SparkleUpdater: Cannot check for updates — updater not initialized", category: "Update")
            return
        }
        
        Log.info("SparkleUpdater: Manual update check triggered", category: "Update")
        updater.checkForUpdates()
    }
    
    /// Checks for updates silently in the background.
    ///
    /// If an update is available, Sparkle will download it and notify the user.
    /// No dialog is shown if the app is already up to date.
    func checkForUpdatesInBackground() {
        guard !isHomebrewInstall else { return }
        
        guard let updater = updater else {
            Log.error("SparkleUpdater: Cannot check for updates — updater not initialized", category: "Update")
            return
        }
        
        Log.debug("SparkleUpdater: Background update check triggered", category: "Update")
        updater.checkForUpdatesInBackground()
    }
    
    /// Returns the URL for the Sparkle appcast feed.
    ///
    /// This is typically set in Info.plist as `SUFeedURL`, but can also be
    /// resolved dynamically from Config.xcconfig.
    var feedURL: URL? {
        updater?.feedURL
    }
}

// MARK: - SPUUpdaterDelegate

extension SparkleUpdaterService: SPUUpdaterDelegate {
    /// Called when Sparkle is about to check for updates.
    ///
    /// We can use this to post notifications, update UI, or cancel the check.
    func updater(_ updater: SPUUpdater, willScheduleUpdateCheckAfterDelay delay: TimeInterval) {
        Log.debug("SparkleUpdater: Next check scheduled in \(Int(delay))s", category: "Update")
    }
    
    /// Called when an update check finds a newer version.
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Log.info("SparkleUpdater: Update found — v\(version)", category: "Update")
        
        // Post notification so UI can update
        DispatchQueue.main.async {
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
    }
    
    /// Called when an update check completes without finding a newer version.
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Log.info("SparkleUpdater: No update available — app is up to date", category: "Update")
        
        // Post notification so UI can update
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name(AppConstants.Notifications.updateStateChanged),
                object: nil,
                userInfo: [
                    "isUpdateAvailable": false,
                    "latestVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
                ]
            )
        }
    }
    
    /// Called when an update check fails (network error, malformed feed, etc.)
    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        Log.error("SparkleUpdater: Failed to download update — \(error.localizedDescription)", category: "Update")
    }
    
    /// Called when an update is about to be installed.
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Log.info("SparkleUpdater: Installing update — v\(version)", category: "Update")
    }
    
    /// Determines whether Sparkle should postpone an update that's ready to install.
    ///
    /// Return true to delay installation (e.g., if user is in the middle of something).
    /// Return false to allow installation to proceed.
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        // For now, allow installation immediately
        // You could add logic here to check if user is streaming, etc.
        return false
    }
    
    /// Called after an update has been successfully installed and the app is about to relaunch.
    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        Log.info("SparkleUpdater: Update installed successfully — relaunching app", category: "Update")
    }
    
    /// Allows customization of update permission prompts.
    ///
    /// Return true to show Sparkle's default permission dialog on first launch.
    /// Return false to skip it (we'll handle this in our own onboarding).
    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool {
        // Don't show Sparkle's default prompt — we handle this in onboarding
        return false
    }
    
    /// Called when the user is prompted for update permission.
    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate updateItem: SUAppcastItem, state: SPUUserUpdateState) {
        switch choice {
        case .skip:
            Log.info("SparkleUpdater: User skipped update v\(updateItem.displayVersionString)", category: "Update")
        case .install:
            Log.info("SparkleUpdater: User chose to install update v\(updateItem.displayVersionString)", category: "Update")
        case .dismiss:
            Log.info("SparkleUpdater: User dismissed update dialog", category: "Update")
        @unknown default:
            break
        }
    }
}
