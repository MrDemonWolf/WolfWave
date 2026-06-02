//
//  SettingsBackupKeyCoverageTests.swift
//  WolfWaveTests
//
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Testing
@testable import WolfWave

/// Anti-drift guard for the export/import key classification.
///
/// Every key the app writes (`allKeys`) must be sorted into exactly one of the
/// three backup buckets. When someone adds a new UserDefaults key, these tests
/// fail until it is classified, which forces a deliberate "is this safe to
/// back up?" decision instead of a silent leak or omission.
struct SettingsBackupKeyCoverageTests {

    private typealias Keys = AppConstants.UserDefaults

    @Test func everyKeyIsClassifiedExactlyOnce() {
        let all = Set(Keys.allKeys)
        let exportable = Set(Keys.exportableKeys)
        let account = Set(Keys.accountLinkedKeys)
        let runtime = Set(Keys.runtimeStateKeys)

        // The three buckets exactly partition allKeys.
        #expect(exportable.union(account).union(runtime) == all)

        // No key appears in two buckets.
        #expect(exportable.isDisjoint(with: account))
        #expect(exportable.isDisjoint(with: runtime))
        #expect(account.isDisjoint(with: runtime))

        // No bucket contains a key that is not in allKeys.
        #expect(exportable.isSubset(of: all))
        #expect(account.isSubset(of: all))
        #expect(runtime.isSubset(of: all))
    }

    @Test func bucketsHaveNoInternalDuplicates() {
        #expect(Keys.allKeys.count == Set(Keys.allKeys).count)
        #expect(Keys.exportableKeys.count == Set(Keys.exportableKeys).count)
        #expect(Keys.accountLinkedKeys.count == Set(Keys.accountLinkedKeys).count)
        #expect(Keys.runtimeStateKeys.count == Set(Keys.runtimeStateKeys).count)
    }

    @Test func accountAndRuntimeKeysAreNeverExportable() {
        let exportable = Set(Keys.exportableKeys)
        for key in Keys.accountLinkedKeys + Keys.runtimeStateKeys {
            #expect(!exportable.contains(key))
        }
    }

    @Test func twitchIdentityIsNotExportable() {
        // Twitch is the only OAuth account; its identity keys must stay out of
        // a backup payload and be gated behind the per-account reconnect opt-in.
        let exportable = Set(Keys.exportableKeys)
        #expect(!exportable.contains(Keys.twitchChannelName))
        #expect(!exportable.contains(Keys.twitchReauthNeeded))
    }
}
