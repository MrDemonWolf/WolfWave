//
//  DebugDiagnosticsTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-26.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

#if DEBUG
import XCTest
@testable import WolfWave

@MainActor
final class DebugDiagnosticsTests: XCTestCase {

    private func sampleSnapshot(
        appVersion: String = "1.2.3",
        build: String = "42",
        logSizeBytes: Int64 = 1024,
        logLineCount: Int = 100,
        musicTrackingEnabled: Bool = true,
        discordPresenceEnabled: Bool = false,
        widgetHTTPEnabled: Bool = true,
        twitchConnected: Bool = true,
        discordConnection: String = "disconnected",
        twitchTokenStored: Bool = true
    ) -> DebugDiagnostics.Snapshot {
        DebugDiagnostics.Snapshot(
            appVersion: appVersion,
            build: build,
            osVersion: "macOS 26.0",
            arch: "arm64",
            installMethod: "DMG",
            logSizeBytes: logSizeBytes,
            logLineCount: logLineCount,
            musicTrackingEnabled: musicTrackingEnabled,
            discordPresenceEnabled: discordPresenceEnabled,
            widgetHTTPEnabled: widgetHTTPEnabled,
            twitchConnected: twitchConnected,
            discordConnection: discordConnection,
            twitchTokenStored: twitchTokenStored
        )
    }

    func testIncludesAllThreeHeadings() {
        let output = DebugDiagnostics.markdown(sampleSnapshot())
        XCTAssertTrue(output.contains("## Environment"))
        XCTAssertTrue(output.contains("## Connections"))
        XCTAssertTrue(output.contains("## Preferences"))
    }

    func testEnvironmentFieldsAppearVerbatim() {
        let output = DebugDiagnostics.markdown(sampleSnapshot(appVersion: "9.9.9", build: "777"))
        XCTAssertTrue(output.contains("9.9.9 (build 777)"))
        XCTAssertTrue(output.contains("macOS 26.0"))
        XCTAssertTrue(output.contains("arm64"))
        XCTAssertTrue(output.contains("DMG"))
        XCTAssertTrue(output.contains("100"))
    }

    func testLogSizeFormattedViaByteCountFormatter() {
        let output = DebugDiagnostics.markdown(sampleSnapshot(logSizeBytes: 1024))
        let expected = ByteCountFormatter.string(fromByteCount: 1024, countStyle: .file)
        XCTAssertTrue(output.contains(expected), "expected formatted size in markdown")
    }

    /// The whole point of the split. A preference being on says nothing about
    /// whether the service actually connected, and the old single "Service
    /// State" table conflated them: it reported `discordPresenceEnabled` under
    /// a "Discord" row, so a pasted issue claimed Discord was up for a user
    /// whose RPC socket never connected.
    func testPreferencesAndConnectionsAreReportedSeparately() {
        let output = DebugDiagnostics.markdown(sampleSnapshot(
            discordPresenceEnabled: true,
            twitchConnected: false,
            discordConnection: "disconnected"
        ))

        XCTAssertTrue(output.contains("| Discord presence | Yes |"),
            "preference should read as enabled")
        XCTAssertTrue(output.contains("| Discord RPC | disconnected |"),
            "live connection should read as disconnected, not inherit the preference")
        XCTAssertTrue(output.contains("| Twitch chat | not connected |"))
    }

    func testConnectionStateUsesLiveWordingNotYesNo() {
        let connected = DebugDiagnostics.markdown(sampleSnapshot(twitchConnected: true))
        XCTAssertTrue(connected.contains("| Twitch chat | connected |"))

        let offline = DebugDiagnostics.markdown(sampleSnapshot(twitchConnected: false))
        XCTAssertTrue(offline.contains("| Twitch chat | not connected |"))
    }

    /// A stored token is not a connection. It is reported, but as its own row so
    /// it cannot be mistaken for one.
    func testStoredTokenIsReportedApartFromConnection() {
        let output = DebugDiagnostics.markdown(sampleSnapshot(
            twitchConnected: false,
            twitchTokenStored: true
        ))
        XCTAssertTrue(output.contains("| Twitch token in Keychain | Yes |"))
        XCTAssertTrue(output.contains("| Twitch chat | not connected |"))
    }

    func testPreferenceFlagsRenderAsYesNo() {
        let output = DebugDiagnostics.markdown(sampleSnapshot(
            musicTrackingEnabled: false,
            discordPresenceEnabled: true,
            widgetHTTPEnabled: true
        ))
        XCTAssertTrue(output.contains("| Music tracking | No |"))
        XCTAssertTrue(output.contains("| Discord presence | Yes |"))
        XCTAssertTrue(output.contains("| Widget HTTP server | Yes |"))
    }

    func testEmptyVersionAndZeroLogStatsTolerated() {
        let output = DebugDiagnostics.markdown(sampleSnapshot(
            appVersion: "",
            build: "",
            logSizeBytes: 0,
            logLineCount: 0
        ))
        XCTAssertTrue(output.contains("(build )"))
        XCTAssertTrue(output.contains("| Log line count | 0 |"))
        let zero = ByteCountFormatter.string(fromByteCount: 0, countStyle: .file)
        XCTAssertTrue(output.contains(zero))
    }

    func testOutputIsMarkdownTable() {
        let output = DebugDiagnostics.markdown(sampleSnapshot())
        XCTAssertTrue(output.contains("| Field | Value |"))
        XCTAssertTrue(output.contains("| Service | State |"))
        XCTAssertTrue(output.contains("| Setting | Enabled |"))
        XCTAssertTrue(output.contains("|---|---|"))
    }
}
#endif
