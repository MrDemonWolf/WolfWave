//
//  AppearanceSettingsView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-01.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Appearance settings: three selectable preview tiles (System / Light / Dark)
/// that override the app's `NSAppearance` via `AppearanceController`. Mirrors the
/// thumbnail appearance picker in macOS System Settings, where each option shows a
/// miniature window so the choice is visual rather than a plain segmented control.
struct AppearanceSettingsView: View {

    // MARK: - User Settings

    @AppStorage(AppConstants.UserDefaults.appearancePreference)
    private var appearance = AppConstants.Appearance.default

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            VStack(alignment: .leading, spacing: DSSpace.s2) {
                Text("Appearance")
                    .sectionSubHeader()

                Text("Pick a look, or follow your system setting.")
                    .font(.system(size: DSFont.Size.base))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: DSSpace.s4) {
                HStack(alignment: .top, spacing: DSSpace.s4) {
                    ForEach(AppearanceOption.allCases, id: \.mode) { option in
                        AppearanceTile(
                            option: option,
                            isSelected: appearance == option.mode,
                            action: { select(option) }
                        )
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Appearance")
                .accessibilityIdentifier("appearancePicker")

                Text("System matches macOS automatically, including the light/dark schedule.")
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }

    // MARK: - Private Helpers

    /// Persists the chosen mode and applies it app-wide.
    private func select(_ option: AppearanceOption) {
        appearance = option.mode
        AppearanceController.apply(option.mode)
    }
}

// MARK: - Appearance Option

/// The three appearance choices, mapped to the persisted `AppConstants.Appearance`
/// raw values and to the palette each preview tile renders.
private enum AppearanceOption: CaseIterable {
    case system
    case light
    case dark

    /// Persisted raw value stored in `UserDefaults`.
    var mode: String {
        switch self {
        case .system: AppConstants.Appearance.system
        case .light: AppConstants.Appearance.light
        case .dark: AppConstants.Appearance.dark
        }
    }

    /// User-facing label shown beneath the tile.
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Which palette(s) the thumbnail draws.
    var preview: ThumbStyle {
        switch self {
        case .system: .system
        case .light: .light
        case .dark: .dark
        }
    }
}

// MARK: - Appearance Tile

/// One selectable preview: thumbnail, label, and a radio glyph. The whole tile is a
/// button; selection is signalled by both an accent ring and a checkmark (never by
/// color alone, per HIG) so it reads under color-blindness and Increase Contrast.
private struct AppearanceTile: View {

    let option: AppearanceOption
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var ringWidth: CGFloat {
        contrast == .increased ? ThumbMetrics.ringWidthHighContrast : ThumbMetrics.ringWidth
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: DSSpace.s2) {
                AppearancePreviewThumbnail(style: option.preview)
                    .frame(height: ThumbMetrics.thumbHeight)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                                lineWidth: isSelected ? ringWidth : 1
                            )
                    }
                    .scaleEffect(isHovering && !isSelected ? 1.02 : 1.0)

                Text(option.title)
                    .font(.system(size: DSFont.Size.body, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: DSFont.Size.md))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in
            if reduceMotion {
                isHovering = hovering
            } else {
                withAnimation(.easeInOut(duration: DSMotion.Duration.fast)) { isHovering = hovering }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: DSMotion.Duration.fast), value: isSelected)
        .help("Use the \(option.title.lowercased()) appearance.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Sets the app appearance to \(option.title.lowercased()).")
        .accessibilityIdentifier("appearanceOption.\(option.mode)")
    }
}

// MARK: - Preview Thumbnail

/// Which palette a thumbnail paints. `.system` layers the dark palette over the
/// light one along a diagonal, matching the split "Auto" tile in System Settings.
private enum ThumbStyle {
    case light
    case dark
    case system
}

/// A miniature desktop-plus-window mock drawn entirely with shapes so it renders the
/// same regardless of the app's current appearance (the Light tile always looks light,
/// the Dark tile always looks dark).
private struct AppearancePreviewThumbnail: View {
    let style: ThumbStyle

    var body: some View {
        switch style {
        case .light:
            DesktopMock(palette: .light)
        case .dark:
            DesktopMock(palette: .dark)
        case .system:
            DesktopMock(palette: .light)
                .overlay {
                    DesktopMock(palette: .dark)
                        .clipShape(DiagonalBottomTrailing())
                }
                .overlay(alignment: .topTrailing) {
                    // Faint divider along the light/dark seam.
                    DiagonalSeam()
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                }
        }
    }
}

/// Wallpaper gradient with a small centred window.
private struct DesktopMock: View {
    let palette: ThumbPalette

    var body: some View {
        LinearGradient(
            colors: [palette.wallpaperTop, palette.wallpaperBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay {
            WindowMock(palette: palette)
                .padding(.horizontal, DSSpace.s4)
                .padding(.top, DSSpace.s5)
                .padding(.bottom, DSSpace.s3)
        }
    }
}

/// A tiny window: title bar with three traffic-light dots, a sidebar, and content rows.
private struct WindowMock: View {
    let palette: ThumbPalette

    var body: some View {
        VStack(spacing: 0) {
            // Title bar with traffic lights.
            HStack(spacing: ThumbMetrics.trafficGap) {
                Circle().fill(ThumbPalette.trafficRed)
                Circle().fill(ThumbPalette.trafficYellow)
                Circle().fill(ThumbPalette.trafficGreen)
                Spacer(minLength: 0)
            }
            .frame(height: ThumbMetrics.trafficDot)
            .padding(.horizontal, DSSpace.s1)
            .frame(maxWidth: .infinity)
            .frame(height: ThumbMetrics.titleBarHeight)
            .background(palette.titleBar)

            // Sidebar + content.
            HStack(spacing: 0) {
                palette.sidebar
                    .frame(width: ThumbMetrics.sidebarWidth)

                VStack(alignment: .leading, spacing: ThumbMetrics.contentGap) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule()
                            .fill(palette.line)
                            .frame(height: ThumbMetrics.contentLine)
                    }
                    Spacer(minLength: 0)
                }
                .padding(DSSpace.s1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.windowFill)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.sm, style: .continuous)
                .strokeBorder(palette.windowStroke, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
    }
}

// MARK: - Palette

/// Fixed light/dark colors for the mock interior. Deliberately literal (not theme
/// tokens) so each tile shows its own scheme no matter the running app appearance.
private struct ThumbPalette {
    let wallpaperTop: Color
    let wallpaperBottom: Color
    let windowFill: Color
    let titleBar: Color
    let sidebar: Color
    let line: Color
    let windowStroke: Color

    static let light = ThumbPalette(
        wallpaperTop: Color(red: 0.90, green: 0.93, blue: 0.98),
        wallpaperBottom: Color(red: 0.78, green: 0.84, blue: 0.93),
        windowFill: Color(white: 0.99),
        titleBar: Color(white: 0.93),
        sidebar: Color(white: 0.95),
        line: Color(white: 0.80),
        windowStroke: Color.black.opacity(0.10)
    )

    static let dark = ThumbPalette(
        wallpaperTop: Color(red: 0.16, green: 0.17, blue: 0.21),
        wallpaperBottom: Color(red: 0.08, green: 0.09, blue: 0.12),
        windowFill: Color(white: 0.17),
        titleBar: Color(white: 0.24),
        sidebar: Color(white: 0.21),
        line: Color(white: 0.40),
        windowStroke: Color.white.opacity(0.12)
    )

    static let trafficRed = Color(red: 0.99, green: 0.37, blue: 0.34)
    static let trafficYellow = Color(red: 0.99, green: 0.74, blue: 0.18)
    static let trafficGreen = Color(red: 0.20, green: 0.78, blue: 0.35)
}

// MARK: - Shapes

/// Bottom-trailing triangle used to clip the dark layer of the System tile, leaving
/// the top-leading half showing the light layer.
private struct DiagonalBottomTrailing: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The seam line of the System tile, from bottom-leading to top-trailing.
private struct DiagonalSeam: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

// MARK: - Metrics

/// Bespoke layout sizes for the mock (frame/line dimensions, not spacing/padding).
private enum ThumbMetrics {
    static let thumbHeight: CGFloat = 78
    static let titleBarHeight: CGFloat = 14
    static let trafficDot: CGFloat = 6
    static let trafficGap: CGFloat = 3
    static let sidebarWidth: CGFloat = 26
    static let contentLine: CGFloat = 4
    static let contentGap: CGFloat = 4
    static let ringWidth: CGFloat = 2.5
    static let ringWidthHighContrast: CGFloat = 3.5
}

// MARK: - Preview

#Preview("Appearance") {
    AppearanceSettingsView()
        .padding()
        .frame(width: 600)
}
