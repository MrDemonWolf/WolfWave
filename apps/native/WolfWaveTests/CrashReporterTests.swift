//
//  CrashReporterTests.swift
//  WolfWave
//
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

/// Covers the breadcrumb lifecycle of ``CrashReporter`` (write / detect / clear)
/// through the `markerDirectoryOverride` seam, so tests stay in a temp dir and
/// never touch the real app container.
///
/// Deliberately NOT covered here:
/// - `CrashReporter.install()` is never called: it installs process-wide signal
///   handlers, which would interfere with the XCTest host's own crash reporting.
/// - No real signal or `NSException` is ever raised: that would kill the test
///   host. The handlers' marker-writing path is exercised indirectly via
///   `writeMarker`, which the NSException handler also uses.
@MainActor
final class CrashReporterTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "CrashReporterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        CrashReporter.markerDirectoryOverride = tempDir
        CrashReporter.clearMarker()
    }

    override func tearDownWithError() throws {
        CrashReporter.clearMarker()
        CrashReporter.markerDirectoryOverride = nil
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
        tempDir = nil
        try super.tearDownWithError()
    }

    func testNoCrashByDefault() {
        XCTAssertFalse(CrashReporter.didCrashLastLaunch())
    }

    func testWriteMarkerIsDetected() {
        CrashReporter.writeMarker("EXCEPTION NSInvalidArgumentException\nboom\n")
        XCTAssertTrue(CrashReporter.didCrashLastLaunch())
    }

    func testMarkerContentRoundTrips() throws {
        CrashReporter.writeMarker("SIGSEGV\n")
        let contents = try String(contentsOf: CrashReporter.markerURL(), encoding: .utf8)
        XCTAssertEqual(contents, "SIGSEGV\n")
    }

    func testClearMarkerRemovesIt() {
        CrashReporter.writeMarker("SIGABRT\n")
        XCTAssertTrue(CrashReporter.didCrashLastLaunch())
        CrashReporter.clearMarker()
        XCTAssertFalse(CrashReporter.didCrashLastLaunch())
    }

    func testClearMarkerWhenAbsentIsNoOp() {
        XCTAssertFalse(CrashReporter.didCrashLastLaunch())
        CrashReporter.clearMarker() // must not throw or crash
        XCTAssertFalse(CrashReporter.didCrashLastLaunch())
    }

    func testWriteMarkerOverwritesPrevious() throws {
        CrashReporter.writeMarker("first\n")
        CrashReporter.writeMarker("second\n")
        let contents = try String(contentsOf: CrashReporter.markerURL(), encoding: .utf8)
        XCTAssertEqual(contents, "second\n")
    }

    func testMarkerURLHonorsOverride() {
        let path = CrashReporter.markerURL().path
        XCTAssertTrue(path.hasPrefix(tempDir.path), "override dir should root the marker path: \(path)")
        XCTAssertTrue(path.hasSuffix("last-crash.marker"))
    }

    func testDefaultMarkerURLIsScopedToWolfWaveState() {
        // Temporarily drop the override to assert the production path layout.
        CrashReporter.markerDirectoryOverride = nil
        defer { CrashReporter.markerDirectoryOverride = tempDir }
        let path = CrashReporter.markerURL().path
        XCTAssertTrue(path.contains("WolfWave/State/last-crash.marker"), "unexpected marker path: \(path)")
    }
}
