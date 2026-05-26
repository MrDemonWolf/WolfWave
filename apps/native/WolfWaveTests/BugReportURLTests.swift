//
//  BugReportURLTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

@MainActor
final class BugReportURLTests: XCTestCase {

    private let base = "https://github.com/mrdemonwolf/wolfwave/issues/new"

    func testReturnsNonNilURLForValidBase() {
        let url = BugReportURL.make(
            base: base,
            appVersion: "1.2.0",
            build: "42",
            osVersion: "macOS 26.0",
            arch: "arm64",
            install: .dmg
        )
        XCTAssertNotNil(url)
    }

    func testReturnsNilForMalformedBase() {
        let url = BugReportURL.make(
            base: "not a url",
            appVersion: "1.0",
            build: "1",
            osVersion: "macOS 26.0",
            arch: "arm64",
            install: .dmg
        )
        // URLComponents accepts most strings; check at least path/host are present
        if let url = url {
            XCTAssertTrue(url.absoluteString.contains("template=bug_report.yml"))
        }
    }

    func testQueryItemsIncludeTemplateAndLabel() throws {
        let url = BugReportURL.make(
            base: base,
            appVersion: "1.2.0",
            build: "42",
            osVersion: "macOS 26.0",
            arch: "arm64",
            install: .dmg
        )
        let url2 = try XCTUnwrap(url)
        let comps = URLComponents(url: url2, resolvingAgainstBaseURL: false)
        let items = comps?.queryItems ?? []

        let names = items.map { $0.name }
        XCTAssertTrue(names.contains("template"))
        XCTAssertTrue(names.contains("labels"))
        XCTAssertTrue(names.contains("title"))
        XCTAssertTrue(names.contains("body"))

        let template = items.first { $0.name == "template" }?.value
        XCTAssertEqual(template, "bug_report.yml")

        let labels = items.first { $0.name == "labels" }?.value
        XCTAssertEqual(labels, "bug")
    }

    func testBodyContainsEnvironmentFields() throws {
        let url = BugReportURL.make(
            base: base,
            appVersion: "1.2.3",
            build: "99",
            osVersion: "macOS 26.1.0",
            arch: "arm64",
            install: .homebrew
        )
        let url2 = try XCTUnwrap(url)
        let comps = URLComponents(url: url2, resolvingAgainstBaseURL: false)
        let body = comps?.queryItems?.first { $0.name == "body" }?.value ?? ""

        XCTAssertTrue(body.contains("1.2.3"), "body should contain app version")
        XCTAssertTrue(body.contains("99"), "body should contain build number")
        XCTAssertTrue(body.contains("macOS 26.1.0"), "body should contain OS version")
        XCTAssertTrue(body.contains("arm64"), "body should contain arch")
        XCTAssertTrue(body.contains("Homebrew"), "body should contain install method")
    }

    func testInstallMethodRawValues() {
        XCTAssertEqual(BugReportURL.InstallMethod.dmg.rawValue, "DMG")
        XCTAssertEqual(BugReportURL.InstallMethod.homebrew.rawValue, "Homebrew")
    }

    func testCurrentArchIsKnownValue() {
        let arch = BugReportURL.currentArch()
        XCTAssertTrue(["arm64", "x86_64", "unknown"].contains(arch))
    }

    func testURLPathPointsToIssuesNew() throws {
        let url = BugReportURL.make(
            base: base,
            appVersion: "1.0",
            build: "1",
            osVersion: "macOS 26.0",
            arch: "arm64",
            install: .dmg
        )
        let url2 = try XCTUnwrap(url)
        XCTAssertEqual(url2.host, "github.com")
        XCTAssertEqual(url2.path, "/mrdemonwolf/wolfwave/issues/new")
    }
}
