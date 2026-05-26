//
//  DebugDiagnosticsTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 5/25/26.
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
        twitchConnected: Bool = true,
        discordConnected: Bool = false,
        widgetEnabled: Bool = true,
        musicTrackingEnabled: Bool = true
    ) -> DebugDiagnostics.Snapshot {
        DebugDiagnostics.Snapshot(
            appVersion: appVersion,
            build: build,
            osVersion: "macOS 26.0",
            arch: "arm64",
            installMethod: "DMG",
            logSizeBytes: logSizeBytes,
            logLineCount: logLineCount,
            twitchConnected: twitchConnected,
            discordConnected: discordConnected,
            widgetEnabled: widgetEnabled,
            musicTrackingEnabled: musicTrackingEnabled
        )
    }

    func testIncludesEnvironmentAndServiceStateHeadings() {
        let output = DebugDiagnostics.markdown(sampleSnapshot())
        XCTAssertTrue(output.contains("## Environment"))
        XCTAssertTrue(output.contains("## Service State"))
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

    func testServiceFlagsRenderAsYesNo() {
        let output = DebugDiagnostics.markdown(sampleSnapshot(
            twitchConnected: true,
            discordConnected: false,
            widgetEnabled: true,
            musicTrackingEnabled: false
        ))
        XCTAssertTrue(output.contains("| Twitch | Yes |"))
        XCTAssertTrue(output.contains("| Discord | No |"))
        XCTAssertTrue(output.contains("| Widget HTTP | Yes |"))
        XCTAssertTrue(output.contains("| Music tracking | No |"))
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
        XCTAssertTrue(output.contains("|---|---|"))
    }
}
#endif
