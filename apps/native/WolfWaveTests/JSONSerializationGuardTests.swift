//
//  JSONSerializationGuardTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-03.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

/// Locks in the `isValidJSONObject` guard that fronts every
/// `JSONSerialization.data(withJSONObject:)` call site (DiscordRPCService,
/// WebSocketServerService, DebugInspectorsCard).
///
/// `data(withJSONObject:)` raises an ObjC `NSInvalidArgumentException` on an
/// invalid leaf, and `try?` does NOT catch ObjC exceptions, so an unguarded
/// call would hard-crash the process. The guard converts those exact inputs
/// into a clean `false` (skip the serialize) instead.
final class JSONSerializationGuardTests: XCTestCase {

    func testIsValidRejectsNaN() {
        XCTAssertFalse(JSONSerialization.isValidJSONObject(["x": Double.nan]))
    }

    func testIsValidRejectsPositiveInfinity() {
        XCTAssertFalse(JSONSerialization.isValidJSONObject(["x": Double.infinity]))
    }

    func testIsValidRejectsNegativeInfinity() {
        XCTAssertFalse(JSONSerialization.isValidJSONObject(["x": -Double.infinity]))
    }

    func testValidDiscordShapedDictPasses() {
        // Mirrors a Discord IPC handshake payload (the sendFrame call site).
        let payload: [String: Any] = [
            "v": 1,
            "client_id": "0123456789",
            "nonce": "abc-123",
        ]
        XCTAssertTrue(JSONSerialization.isValidJSONObject(payload))
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: payload))
    }

    func testValidWebSocketShapedDictPasses() {
        // Mirrors a now-playing overlay broadcast (the sendJSON call site).
        let dict: [String: Any] = [
            "type": "playback_state",
            "playing": true,
            "title": "Howl at the Moon",
            "progress": 42.5,
        ]
        XCTAssertTrue(JSONSerialization.isValidJSONObject(dict))
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: dict))
    }

    func testStringDictionaryIsAlwaysValid() {
        // The DebugInspectorsCard site is [String: String]; such a dict can
        // never contain an invalid JSON leaf, so the guard always passes.
        let dict: [String: String] = ["version": "2.0.0", "build": "42", "locale": "en_US"]
        XCTAssertTrue(JSONSerialization.isValidJSONObject(dict))
    }

    func testNaNNestedInArrayIsRejected() {
        // Defense-in-depth: an invalid leaf nested inside a value is still caught.
        let dict: [String: Any] = ["samples": [1.0, 2.0, Double.nan]]
        XCTAssertFalse(JSONSerialization.isValidJSONObject(dict))
    }
}
