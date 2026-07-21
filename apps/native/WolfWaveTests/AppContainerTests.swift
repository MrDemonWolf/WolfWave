//
//  AppContainerTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-06.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

@MainActor
final class AppContainerTests: XCTestCase {

    // MARK: - Path Composition

    func testDirectoryComposesContainerAndSub() {
        let url = AppContainer.directory("History")
        // Always ends in <container>/<sub>.
        XCTAssertEqual(url.lastPathComponent, "History")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, AppContainer.containerName)
    }

    func testContainerNameIsWolfWave() {
        XCTAssertEqual(AppContainer.containerName, "WolfWave")
    }

    func testDistinctSubdirsAreSiblings() {
        let logs = AppContainer.directory("Logs")
        let history = AppContainer.directory("History")
        XCTAssertEqual(
            logs.deletingLastPathComponent().path,
            history.deletingLastPathComponent().path,
            "Logs and History live under the same WolfWave container."
        )
        XCTAssertNotEqual(logs.path, history.path)
    }

    // MARK: - Application Support Resolution

    func testResolvesUnderApplicationSupportWhenAvailable() throws {
        // The unit-test host has an Application Support directory, so the
        // resolver should anchor there rather than the temporary fallback.
        let appSupport = try XCTUnwrap(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        )
        let url = AppContainer.directory("State")
        let expected = appSupport
            .appending(path: AppContainer.containerName, directoryHint: .isDirectory)
            .appending(path: "State", directoryHint: .isDirectory)
        XCTAssertEqual(url.path, expected.path)
    }

    // MARK: - Fallback Policy

    func testFallbackPolicyKeepsContainerPrefix() {
        // The resolver's fallback (temporary directory) still nests the same
        // WolfWave/<sub> layout, so subdirs never collide with unrelated temp
        // files even if Application Support is unavailable.
        let temp = FileManager.default.temporaryDirectory
        let fallback = temp
            .appending(path: AppContainer.containerName, directoryHint: .isDirectory)
            .appending(path: "Cache", directoryHint: .isDirectory)
        XCTAssertEqual(fallback.lastPathComponent, "Cache")
        XCTAssertEqual(fallback.deletingLastPathComponent().lastPathComponent, AppContainer.containerName)
    }

    func testDoesNotCreateDirectory() {
        // directory(_:) only composes the path; it must not touch the disk.
        let url = AppContainer.directory("DoesNotCreate-\(UUID().uuidString)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
