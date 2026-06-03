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
/// performs no UI and no file I/O of its own, only data + state changes.
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
        /// Backup keys ignored because they are not exportable.
        var ignoredCount: Int
    }

    private let defaults: Foundation.UserDefaults
    private let center: NotificationCenter
    private let coder = SettingsBackupCoder()

    init(
        defaults: Foundation.UserDefaults = .standard,
        center: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.center = center
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
    /// flags re-auth, then broadcasts the service toggles so background
    /// components pick up the new state without a relaunch.
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

        if plan.reconnectTwitch, let channel = plan.twitchChannelName {
            // Restore the public channel name and mark re-auth needed. The token
            // is not in the backup, so TwitchViewModel surfaces a sign-in CTA.
            defaults.set(channel, forKey: AppConstants.UserDefaults.twitchChannelName)
            defaults.set(true, forKey: AppConstants.UserDefaults.twitchReauthNeeded)
            center.post(name: .twitchReauthNeededChanged, object: nil)
        }

        broadcastServiceState()

        return ApplySummary(
            restoredCount: plan.set.count,
            reconnectedTwitch: plan.reconnectTwitch,
            twitchChannel: plan.twitchChannelName,
            ignoredCount: plan.ignoredKeyCount
        )
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

        let portInt = defaults.integer(forKey: keys.websocketServerPort)
        let port: UInt16? = (portInt > 0 && portInt <= Int(UInt16.max)) ? UInt16(portInt) : nil
        center.postWebSocketServerChanged(
            enabled: defaults.bool(forKey: keys.websocketEnabled),
            widgetHTTPEnabled: defaults.bool(forKey: keys.widgetHTTPEnabled),
            port: port
        )
    }

    // MARK: - App Version

    /// Running app marketing version (`CFBundleShortVersionString`).
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Running app build number (`CFBundleVersion`).
    static var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}
