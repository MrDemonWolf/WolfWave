//
//  DesignTokenCatalogTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI
import Testing
@testable import WolfWave

/// Pins the ordered token lists that `design-system/scripts/generate.ts` emits
/// alongside the named `static let`s (`DSColor.groups`, `DSSpace.all`, …).
///
/// The Debug design-system gallery iterates these lists instead of hand-listing
/// tokens, so the gallery can only be as complete as the generator output. A
/// regeneration that silently dropped a family, duplicated a name, or lost the
/// value-sorted spacing order would show up here, not as a half-empty gallery.
/// Nothing here touches process-global state.
@Suite("Design Token Catalog")
struct DesignTokenCatalogTests {

    private func assertUniqueNonEmpty(_ names: [String], _ family: String) {
        #expect(!names.isEmpty, "\(family) list is empty")
        #expect(Set(names).count == names.count, "\(family) has duplicate names: \(names)")
    }

    @Test("Every scalar family is non-empty with unique names")
    func scalarFamilies() {
        assertUniqueNonEmpty(DSFont.Size.all.map(\.name), "DSFont.Size")
        assertUniqueNonEmpty(DSFont.Weight.all.map(\.name), "DSFont.Weight")
        assertUniqueNonEmpty(DSSpace.all.map(\.name), "DSSpace")
        assertUniqueNonEmpty(DSRadius.all.map(\.name), "DSRadius")
        assertUniqueNonEmpty(DSMotion.Duration.all.map(\.name), "DSMotion.Duration")
        assertUniqueNonEmpty(DSMotion.Spring.all.map(\.name), "DSMotion.Spring")
    }

    @Test("Spacing list is sorted by value and includes the half step")
    func spacingOrder() {
        let values = DSSpace.all.map(\.value)
        #expect(values == values.sorted(), "DSSpace.all must read smallest to largest: \(values)")
        #expect(Set(values).count == values.count, "DSSpace.all has duplicate values")
        #expect(values.contains(DSSpace.s1h), "s1h missing from DSSpace.all")
        #expect(values.first == DSSpace.s0)
        #expect(values.last == DSSpace.s11)
    }

    @Test("Font size ramp matches the named constants")
    func fontSizes() {
        let byName = Dictionary(uniqueKeysWithValues: DSFont.Size.all.map { ($0.name, $0.value) })
        #expect(byName["xs"] == DSFont.Size.xs)
        #expect(byName["base"] == DSFont.Size.base)
        #expect(byName["x3xl"] == DSFont.Size.x3xl)
        #expect(DSFont.Size.all.map(\.value) == DSFont.Size.all.map(\.value).sorted())
    }

    @Test("Color groups carry every MARK group with six-digit uppercase hex")
    func colorGroups() {
        let groupNames = DSColor.groups.map(\.name)
        #expect(groupNames == [
            "Brand", "Semantic", "Surface (light)", "Surface (dark)",
            "Text (light)", "Text (dark)", "Partner"
        ])
        let tokens = DSColor.groups.flatMap(\.tokens)
        assertUniqueNonEmpty(tokens.map(\.name), "DSColor")
        for token in tokens {
            let digits = token.hex.dropFirst()
            let isHex = token.hex.hasPrefix("#") && digits.count == 6
                && digits.allSatisfy { $0.isHexDigit && !$0.isLowercase }
            #expect(isHex, "\(token.name) hex is \(token.hex)")
        }
        let semantic = DSColor.groups.first { $0.name == "Semantic" }?.tokens.map(\.name) ?? []
        #expect(semantic == ["success", "warning", "error", "info", "neutral"])
    }

    @Test("Spring list mirrors the named presets")
    func springs() {
        let names = DSMotion.Spring.all.map(\.name)
        #expect(names.contains("snappy"))
        for spring in DSMotion.Spring.all {
            #expect(spring.response > 0, "\(spring.name) response")
            #expect((0...1).contains(spring.damping), "\(spring.name) damping")
        }
    }

    @Test("Dimension groups match the nested enums")
    func dimensionGroups() {
        let groupNames = DSDimension.groups.map(\.name)
        #expect(groupNames == ["Settings", "Onboarding", "About", "WhatsNew", "IconButton", "HistoryStats"])
        for group in DSDimension.groups {
            assertUniqueNonEmpty(group.tokens.map(\.name), "DSDimension.\(group.name)")
        }
        let settings = DSDimension.groups.first { $0.name == "Settings" }?.tokens ?? []
        #expect(settings.first { $0.name == "maxContentWidth" }?.value == DSDimension.Settings.maxContentWidth)
    }
}
