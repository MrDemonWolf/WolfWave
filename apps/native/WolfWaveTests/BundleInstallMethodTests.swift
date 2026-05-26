//
//  BundleInstallMethodTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-16.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

@MainActor
final class BundleInstallMethodTests: XCTestCase {

    // MARK: - DMG / Non-Homebrew Paths

    func testApplicationsPathIsNotHomebrew() {
        XCTAssertFalse(Bundle.isHomebrewPath("/Applications/WolfWave.app"))
    }

    func testDownloadsPathIsNotHomebrew() {
        XCTAssertFalse(Bundle.isHomebrewPath("/Users/alice/Downloads/WolfWave.app"))
    }

    func testUserApplicationsPathIsNotHomebrew() {
        XCTAssertFalse(Bundle.isHomebrewPath("/Users/alice/Applications/WolfWave.app"))
    }

    func testEmptyPathIsNotHomebrew() {
        XCTAssertFalse(Bundle.isHomebrewPath(""))
    }

    // MARK: - Apple Silicon Homebrew

    func testAppleSiliconCaskroomIsHomebrew() {
        XCTAssertTrue(Bundle.isHomebrewPath("/opt/homebrew/Caskroom/wolfwave/1.0.0/WolfWave.app"))
    }

    func testAppleSiliconCellarIsHomebrew() {
        XCTAssertTrue(Bundle.isHomebrewPath("/opt/homebrew/Cellar/something/1.0/bin"))
    }

    // MARK: - Intel Homebrew

    func testIntelCaskroomIsHomebrew() {
        // Regression guard: previously misclassified as DMG install.
        XCTAssertTrue(Bundle.isHomebrewPath("/usr/local/Caskroom/wolfwave/1.0.0/WolfWave.app"))
    }

    func testIntelCellarIsHomebrew() {
        XCTAssertTrue(Bundle.isHomebrewPath("/usr/local/Cellar/something/1.0/bin"))
    }

    // MARK: - Custom Prefix

    func testCustomHomebrewPrefixIsHomebrew() {
        XCTAssertTrue(Bundle.isHomebrewPath("/Users/alice/Homebrew/Caskroom/wolfwave/1.0.0/WolfWave.app"))
    }

    // MARK: - Bundle.main accessor compiles

    func testMainBundleAccessorReturnsBool() {
        _ = Bundle.main.isHomebrewInstall
    }
}
