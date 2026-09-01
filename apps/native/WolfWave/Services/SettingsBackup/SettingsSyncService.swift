//
//  SettingsSyncService.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-09-01.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

// MARK: - Store seam

/// The slice of `NSUbiquitousKeyValueStore` the sync service touches.
///
/// Exists so tests run against an in-memory store: a hosted test must never
/// write to the developer's real iCloud, the same rule `KeychainService`
/// follows. The only production conformer is `NSUbiquitousKeyValueStore`.
protocol SettingsSyncStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    @discardableResult func synchronize() -> Bool
    /// Posted (with `object == self`) when another device changed the store.
    var externalChangeNotificationName: Notification.Name { get }
}

extension NSUbiquitousKeyValueStore: SettingsSyncStore {
    var externalChangeNotificationName: Notification.Name {
        NSUbiquitousKeyValueStore.didChangeExternallyNotification
    }
}

// MARK: - Service

/// Mirrors the settings-backup payload to iCloud Key-Value Storage.
///
/// Reuses `SettingsBackupService` wholesale: the cloud copy is byte-for-byte
/// the same JSON an Export writes, so the exportable / account-linked /
/// runtime key classification is the sync boundary too. Accounts and tokens
/// never leave the Mac. Twitch is never auto-reconnected on a pull.
///
/// Conflict rule: last write wins on the whole blob, ordered by
/// `SettingsBackup.exportedAt`.
// ponytail: LWW on whole blob; per-key merge if two Macs edit simultaneously becomes a real complaint.
@MainActor
final class SettingsSyncService {

    // MARK: Properties

    /// KVS key holding the encoded `SettingsBackup`.
    static let payloadKey = "settings.v1"

    private let store: SettingsSyncStore
    private let backup: SettingsBackupService
    private let defaults: Foundation.UserDefaults
    private let center: NotificationCenter
    private let debounce: Duration
    private var observers: [NSObjectProtocol] = []
    private var lastPushedSettings: [String: BackupValue]?
    /// Set while a pull is writing defaults so the local-change observer
    /// doesn't echo a cloud payload straight back up.
    private var isApplying = false

    private(set) var isEnabled = false
    /// The debounced push in flight, if any. Tests await it.
    private(set) var pendingPush: Task<Void, Never>?
    private var pullTask: Task<Void, Never>?

    // MARK: Init

    init(
        store: SettingsSyncStore = NSUbiquitousKeyValueStore.default,
        backup: SettingsBackupService = SettingsBackupService(),
        defaults: Foundation.UserDefaults = DefaultsStore.store,
        center: NotificationCenter = .default,
        debounce: Duration = .seconds(2)
    ) {
        self.store = store
        self.backup = backup
        self.defaults = defaults
        self.center = center
        self.debounce = debounce
    }

    // MARK: Public Methods

    /// Starts or stops mirroring. Turning it off leaves the cloud copy alone.
    func setEnabled(_ enabled: Bool) {
        enabled ? start() : stop()
    }

    /// Applies the cloud payload if it is newer than what this Mac last
    /// applied or pushed. Returns `true` when settings changed.
    @discardableResult
    func pull() async -> Bool {
        guard let data = store.data(forKey: Self.payloadKey),
              let cloud = try? backup.decode(data)
        else { return false }
        let lastApplied = defaults.double(
            forKey: AppConstants.UserDefaults.iCloudSettingsSyncLastAppliedAt)
        guard cloud.exportedAt.timeIntervalSince1970 > lastApplied else { return false }

        isApplying = true
        defer { isApplying = false }
        let summary = await backup.apply(
            cloud, choices: SettingsBackupCoder.ImportChoices(reconnectTwitch: false))
        lastPushedSettings = cloud.settings
        markApplied(cloud.exportedAt)
        Log.info(
            "SettingsSync: applied cloud settings",
            category: .app,
            fields: ["restored": "\(summary.restoredCount)"]
        )
        return true
    }

    /// Uploads the current exportable preferences now, skipping the write when
    /// nothing exportable changed since the last push.
    func push(now: Date = Date()) {
        guard isEnabled else { return }
        guard let payload = try? backup.makeBackup(exportedAt: now) else { return }
        guard payload.settings != lastPushedSettings else { return }
        guard let data = try? SettingsBackupCoder().encode(payload) else { return }
        store.set(data, forKey: Self.payloadKey)
        store.synchronize()
        lastPushedSettings = payload.settings
        isApplying = true
        markApplied(now)
        isApplying = false
        Log.info("SettingsSync: pushed settings to iCloud", category: .app)
    }

    // MARK: Private Helpers

    private func start() {
        guard !isEnabled else { return }
        isEnabled = true
        observers.append(center.addObserver(
            forName: store.externalChangeNotificationName,
            object: store,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { [weak self] in
                self?.pullTask = Task { [weak self] in
                    await self?.pull()
                }
            }
        })
        observers.append(center.addObserver(
            forName: Foundation.UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { [weak self] in
                self?.schedulePush()
            }
        })
        store.synchronize()
        Task { [weak self] in
            guard let self else { return }
            if await !pull() { push() }
        }
    }

    private func stop() {
        guard isEnabled else { return }
        isEnabled = false
        observers.forEach(center.removeObserver)
        observers.removeAll()
        pendingPush?.cancel()
        pendingPush = nil
        pullTask?.cancel()
        pullTask = nil
    }

    private func schedulePush() {
        guard isEnabled, !isApplying else { return }
        pendingPush?.cancel()
        pendingPush = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            self?.push()
        }
    }

    private func markApplied(_ date: Date) {
        defaults.set(
            date.timeIntervalSince1970,
            forKey: AppConstants.UserDefaults.iCloudSettingsSyncLastAppliedAt)
    }
}
