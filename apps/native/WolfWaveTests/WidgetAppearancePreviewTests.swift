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
/// theme/layout tables that back the picker and the preview's stage sizing. The
/// preview itself now renders the real `widget.html` in a `WKWebView`, so the
/// theme/layout/color *rendering* is exercised by that one shared code path
/// (`apps/widget/src/widget.ts`) rather than a parallel Swift resolver. No
/// SwiftUI, Keychain, or network.
final class WidgetAppearancePreviewTests: XCTestCase {

    // MARK: - Generated theme table

    func testKnownThemesResolve() {
        for name in ["Default", "Dark", "Light", "Glass", "Neon"] {
            // Resolve returns a real palette (not the fallback by accident).
            // Smoke check: every picker theme exists in the generated table.
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
        XCTAssertEqual(DSWidgetLayouts.size("Vinyl"), CGSize(width: 260, height: 300))
        XCTAssertEqual(DSWidgetLayouts.size("Classic"), CGSize(width: 440, height: 112))
    }

    func testUnknownLayoutFallsBackToHorizontal() {
        XCTAssertEqual(DSWidgetLayouts.size("Bogus"), CGSize(width: 500, height: 100))
    }

    func testLayoutKeysMatchPickerConstants() {
        let keys = Set(DSWidgetLayouts.sizes.keys)
        XCTAssertEqual(keys, Set(AppConstants.Widget.layouts))
    }

    // MARK: - Appearance config → preview JSON

    func testPreviewJSONCarriesAllFields() throws {
        let config = WidgetAppearanceConfig(
            theme: "Glass",
            layout: "Vertical",
            textColor: "#FF0000",
            backgroundColor: "#1A1A2E",
            fontFamily: "Helvetica Neue"
        )
        let json = try XCTUnwrap(config.previewJSON)
        let data = try XCTUnwrap(json.data(using: .utf8))
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: String]
        )
        XCTAssertEqual(parsed["theme"], "Glass")
        XCTAssertEqual(parsed["layout"], "Vertical")
        XCTAssertEqual(parsed["textColor"], "#FF0000")
        XCTAssertEqual(parsed["backgroundColor"], "#1A1A2E")
        XCTAssertEqual(parsed["fontFamily"], "Helvetica Neue")
    }

    func testPreviewJSONEscapesUnsafeFontName() throws {
        // A font family with a quote must not break out of the injected JS; the
        // value survives a round-trip intact (escaping handled by JSONSerialization).
        let config = WidgetAppearanceConfig(
            theme: "Default",
            layout: "Horizontal",
            textColor: "#FFFFFF",
            backgroundColor: "#1A1A2E",
            fontFamily: "Evil\"); alert('x'); //"
        )
        let json = try XCTUnwrap(config.previewJSON)
        let data = try XCTUnwrap(json.data(using: .utf8))
        let parsed = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: String]
        )
        XCTAssertEqual(parsed["fontFamily"], "Evil\"); alert('x'); //")
    }

    func testThemeCustomizableMatchesGeneratedTable() {
        XCTAssertTrue(WidgetAppearanceConfig(
            theme: "Default", layout: "Horizontal",
            textColor: "#FFFFFF", backgroundColor: "#1A1A2E", fontFamily: "System Default"
        ).themeCustomizable)
        XCTAssertFalse(WidgetAppearanceConfig(
            theme: "Dark", layout: "Horizontal",
            textColor: "#FFFFFF", backgroundColor: "#1A1A2E", fontFamily: "System Default"
        ).themeCustomizable)
    }
}
