//
//  WolfWaveReplyStyleTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-03.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

/// Coverage for `WolfWaveReplyStyle`: the preset reply copy, the default, and
/// resolution from UserDefaults. Each test resolves against a throwaway
/// `UserDefaults` suite so `.standard` is never touched.
@MainActor
final class WolfWaveReplyStyleTests: XCTestCase {

    /// A fresh, isolated UserDefaults suite, auto-cleaned at tear-down.
    private func makeStore() throws -> UserDefaults {
        let suiteName = "test.wolfwaveReplyStyle.\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        store.removePersistentDomain(forName: suiteName)
        addTeardownBlock { store.removePersistentDomain(forName: suiteName) }
        return store
    }

    // MARK: - Cases & defaults

    func testFourCases() {
        XCTAssertEqual(WolfWaveReplyStyle.allCases.count, 4)
    }

    func testDefaultIsCredit() {
        XCTAssertEqual(WolfWaveReplyStyle.default, .credit)
    }

    func testRawValuesStable() {
        // Persisted in UserDefaults, so these strings must not drift.
        XCTAssertEqual(WolfWaveReplyStyle.credit.rawValue, "credit")
        XCTAssertEqual(WolfWaveReplyStyle.howto.rawValue, "howto")
        XCTAssertEqual(WolfWaveReplyStyle.pitch.rawValue, "pitch")
        XCTAssertEqual(WolfWaveReplyStyle.short.rawValue, "short")
    }

    // MARK: - Reply copy

    func testEveryMessageIsWellFormed() {
        for style in WolfWaveReplyStyle.allCases {
            let message = style.message
            XCTAssertFalse(message.isEmpty, "\(style) message is empty")
            XCTAssertLessThanOrEqual(message.count, 500, "\(style) exceeds Twitch limit")
            XCTAssertTrue(message.hasPrefix("🐺"), "\(style) should open with the wolf mark")
            XCTAssertTrue(message.contains("WolfWave"), "\(style) missing app name")
            XCTAssertTrue(message.contains("MrDemonWolf"), "\(style) missing maker credit")
            XCTAssertTrue(message.contains(AppConstants.URLs.docs), "\(style) missing site link")
            XCTAssertFalse(message.contains("—"), "\(style) must not contain em-dashes")
        }
    }

    func testLabelsAreNonEmptyAndUnique() {
        let labels = WolfWaveReplyStyle.allCases.map(\.label)
        XCTAssertFalse(labels.contains(where: \.isEmpty))
        XCTAssertEqual(Set(labels).count, labels.count, "labels must be distinct")
    }

    // MARK: - Resolution from UserDefaults

    func testCurrentDefaultsToCreditWhenUnset() throws {
        let store = try makeStore()
        XCTAssertEqual(WolfWaveReplyStyle.current(store), .credit)
    }

    func testCurrentResolvesEachStoredCase() throws {
        let store = try makeStore()
        for style in WolfWaveReplyStyle.allCases {
            store.set(style.rawValue, forKey: AppConstants.UserDefaults.wolfwaveCommandReplyStyle)
            XCTAssertEqual(WolfWaveReplyStyle.current(store), style)
        }
    }

    func testCurrentFallsBackOnUnknownRawValue() throws {
        let store = try makeStore()
        store.set("nonsense", forKey: AppConstants.UserDefaults.wolfwaveCommandReplyStyle)
        XCTAssertEqual(WolfWaveReplyStyle.current(store), .credit)
    }
}
