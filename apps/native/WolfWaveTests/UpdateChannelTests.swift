//
//  UpdateChannelTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-09.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Testing
@testable import WolfWave

/// Coverage for the `UpdateChannel` value type that backs the Stable/Nightly
/// Sparkle channel selector.
struct UpdateChannelTests {

    @Test func rawValuesAreStableStrings() {
        // These strings are persisted in UserDefaults; changing them would orphan
        // every existing user's stored channel. Lock them down.
        #expect(UpdateChannel.stable.rawValue == "stable")
        #expect(UpdateChannel.nightly.rawValue == "nightly")
    }

    @Test func allCasesAreStableThenNightly() {
        #expect(UpdateChannel.allCases == [.stable, .nightly])
    }

    @Test func fromRawValueParsesKnownValues() {
        #expect(UpdateChannel.from(rawValue: "stable") == .stable)
        #expect(UpdateChannel.from(rawValue: "nightly") == .nightly)
    }

    @Test func fromRawValueFallsBackToStable() {
        #expect(UpdateChannel.from(rawValue: nil) == .stable)
        #expect(UpdateChannel.from(rawValue: "") == .stable)
        #expect(UpdateChannel.from(rawValue: "beta") == .stable)
        #expect(UpdateChannel.from(rawValue: "STABLE") == .stable) // case-sensitive
    }

    @Test func isPrereleaseOnlyForNightly() {
        #expect(UpdateChannel.stable.isPrerelease == false)
        #expect(UpdateChannel.nightly.isPrerelease == true)
    }

    @Test func idMatchesRawValue() {
        #expect(UpdateChannel.stable.id == "stable")
        #expect(UpdateChannel.nightly.id == "nightly")
    }
}
