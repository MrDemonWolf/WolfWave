//
//  WidgetAppearancePreviewTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-04.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
import CoreGraphics
@testable import WolfWave

/// Pure-logic coverage for the in-app widget appearance preview: the generated
/// theme/layout tables and the Default/Glass custom-color override rules that
/// mirror `apps/widget/src/widget.ts`. No SwiftUI, Keychain, or network.
final class WidgetAppearancePreviewTests: XCTestCase {

    // MARK: - Generated theme table

    func testKnownThemesResolve() {
        for name in ["Default", "Dark", "Light", "Glass", "Neon"] {
            // Resolve returns a real palette (not the fallback by accident) —
            // smoke check that every picker theme exists in the generated table.
            XCTAssertNotNil(DSWidgetThemes.all[name], "missing generated theme: \(name)")
        }
    }

    func testUnknownThemeFallsBackToDefault() {
        let unknown = DSWidgetThemes.resolve("NotARealTheme")
        let fallback = DSWidgetThemes.fallback
        XCTAssertEqual(unknown.userCustomizable, fallback.userCustomizable)
        XCTAssertEqual(unknown.cornerRadius, fallback.cornerRadius)
        XCTAssertEqual(unknown.showArtworkBlur, fallback.showArtworkBlur)
    }

    func testOrderExcludesHiddenThemes() {
        XCTAssertEqual(DSWidgetThemes.order, ["Default", "Dark", "Light", "Glass", "Neon"])
        XCTAssertFalse(DSWidgetThemes.order.contains("WolfWave"), "hidden theme leaked into picker order")
    }

    func testOrderMatchesPickerConstants() {
        // The picker reads AppConstants.Widget.themes; the preview reads the
        // generated order. They must agree or the preview drifts from the picker.
        XCTAssertEqual(DSWidgetThemes.order, AppConstants.Widget.themes)
    }

    func testCustomizableFlag() {
        XCTAssertTrue(DSWidgetThemes.resolve("Default").userCustomizable)
        XCTAssertTrue(DSWidgetThemes.resolve("Glass").userCustomizable)
        XCTAssertFalse(DSWidgetThemes.resolve("Dark").userCustomizable)
        XCTAssertFalse(DSWidgetThemes.resolve("Light").userCustomizable)
        XCTAssertFalse(DSWidgetThemes.resolve("Neon").userCustomizable)
    }

    func testDefaultThemeIsTransparentWithOverlay() {
        let theme = DSWidgetThemes.resolve("Default")
        XCTAssertNil(theme.containerBg, "Default container should be transparent")
        XCTAssertNil(theme.borderColor, "Default has no border")
        XCTAssertNotNil(theme.overlayBg, "Default draws a dark overlay for legibility")
        XCTAssertTrue(theme.showArtworkBlur)
    }

    // MARK: - Generated layout table

    func testLayoutSizes() {
        XCTAssertEqual(DSWidgetLayouts.size("Horizontal"), CGSize(width: 500, height: 100))
        XCTAssertEqual(DSWidgetLayouts.size("Vertical"), CGSize(width: 220, height: 280))
        XCTAssertEqual(DSWidgetLayouts.size("Compact"), CGSize(width: 350, height: 56))
    }

    func testUnknownLayoutFallsBackToHorizontal() {
        XCTAssertEqual(DSWidgetLayouts.size("Bogus"), CGSize(width: 500, height: 100))
    }

    func testLayoutKeysMatchPickerConstants() {
        let keys = Set(DSWidgetLayouts.sizes.keys)
        XCTAssertEqual(keys, Set(AppConstants.Widget.layouts))
    }

    // MARK: - Custom-color override rules

    func testCustomTextOverrideOnlyForCustomizableThemes() {
        // Default/Glass: a non-default text color overrides.
        XCTAssertTrue(ResolvedWidgetTheme.shouldOverrideText(themeName: "Default", textColorHex: "#FF0000"))
        XCTAssertTrue(ResolvedWidgetTheme.shouldOverrideText(themeName: "Glass", textColorHex: "#00FF00"))
        // Preset themes never take a text override.
        XCTAssertFalse(ResolvedWidgetTheme.shouldOverrideText(themeName: "Dark", textColorHex: "#FF0000"))
        XCTAssertFalse(ResolvedWidgetTheme.shouldOverrideText(themeName: "Neon", textColorHex: "#FF0000"))
    }

    func testDefaultTextColorIsNotAnOverride() {
        XCTAssertFalse(ResolvedWidgetTheme.shouldOverrideText(themeName: "Default", textColorHex: "#FFFFFF"))
        // Case-insensitive: the ColorPicker can emit either case.
        XCTAssertFalse(ResolvedWidgetTheme.shouldOverrideText(themeName: "Default", textColorHex: "#ffffff"))
    }

    func testBackgroundOverrideRules() {
        XCTAssertTrue(ResolvedWidgetTheme.shouldOverrideBackground(themeName: "Default", backgroundColorHex: "#000000"))
        XCTAssertFalse(ResolvedWidgetTheme.shouldOverrideBackground(themeName: "Default", backgroundColorHex: "#1A1A2E"))
        XCTAssertFalse(ResolvedWidgetTheme.shouldOverrideBackground(themeName: "Default", backgroundColorHex: "#1a1a2e"))
        XCTAssertFalse(ResolvedWidgetTheme.shouldOverrideBackground(themeName: "Dark", backgroundColorHex: "#000000"))
    }

    func testResolvePreservesPassthroughFields() {
        // Custom colors must not disturb the non-overridable parts of the palette.
        let base = DSWidgetThemes.resolve("Default")
        let resolved = ResolvedWidgetTheme.resolve(
            themeName: "Default",
            textColorHex: "#FF0000",
            backgroundColorHex: "#1A1A2E"
        )
        XCTAssertEqual(resolved.cornerRadius, base.cornerRadius)
        XCTAssertNil(resolved.containerBg)
        XCTAssertTrue(resolved.hasTextShadow, "Default keeps its text shadow")
        XCTAssertFalse(resolved.glow)
    }

    func testNeonResolvesWithGlow() {
        let resolved = ResolvedWidgetTheme.resolve(
            themeName: "Neon",
            textColorHex: "#FFFFFF",
            backgroundColorHex: "#1A1A2E"
        )
        XCTAssertTrue(resolved.glow)
        XCTAssertTrue(resolved.hasTextShadow)
    }
}
