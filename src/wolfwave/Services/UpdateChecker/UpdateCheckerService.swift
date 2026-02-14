//
//  UpdateCheckerService.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/12/26.
//

/// Service that periodically checks GitHub Releases for newer versions of WolfWave.
///
/// Queries the GitHub Releases API on launch (after a delay) and every 24 hours,
/// compares the latest release tag against the current bundle version, and posts
/// a `updateStateChanged` notification when a newer version is found.
///
/// Thread Safety:
/// - Uses `NSLock` to protect shared mutable state (`latestUpdateInfo`, `isChecking`).
/// - All URLSession work uses async/await on cooperative threads.
/// - Timer runs on the main RunLoop.

import Foundation

// MARK: - Supporting Types

/// How WolfWave was installed on this machine.
enum InstallMethod: String {
    /// Installed via Homebrew Cask
    case homebrew
    /// Installed via DMG download (or unknown path)
    case dmg
}

/// Information about an available update.
struct UpdateInfo {
    /// The latest version string (e.g. "1.1.0")
    let latestVersion: String
    /// Whether this version is newer than the running app
    let isUpdateAvailable: Bool
    /// Direct download URL for the DMG asset (nil if not found)
    let downloadURL: URL?
    /// Browser URL for the release page
    let releaseURL: URL?
    /// Release notes / body markdown
    let releaseNotes: String?
    /// Detected install method for this machine
    let installMethod: InstallMethod
}

// MARK: - UpdateCheckerService

final class UpdateCheckerService: @unchecked Sendable {
    // MARK: - Properties

    /// Lock protecting mutable state accessed from multiple threads.
    private let lock = NSLock()

    /// Most recent update check result.
    private var _latestUpdateInfo: UpdateInfo?
    var latestUpdateInfo: UpdateInfo? {
        lock.lock()
        defer { lock.unlock() }
        return _latestUpdateInfo
    }

    /// Whether a check is currently in progress.
    private var _isChecking = false
    var isChecking: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isChecking
    }

    /// Periodic check timer (runs on main RunLoop).
    private var checkTimer: Timer?

    /// Shared URLSession configured with timeout.
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = AppConstants.Update.requestTimeout
        config.timeoutIntervalForResource = AppConstants.Update.requestTimeout
        return URLSession(configuration: config)
    }()

    // MARK: - Current App Version

    /// The running app's marketing version from the bundle.
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    // MARK: - Periodic Checking

    /// Starts periodic update checking: delayed first check, then every 24 hours.
    ///
    /// Respects the `updateCheckEnabled` user preference. If the preference has never been
    /// set, defaults to enabled. Skips the check if one was performed within the last 24 hours.
    func startPeriodicChecking() {
        guard UserDefaults.standard.object(forKey: AppConstants.UserDefaults.updateCheckEnabled) == nil
                || UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.updateCheckEnabled) else {
            Log.info("UpdateChecker: Automatic checking is disabled", category: "Update")
            return
        }

        Log.info("UpdateChecker: Scheduling periodic checks (first in \(Int(AppConstants.Update.launchCheckDelay))s, then every 24h)", category: "Update")

        // Delayed first check
        DispatchQueue.main.asyncAfter(deadline: .now() + AppConstants.Update.launchCheckDelay) { [weak self] in
            guard let self else { return }
            Task {
                await self.checkForUpdates()
            }
            self.scheduleTimer()
        }
    }

    /// Stops the periodic check timer.
    func stopPeriodicChecking() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    /// Schedules the repeating 24-hour timer on the main RunLoop.
    private func scheduleTimer() {
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: AppConstants.Update.checkInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.checkForUpdates()
            }
        }
    }

    // MARK: - Check For Updates

    /// Performs an update check against the GitHub Releases API.
    ///
    /// Fetches the latest release, parses `tag_name`, compares versions, stores
    /// the result, and posts an `updateStateChanged` notification.
    ///
    /// - Returns: The update info, or nil if the check failed.
    @discardableResult
    func checkForUpdates() async -> UpdateInfo? {
        guard beginCheck() else {
            Log.debug("UpdateChecker: Check already in progress, skipping", category: "Update")
            return nil
        }

        defer { endCheck() }

        // Skip if checked recently (within 24h) — unless this is a manual check
        if shouldSkipBasedOnInterval() {
            Log.debug("UpdateChecker: Skipping check, last check was within 24h", category: "Update")
            return latestUpdateInfo
        }

        Log.info("UpdateChecker: Checking for updates...", category: "Update")

        guard let url = URL(string: AppConstants.URLs.githubReleasesAPI) else {
            Log.error("UpdateChecker: Invalid API URL", category: "Update")
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("WolfWave/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                Log.error("UpdateChecker: GitHub API returned status \(statusCode)", category: "Update")
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                Log.error("UpdateChecker: Failed to parse JSON response", category: "Update")
                return nil
            }

            let info = parseRelease(json)

            // Store result and update last check date
            storeUpdateInfo(info)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: AppConstants.UserDefaults.updateLastCheckDate)

            if info.isUpdateAvailable {
                Log.info("UpdateChecker: Update available — v\(info.latestVersion) (current: \(currentVersion))", category: "Update")
            } else {
                Log.info("UpdateChecker: App is up to date (\(currentVersion))", category: "Update")
            }

            // Post notification on main thread
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name(AppConstants.Notifications.updateStateChanged),
                    object: nil,
                    userInfo: [
                        "isUpdateAvailable": info.isUpdateAvailable,
                        "latestVersion": info.latestVersion,
                    ]
                )
            }

            return info
        } catch {
            Log.error("UpdateChecker: Network error — \(error.localizedDescription)", category: "Update")
            return nil
        }
    }

    /// Atomically marks a check as in-progress. Returns false if already checking.
    private func beginCheck() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !_isChecking else { return false }
        _isChecking = true
        return true
    }

    /// Atomically marks the check as finished.
    private func endCheck() {
        lock.lock()
        _isChecking = false
        lock.unlock()
    }

    /// Thread-safe storage of latest update info.
    private func storeUpdateInfo(_ info: UpdateInfo) {
        lock.lock()
        _latestUpdateInfo = info
        lock.unlock()
    }

    // MARK: - Parsing

    /// Parses a GitHub release JSON object into an `UpdateInfo`.
    private func parseRelease(_ json: [String: Any]) -> UpdateInfo {
        let tagName = (json["tag_name"] as? String) ?? ""
        let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        let htmlURL = (json["html_url"] as? String).flatMap { URL(string: $0) }
        let body = json["body"] as? String
        let installMethod = detectInstallMethod()

        // Find DMG asset download URL
        var downloadURL: URL?
        if let assets = json["assets"] as? [[String: Any]] {
            for asset in assets {
                if let name = asset["name"] as? String,
                   name.hasSuffix(".dmg"),
                   let urlStr = asset["browser_download_url"] as? String {
                    downloadURL = URL(string: urlStr)
                    break
                }
            }
        }

        let isNewer = isNewerVersion(latestVersion, than: currentVersion)

        return UpdateInfo(
            latestVersion: latestVersion,
            isUpdateAvailable: isNewer,
            downloadURL: downloadURL,
            releaseURL: htmlURL,
            releaseNotes: body,
            installMethod: installMethod
        )
    }

    // MARK: - Install Method Detection

    /// Detects whether WolfWave was installed via Homebrew or DMG.
    ///
    /// Checks the app bundle path for Homebrew-related directories.
    func detectInstallMethod() -> InstallMethod {
        let path = Bundle.main.bundlePath
        let homebrewPaths = ["/opt/homebrew/", "/usr/local/Cellar/", "/Homebrew/"]
        for prefix in homebrewPaths {
            if path.contains(prefix) {
                return .homebrew
            }
        }
        return .dmg
    }

    // MARK: - Version Comparison

    /// Compares two semantic version strings (major.minor.patch).
    ///
    /// - Parameters:
    ///   - candidate: The version to check (e.g. "1.2.0").
    ///   - current: The version to compare against (e.g. "1.1.0").
    /// - Returns: True if `candidate` is strictly newer than `current`.
    ///
    /// - Note: Pre-release identifiers (e.g. "-beta", "-rc.1") are ignored by the
    ///   current implementation — `compactMap { Int($0) }` strips non-numeric segments,
    ///   so "1.1.0-beta" is treated identically to "1.1.0". If pre-release GitHub
    ///   releases need to be distinguished, consider adopting full SemVer parsing.
    func isNewerVersion(_ candidate: String, than current: String) -> Bool {
        let candidateParts = candidate.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }

        let maxLen = max(candidateParts.count, currentParts.count)
        for i in 0..<maxLen {
            let c = i < candidateParts.count ? candidateParts[i] : 0
            let r = i < currentParts.count ? currentParts[i] : 0
            if c > r { return true }
            if c < r { return false }
        }
        return false
    }

    // MARK: - Helpers

    /// Whether we should skip a check because the last one was recent enough.
    private func shouldSkipBasedOnInterval() -> Bool {
        let lastCheck = UserDefaults.standard.double(forKey: AppConstants.UserDefaults.updateLastCheckDate)
        guard lastCheck > 0 else { return false }
        let elapsed = Date().timeIntervalSince1970 - lastCheck
        return elapsed < AppConstants.Update.checkInterval
    }
}
