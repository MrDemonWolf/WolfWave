//
//  SettingsBackupService.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-02.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Main-actor adapter that wires the pure `SettingsBackupCoder` to live app
/// state: it snapshots and writes `UserDefaults`, stamps the running app
/// version, and broadcasts the service notifications that non-view components
/// (Discord RPC, WebSocket server, song-request pipeline, etc.) listen for.
///
/// File dialogs (`NSSavePanel` / `NSOpenPanel`) stay in the view layer, mirroring
/// how `AdvancedSettingsView.exportLogs()` already presents panels. This type
/// performs no UI and no file I/O of its own. System-backed preferences are
/// applied through the injectable `SideEffects` adapter.
@MainActor
struct SettingsBackupService {
    /// Outcome of an import, surfaced to the user in the completion message.
    struct ApplySummary: Equatable {
        /// Number of portable preferences written.
        var restoredCount: Int
        /// Whether Twitch identity was restored and re-auth was triggered.
        var reconnectedTwitch: Bool
        /// The restored Twitch channel name, when reconnecting.
        var twitchChannel: String?
        /// Backup keys ignored because they are unknown, non-portable, or invalid.
        var ignoredCount: Int
        /// Non-fatal system-setting failures that need the user's attention.
        var warnings: [String]

        /// The correctly pluralized noun for a preference count
        /// (`preference` for 1, `preferences` otherwise). Shared by the import
        /// preview summary and the post-import confirmation message.
        static func preferenceNoun(_ count: Int) -> String {
            count == 1 ? "preference" : "preferences"
        }
    }

    /// Update preferences restored together so Sparkle is refreshed at most
    /// once after an import.
    struct UpdatePreferences: Equatable {
        var automaticCheckEnabled: Bool?
        var channel: UpdateChannel?
    }

    /// Small side-effect seam for preferences whose source of truth is not only
    /// UserDefaults. Tests inject closures; production delegates to native APIs.
    struct SideEffects {
        var isLaunchAtLoginEnabled: @MainActor () -> Bool
        var setLaunchAtLogin: @MainActor (Bool) -> LaunchAtLoginService.RegistrationOutcome
        var applyAppearance: @MainActor (String) -> Void
        var applyUpdatePreferences: @MainActor (UpdatePreferences) -> Void

        static let live = SideEffects(
            isLaunchAtLoginEnabled: { LaunchAtLoginService.isEnabled },
            setLaunchAtLogin: { LaunchAtLoginService.setEnabled($0) },
            applyAppearance: { AppearanceController.apply($0) },
            applyUpdatePreferences: { preferences in
                guard let updater = AppDelegate.shared?.sparkleUpdater else { return }
                #if !DEBUG
                if let enabled = preferences.automaticCheckEnabled {
                    updater.automaticCheckEnabled = enabled
                }
                #endif
                if let channel = preferences.channel {
                    updater.channel = channel
                    updater.recheckAfterChannelChange()
                }
            }
        )
    }

    private struct SideEffectResult {
        var failedKeys: Set<String> = []
        var warnings: [String] = []
    }

    private let defaults: Foundation.UserDefaults
    private let center: NotificationCenter
    private let sideEffects: SideEffects
    private let coder = SettingsBackupCoder()

    init(
        defaults: Foundation.UserDefaults = .standard,
        center: NotificationCenter = .default,
        sideEffects: SideEffects = .live
    ) {
        self.defaults = defaults
        self.center = center
        self.sideEffects = sideEffects
    }

    // MARK: - Export

    /// Builds a backup of the current portable preferences.
    func makeBackup(exportedAt: Date = Date()) -> SettingsBackup {
        coder.makeBackup(
            snapshot: snapshot(),
            exportableKeys: AppConstants.UserDefaults.exportableKeys,
            twitchChannelName: defaults.string(forKey: AppConstants.UserDefaults.twitchChannelName),
            appVersion: Self.appVersion,
            appBuild: Self.appBuild,
            exportedAt: exportedAt
        )
    }

    /// Builds a backup and serializes it to pretty-printed JSON for writing.
    func makeBackupData(exportedAt: Date = Date()) throws -> Data {
        try coder.encode(makeBackup(exportedAt: exportedAt))
    }

    /// Reads the current value of every exportable key from UserDefaults.
    private func snapshot() -> [String: Any] {
        var dict: [String: Any] = [:]
        for key in AppConstants.UserDefaults.exportableKeys {
            if let value = defaults.object(forKey: key) {
                dict[key] = value
            }
        }
        return dict
    }

    // MARK: - Import

    /// Decodes and validates backup data. Throws `SettingsBackupCoder.BackupError`.
    func decode(_ data: Data) throws -> SettingsBackup {
        try coder.decode(data)
    }

    /// How many preferences a backup would restore (for the review summary).
    func restorableCount(_ backup: SettingsBackup) -> Int {
        coder.restorableCount(backup: backup, exportableKeys: AppConstants.UserDefaults.exportableKeys)
    }

    /// Applies a backup using the user's per-integration choices.
    ///
    /// Writes portable preferences, optionally restores the Twitch channel and
    /// flags re-auth, applies system-backed preferences, then broadcasts service
    /// toggles so background components pick up the new state without a relaunch.
    @discardableResult
    func apply(_ backup: SettingsBackup, choices: SettingsBackupCoder.ImportChoices) -> ApplySummary {
        let plan = coder.makeApplyPlan(
            backup: backup,
            choices: choices,
            exportableKeys: AppConstants.UserDefaults.exportableKeys
        )

        for (key, value) in plan.set {
            defaults.set(value.userDefaultsValue, forKey: key)
        }

        // If the backup turned Song Requests on but this machine has never
        // completed setup, force it back off so the feature doesn't start in a
        // broken state. The user can run setup from the Song Requests pane.
        let keys = AppConstants.UserDefaults.self
        if defaults.bool(forKey: keys.songRequestEnabled),
           !defaults.bool(forKey: keys.songRequestSetupComplete) {
            defaults.set(false, forKey: keys.songRequestEnabled)
        }

        if plan.reconnectTwitch, let channel = plan.twitchChannelName {
            // Restore the public channel name and mark re-auth needed. The token
            // is not in the backup, so TwitchViewModel surfaces a sign-in CTA.
            defaults.set(channel, forKey: AppConstants.UserDefaults.twitchChannelName)
            defaults.set(true, forKey: AppConstants.UserDefaults.twitchReauthNeeded)
            center.post(name: .twitchReauthNeededChanged, object: nil)
        }

        let sideEffectResult = applySideEffects(for: plan)
        broadcastServiceState()

        return ApplySummary(
            restoredCount: plan.set.count - sideEffectResult.failedKeys.count,
            reconnectedTwitch: plan.reconnectTwitch,
            twitchChannel: plan.twitchChannelName,
            ignoredCount: plan.ignoredKeyCount,
            warnings: sideEffectResult.warnings
        )
    }

    /// Applies preferences backed by AppKit, ServiceManagement, or Sparkle.
    /// A failed login-item transition is reconciled to the actual OS state so
    /// UserDefaults never claims a setting macOS rejected.
    private func applySideEffects(for plan: SettingsBackupCoder.ApplyPlan) -> SideEffectResult {
        let keys = AppConstants.UserDefaults.self
        var result = SideEffectResult()

        if case .bool(let desired)? = plan.set[keys.launchAtLogin],
           sideEffects.isLaunchAtLoginEnabled() != desired {
            switch sideEffects.setLaunchAtLogin(desired) {
            case .success, .requiresApproval:
                break
            case .failure:
                let actual = sideEffects.isLaunchAtLoginEnabled()
                defaults.set(actual, forKey: keys.launchAtLogin)
                if actual != desired {
                    result.failedKeys.insert(keys.launchAtLogin)
                    result.warnings.append(
                        "Launch at Login couldn't be restored and remains \(actual ? "on" : "off")."
                    )
                }
            }
        }

        if case .string(let appearance)? = plan.set[keys.appearancePreference] {
            sideEffects.applyAppearance(appearance)
        }

        let automaticChecks: Bool?
        if case .bool(let enabled)? = plan.set[keys.updateCheckEnabled] {
            automaticChecks = enabled
        } else {
            automaticChecks = nil
        }

        let channel: UpdateChannel?
        if case .string(let rawChannel)? = plan.set[keys.updateChannel] {
            channel = UpdateChannel.from(rawValue: rawChannel)
        } else {
            channel = nil
        }

        if automaticChecks != nil || channel != nil {
            sideEffects.applyUpdatePreferences(
                UpdatePreferences(
                    automaticCheckEnabled: automaticChecks,
                    channel: channel
                )
            )
        }

        return result
    }

    // MARK: - Service Notifications

    /// Re-broadcasts the toggles that background services observe, so an import
    /// takes effect live. Mirrors the notifications the menu and settings views
    /// post when these values change individually.
    private func broadcastServiceState() {
        let keys = AppConstants.UserDefaults.self

        center.postEnabled(.trackingSettingChanged, enabled: defaults.bool(forKey: keys.trackingEnabled))
        center.postEnabled(.discordPresenceChanged, enabled: defaults.bool(forKey: keys.discordPresenceEnabled))
        center.post(name: .discordPresenceSettingsChanged, object: nil)
        center.postEnabled(.songRequestSettingChanged, enabled: defaults.bool(forKey: keys.songRequestEnabled))
        center.postEnabled(.listeningHistorySettingChanged, enabled: defaults.bool(forKey: keys.listeningHistoryEnabled))
        center.postEnabled(.streamerModeChanged, enabled: defaults.bool(forKey: keys.streamerModeEnabled))
        center.postDockVisibility(mode: defaults.string(forKey: keys.dockVisibility) ?? AppConstants.DockVisibility.default)

        // Always send both resolved ports. A stored zero means "use default";
        // omitting it left an already-running custom-port listener unchanged.
        center.postWebSocketServerChanged(
            enabled: defaults.bool(forKey: keys.websocketEnabled),
            widgetHTTPEnabled: defaults.bool(forKey: keys.widgetHTTPEnabled),
            port: Preferences.resolvePort(
                defaults.integer(forKey: keys.websocketServerPort),
                default: AppConstants.WebSocketServer.defaultPort
            ),
            widgetPort: Preferences.resolvePort(
                defaults.integer(forKey: keys.widgetPort),
                default: AppConstants.WebSocketServer.widgetDefaultPort
            )
        )
    }

    // MARK: - App Version

    /// Running app marketing version (`CFBundleShortVersionString`).
    static var appVersion: String { AppConstants.AppInfo.shortVersion }

    /// Running app build number (`CFBundleVersion`).
    static var appBuild: String { AppConstants.AppInfo.buildNumber }
}
