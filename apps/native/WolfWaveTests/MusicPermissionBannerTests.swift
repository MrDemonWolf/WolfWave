//
//  MusicPermissionBannerTests.swift
//  WolfWaveTests
//

import SwiftUI
import XCTest
@testable import WolfWave

@MainActor
final class MusicPermissionBannerTests: XCTestCase {

    func testInstantiatesWithDefaultHandler() {
        let banner = MusicPermissionBanner(message: "needs access")
        _ = banner.body
    }

    func testInstantiatesWithCustomHandler() {
        var tapped = false
        let banner = MusicPermissionBanner(
            message: "needs access",
            onOpenSettings: { tapped = true }
        )
        _ = banner.body
        XCTAssertFalse(tapped, "Handler must only fire on button tap, not on body render.")
    }

    func testRendersBodyForLongMessage() {
        let banner = MusicPermissionBanner(
            message: String(repeating: "needs access ", count: 40),
            onOpenSettings: {}
        )
        _ = banner.body
    }

    func testRendersBodyForEmptyMessage() {
        let banner = MusicPermissionBanner(message: "", onOpenSettings: {})
        _ = banner.body
    }

    func testHandlerInvokedExplicitly() {
        var invocations = 0
        let banner = MusicPermissionBanner(
            message: "test",
            onOpenSettings: { invocations += 1 }
        )
        banner.onOpenSettings()
        XCTAssertEqual(invocations, 1)
    }

    func testMusicPermissionStateEnumCoversExpectedCases() {
        // Anchors the banner contract: callers gate on these three states.
        XCTAssertEqual(MusicPermissionState.unknown.rawValue, "unknown")
        XCTAssertEqual(MusicPermissionState.granted.rawValue, "granted")
        XCTAssertEqual(MusicPermissionState.denied.rawValue, "denied")
    }
}
