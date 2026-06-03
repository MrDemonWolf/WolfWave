//
//  StreamerModeTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-25.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

final class StreamerModeTests: XCTestCase {

    // MARK: - mask: off

    func testMaskReturnsInputWhenOff() {
        let input = "https://example.com/secret?token=abc"
        for style: StreamerMode.Style in [.url, .token, .channel, .generic] {
            XCTAssertEqual(
                StreamerMode.mask(input, style: style, isOn: false),
                input,
                "style \(style) should pass through when off"
            )
        }
    }

    func testMaskReturnsEmptyForEmptyInputRegardlessOfMode() {
        for isOn in [false, true] {
            for style: StreamerMode.Style in [.url, .token, .channel, .generic] {
                XCTAssertEqual(
                    StreamerMode.mask("", style: style, isOn: isOn),
                    "",
                    "empty input must stay empty (isOn=\(isOn), style=\(style))"
                )
            }
        }
    }

    // MARK: - mask: on

    func testMaskURLOn() {
        XCTAssertEqual(
            StreamerMode.mask("http://192.168.1.42:8766", style: .url, isOn: true),
            "hidden (streamer mode)"
        )
    }

    func testMaskTokenOn() {
        let masked = StreamerMode.mask("super-secret-abcdef", style: .token, isOn: true)
        XCTAssertEqual(masked, "hidden (streamer mode)")
        XCTAssertFalse(masked.contains("super-secret"))
    }

    func testMaskChannelOn() {
        let masked = StreamerMode.mask("mychannelname", style: .channel, isOn: true)
        XCTAssertEqual(masked, "hidden")
        XCTAssertFalse(masked.contains("my"))
    }

    func testMaskGenericOn() {
        XCTAssertEqual(
            StreamerMode.mask("anything", style: .generic, isOn: true),
            "hidden"
        )
    }

    // MARK: - mask: stability across input shapes

    func testMaskOnIsStableAcrossInputShapes() {
        let inputs = [
            "a",
            String(repeating: "x", count: 5_000),
            "üñîçødé-channel",
            "https://example.com/?token=\u{1F600}",
        ]
        for input in inputs {
            for style: StreamerMode.Style in [.url, .token, .channel, .generic] {
                let masked = StreamerMode.mask(input, style: style, isOn: true)
                XCTAssertFalse(masked.isEmpty, "masked output must not be empty")
                XCTAssertNotEqual(masked, input, "masked output must differ from input")
            }
        }
    }

    // MARK: - isEnabled

    func testIsEnabledReadsUserDefaults() {
        let key = AppConstants.UserDefaults.streamerModeEnabled
        let originalValue = UserDefaults.standard.bool(forKey: key)
        defer { UserDefaults.standard.set(originalValue, forKey: key) }

        UserDefaults.standard.set(true, forKey: key)
        XCTAssertTrue(StreamerMode.isEnabled)

        UserDefaults.standard.set(false, forKey: key)
        XCTAssertFalse(StreamerMode.isEnabled)
    }

    // MARK: - Constants registration

    func testStreamerModeKeyRegistered() {
        XCTAssertTrue(
            AppConstants.UserDefaults.allKeys.contains(AppConstants.UserDefaults.streamerModeEnabled),
            "streamerModeEnabled missing from AppConstants.UserDefaults.allKeys: reset operations and Debug inspector won't see it"
        )
    }

    func testStreamerModeNotificationRegistered() {
        XCTAssertTrue(
            AppConstants.Notifications.allNames.contains(AppConstants.Notifications.streamerModeChanged),
            "streamerModeChanged missing from AppConstants.Notifications.allNames: DEBUG firehose won't surface it"
        )
    }
}
