//
//  WidgetAppearancePreview.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-04.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Live, in-app preview of the now-playing overlay widget.
///
/// Mirrors the rendering in `apps/widget/src/widget.ts` (theme palette, the
/// three layouts, and the Default/Glass custom-color overrides) using the
/// generated `DSWidgetThemes` / `DSWidgetLayouts` tables so this preview and the
/// real overlay stay in lockstep with `design-system/tokens.json`.
///
/// The widget is drawn at its native layout size, then scaled down to fit the
/// settings card (never upscaled), and centered on a checkerboard "stage" so
/// transparent themes (Default) read as transparent. All track data is invented
/// demo content — never real artists, songs, or artwork.
struct WidgetAppearancePreview: View {
    /// The appearance values to render. The settings card passes its live
    /// *draft* here, so the preview tracks every edit instantly even though
    /// those edits don't reach the real overlay until the user taps Apply.
    let config: WidgetAppearanceConfig

    private var widgetTheme: String { config.theme }
    private var widgetLayout: String { config.layout }
    private var widgetTextColor: String { config.textColor }
    private var widgetBackgroundColor: String { config.backgroundColor }
    private var widgetFontFamily: String { config.fontFamily }

    // Invented demo track (wolf song + wolf-species "artist"); never real media.
    private let demoTrack = "Midnight Howl"
    private let demoArtist = "Timber Wolf"
    private let demoElapsed = 78
    private let demoTotal = 192

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            header
            stage
        }
        .animation(.easeInOut(duration: DSMotion.Duration.base), value: widgetTheme)
        .animation(.easeInOut(duration: DSMotion.Duration.base), value: widgetLayout)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpace.s1h) {
            HStack(spacing: DSSpace.s2) {
                Image(systemName: "eye.fill")
                    .font(.system(size: DSFont.Size.sm, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .controlAccentColor))
                Text("Live Preview").sectionEyebrow()
            }
            Text("Sample of how your overlay looks. Tap Apply to push changes live.")
                .fieldSubtitle()
        }
    }

    // MARK: - Stage

    private var stage: some View {
        let native = DSWidgetLayouts.size(widgetLayout)
        return GeometryReader { geo in
            // Leave a small margin so the scaled widget never kisses the edges.
            let available = max(geo.size.width - DSSpace.s10, 1)
            let scale = min(1, available / native.width)

            ZStack {
                CheckerboardBackground()
                widgetView(theme: resolvedTheme)
                    .frame(width: native.width, height: native.height)
                    .scaleEffect(scale, anchor: .center)
                    .frame(width: native.width * scale, height: native.height * scale)
            }
            .frame(width: geo.size.width, height: stageHeight)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .frame(height: stageHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Widget preview, \(widgetTheme) theme, \(widgetLayout) layout")
    }

    /// Fixed to the tallest layout (Vertical) so switching layouts never resizes
    /// the stage. A growing/shrinking preview shifts everything below it and
    /// makes the settings pane scroll-jump, so the height stays constant and the
    /// widget just scales within it.
    private var stageHeight: CGFloat {
        (DSWidgetLayouts.sizes.values.map(\.height).max() ?? 280) + DSSpace.s11
    }

    // MARK: - Widget Body

    @ViewBuilder
    private func widgetView(theme: ResolvedWidgetTheme) -> some View {
        ZStack {
            if let bg = theme.containerBg { bg }
            if let overlay = theme.overlayBg { overlay }
            layoutContent(theme: theme)
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                .strokeBorder(theme.borderColor ?? .clear, lineWidth: theme.borderColor == nil ? 0 : 1)
        )
        .shadow(color: theme.glow ? theme.progressFill.opacity(0.45) : .clear,
                radius: theme.glow ? DSSpace.s3 : 0)
    }

    @ViewBuilder
    private func layoutContent(theme: ResolvedWidgetTheme) -> some View {
        switch widgetLayout {
        case "Vertical":  verticalLayout(theme: theme)
        case "Compact":   compactLayout(theme: theme)
        default:          horizontalLayout(theme: theme)
        }
    }

    private func horizontalLayout(theme: ResolvedWidgetTheme) -> some View {
        HStack(spacing: DSSpace.s4) {
            artwork(size: 90, corner: DSRadius.sm)
            VStack(alignment: .leading, spacing: DSSpace.s1) {
                trackText(demoTrack, size: DSFont.Size.lg, weight: .bold, color: theme.textPrimary, theme: theme)
                trackText(demoArtist, size: DSFont.Size.base, weight: .light, color: theme.textSecondary, theme: theme, italic: true)
                Spacer(minLength: 0)
                progressBar(theme: theme)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DSSpace.s3)
    }

    private func verticalLayout(theme: ResolvedWidgetTheme) -> some View {
        VStack(spacing: DSSpace.s2) {
            artwork(size: 150, corner: DSRadius.sm)
            trackText(demoTrack, size: DSFont.Size.base, weight: .bold, color: theme.textPrimary, theme: theme)
            trackText(demoArtist, size: DSFont.Size.sm, weight: .light, color: theme.textSecondary, theme: theme, italic: true)
            Spacer(minLength: 0)
            progressBar(theme: theme)
        }
        .multilineTextAlignment(.center)
        .padding(DSSpace.s4)
    }

    private func compactLayout(theme: ResolvedWidgetTheme) -> some View {
        HStack(spacing: DSSpace.s2) {
            artwork(size: 46, corner: DSRadius.xs)
            Text(compactTitle(theme: theme))
                .font(widgetFont(size: DSFont.Size.base, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .modifier(WidgetTextShadow(theme: theme))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DSSpace.s2)
    }

    /// Track, separator, and artist as one styled run.
    ///
    /// Built as an `AttributedString` so the compact layout stays a single
    /// `Text`. macOS 26 deprecated `Text + Text` concatenation.
    private func compactTitle(theme: ResolvedWidgetTheme) -> AttributedString {
        var track = AttributedString(demoTrack)
        track.foregroundColor = theme.textPrimary
        var separator = AttributedString("  —  ")
        separator.foregroundColor = theme.textMuted
        var artist = AttributedString(demoArtist)
        artist.foregroundColor = theme.textSecondary
        return track + separator + artist
    }

    // MARK: - Pieces

    private func trackText(
        _ text: String,
        size: CGFloat,
        weight: Font.Weight,
        color: Color,
        theme: ResolvedWidgetTheme,
        italic: Bool = false
    ) -> some View {
        let font = widgetFont(size: size, weight: weight)
        return Text(text)
            .font(italic ? font.italic() : font)
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .modifier(WidgetTextShadow(theme: theme))
    }

    private func progressBar(theme: ResolvedWidgetTheme) -> some View {
        let fraction = demoTotal > 0 ? CGFloat(demoElapsed) / CGFloat(demoTotal) : 0
        return VStack(spacing: DSSpace.s0) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.progressTrack)
                    Capsule().fill(theme.progressFill)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: DSSpace.s1)

            HStack {
                Text(HistoryFormat.clock(Double(demoElapsed)))
                Spacer()
                Text(verbatim: "-\(HistoryFormat.clock(Double(demoTotal - demoElapsed)))")
            }
            .font(widgetFont(size: DSFont.Size.xs, weight: .regular))
            .foregroundStyle(theme.textMuted)
        }
    }

    /// Placeholder album art. A flat brand-tinted gradient with a music glyph —
    /// stands in for real artwork without shipping any third-party media.
    private func artwork(size: CGFloat, corner: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.16, green: 0.16, blue: 0.30),
                             Color(red: 0.04, green: 0.52, blue: 1.0)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            )
            .frame(width: size, height: size)
    }

    // MARK: - Theme resolution

    private var resolvedTheme: ResolvedWidgetTheme {
        ResolvedWidgetTheme.resolve(
            themeName: widgetTheme,
            textColorHex: widgetTextColor,
            backgroundColorHex: widgetBackgroundColor
        )
    }

    // MARK: - Helpers

    private func widgetFont(size: CGFloat, weight: Font.Weight) -> Font {
        if widgetFontFamily == "System Default" {
            return .system(size: size, weight: weight)
        }
        return .custom(widgetFontFamily, size: size).weight(weight)
    }
}

// MARK: - Appearance Config

/// The five user-tunable widget appearance values as one `Equatable` value.
///
/// The settings card edits a *draft* copy of this so changes only reach the live
/// overlay (and `UserDefaults`, which `WebSocketServerService.broadcastWidgetConfig()`
/// reads) when the user taps Apply. The preview renders whatever draft it's handed.
struct WidgetAppearanceConfig: Equatable {
    var theme: String
    var layout: String
    var textColor: String
    var backgroundColor: String
    var fontFamily: String

    /// Snapshot the currently-applied values from `UserDefaults`.
    static func loadApplied(_ defaults: UserDefaults = .standard) -> WidgetAppearanceConfig {
        WidgetAppearanceConfig(
            theme: defaults.string(forKey: AppConstants.UserDefaults.widgetTheme) ?? "Default",
            layout: defaults.string(forKey: AppConstants.UserDefaults.widgetLayout) ?? "Horizontal",
            textColor: defaults.string(forKey: AppConstants.UserDefaults.widgetTextColor) ?? "#FFFFFF",
            backgroundColor: defaults.string(forKey: AppConstants.UserDefaults.widgetBackgroundColor) ?? "#1A1A2E",
            fontFamily: defaults.string(forKey: AppConstants.UserDefaults.widgetFontFamily) ?? "System Default"
        )
    }

    /// Whether the chosen theme exposes editable text/background colors. Preset
    /// themes (Dark, Light, Neon) ship fixed palettes.
    var themeCustomizable: Bool {
        DSWidgetThemes.resolve(theme).userCustomizable
    }
}

// MARK: - Resolved Theme

/// Runtime-resolved widget palette (generated base + user overrides applied).
/// `nonisolated` so the pure resolution logic is usable (and testable) off the
/// main actor, matching the generated `DSWidgetTheme` value type.
nonisolated struct ResolvedWidgetTheme {
    let containerBg: Color?
    let borderColor: Color?
    let cornerRadius: CGFloat
    let overlayBg: Color?
    let textPrimary: Color
    let textSecondary: Color
    let textMuted: Color
    let progressTrack: Color
    let progressFill: Color
    /// Apply an outer glow (Neon theme).
    let glow: Bool
    /// Apply a subtle drop shadow behind text for legibility (Default, Neon).
    let hasTextShadow: Bool

    /// Default config text color (`widget.ts` `defaultConfig.textColor`). When the
    /// stored color still equals this, no override is applied.
    static let defaultTextHex = "#FFFFFF"
    /// Default config background color (`widget.ts` `defaultConfig.backgroundColor`).
    static let defaultBackgroundHex = "#1A1A2E"

    /// `true` when a user-customizable theme has a text color that differs from
    /// the default and so should override the theme's text palette. Pure helper,
    /// extracted so the override rule is unit-testable without SwiftUI.
    static func shouldOverrideText(themeName: String, textColorHex: String) -> Bool {
        DSWidgetThemes.resolve(themeName).userCustomizable
            && textColorHex.uppercased() != defaultTextHex
    }

    /// `true` when a user-customizable theme has a background color that differs
    /// from the default and so should override the overlay.
    static func shouldOverrideBackground(themeName: String, backgroundColorHex: String) -> Bool {
        DSWidgetThemes.resolve(themeName).userCustomizable
            && backgroundColorHex.uppercased() != defaultBackgroundHex
    }

    /// Resolve the generated base palette and apply Default/Glass user overrides.
    /// Mirrors `resolveTheme` in `apps/widget/src/widget.ts`.
    static func resolve(
        themeName: String,
        textColorHex: String,
        backgroundColorHex: String
    ) -> ResolvedWidgetTheme {
        let base = DSWidgetThemes.resolve(themeName)
        var textPrimary = base.textPrimary
        var textSecondary = base.textSecondary
        var progressFill = base.progressFill
        var overlayBg = base.overlayBg

        if shouldOverrideText(themeName: themeName, textColorHex: textColorHex),
           let custom = Color(hex: textColorHex) {
            textPrimary = custom
            textSecondary = custom
            progressFill = custom
        }
        if shouldOverrideBackground(themeName: themeName, backgroundColorHex: backgroundColorHex),
           let custom = Color(hex: backgroundColorHex) {
            overlayBg = custom
        }

        return ResolvedWidgetTheme(
            containerBg: base.containerBg,
            borderColor: base.borderColor,
            cornerRadius: base.cornerRadius,
            overlayBg: overlayBg,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            textMuted: base.textMuted,
            progressTrack: base.progressTrack,
            progressFill: progressFill,
            // Themes that ship a CSS text-shadow / glow: Default (legibility on
            // stream) and Neon (signature glow).
            glow: themeName == "Neon",
            hasTextShadow: themeName == "Default" || themeName == "Neon"
        )
    }
}

// MARK: - Text Shadow

/// Subtle drop shadow behind widget text, matching themes that ship a CSS
/// `text-shadow` (Default sits over live video; Neon glows).
private struct WidgetTextShadow: ViewModifier {
    let theme: ResolvedWidgetTheme

    func body(content: Content) -> some View {
        if theme.hasTextShadow {
            content.shadow(color: .black.opacity(0.55), radius: 1, x: 1, y: 1)
        } else {
            content
        }
    }
}

// MARK: - Checkerboard

/// A light/dark checkerboard, the universal "this layer is transparent" cue.
/// Lets the Default (transparent) theme read correctly in the preview.
private struct CheckerboardBackground: View {
    private let tile: CGFloat = 11

    var body: some View {
        Canvas { context, size in
            let light = Color(white: 0.22)
            let dark = Color(white: 0.16)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(dark))
            let cols = Int((size.width / tile).rounded(.up))
            let rows = Int((size.height / tile).rounded(.up))
            for row in 0..<max(rows, 0) {
                for col in 0..<max(cols, 0) where (row + col).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(col) * tile, y: CGFloat(row) * tile, width: tile, height: tile)
                    context.fill(Path(rect), with: .color(light))
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Widget Appearance Preview") {
    ScrollView {
        WidgetAppearancePreview(config: .loadApplied())
            .padding()
            .frame(width: 560)
    }
}
