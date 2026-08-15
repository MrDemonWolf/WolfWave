//
//  DebugSectionCoverageTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-14.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

#if DEBUG
import Testing
@testable import WolfWave

/// Guards the Debug tab's jump-nav rail against silently losing a section.
///
/// `DebugSection.railGroups` is hand-ordered because the grouping is editorial,
/// which means adding a case and forgetting to place it produces no compile
/// error and no visible failure. The section still renders in the scroll column,
/// so the only symptom is that it cannot be reached from the rail. These tests
/// turn that into a test failure.
/// `@MainActor` because the app module defaults to main-actor isolation, so
/// `DebugSection.title` / `.icon` / `.railGroups` are isolated members. The
/// test target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`, so this has
/// to be stated explicitly. The suite touches no process-global state, so it
/// needs none of the Keychain/defaults isolation machinery.
@MainActor
@Suite("Debug Section Coverage")
struct DebugSectionCoverageTests {

    private var railSections: [DebugSection] {
        DebugSection.railGroups.flatMap(\.sections)
    }

    @Test("Every section appears in the rail")
    func testEverySectionIsReachable() {
        let missing = DebugSection.allCases.filter { !railSections.contains($0) }

        #expect(missing.isEmpty,
            "Section(s) not reachable from the Debug rail: \(missing.map(\.rawValue))")
    }

    @Test("No section is listed twice")
    func testNoDuplicates() {
        #expect(Set(railSections).count == railSections.count,
            "Duplicate section in DebugSection.railGroups")
    }

    @Test("The rail lists nothing that is not a real section")
    func testNoExtras() {
        #expect(railSections.count == DebugSection.allCases.count)
    }

    @Test("Every section carries a title and an icon")
    func testTitlesAndIcons() {
        for section in DebugSection.allCases {
            #expect(!section.title.isEmpty, "\(section.rawValue) has no title")
            #expect(!section.icon.isEmpty, "\(section.rawValue) has no icon")
        }
    }

    @Test("Rail order matches the on-screen card order")
    func testRailOrderMatchesDeclarationOrder() {
        // The rail highlights whichever section is scrolled to, so a rail whose
        // order disagrees with the page jumps around as the user scrolls.
        #expect(railSections == DebugSection.allCases)
    }
}
#endif
