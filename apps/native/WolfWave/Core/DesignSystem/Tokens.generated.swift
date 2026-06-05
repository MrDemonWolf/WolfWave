// WolfWave Design System — GENERATED FILE. Do not edit by hand.
// Source: design-system/tokens.json
// Run `bun run tokens` to regenerate.

import SwiftUI
import CoreGraphics

// MARK: - Design System Tokens

/// Generated color tokens. Use these instead of hardcoded `Color(red:…)` literals.
nonisolated enum DSColor {
    // MARK: Brand
    static let brand50 = Color(red: 0.941, green: 0.969, blue: 1.000)
    static let brand100 = Color(red: 0.851, green: 0.925, blue: 1.000)
    static let brand200 = Color(red: 0.690, green: 0.839, blue: 1.000)
    static let brand300 = Color(red: 0.498, green: 0.722, blue: 1.000)
    static let brand400 = Color(red: 0.290, green: 0.612, blue: 1.000)
    static let brand500 = Color(red: 0.039, green: 0.518, blue: 1.000)
    static let brand600 = Color(red: 0.000, green: 0.400, blue: 0.800)
    static let brand700 = Color(red: 0.000, green: 0.306, blue: 0.624)
    static let brand800 = Color(red: 0.000, green: 0.227, blue: 0.471)
    static let brand900 = Color(red: 0.000, green: 0.145, blue: 0.318)

    // MARK: Semantic
    static let success = Color(red: 0.204, green: 0.780, blue: 0.349)
    static let warning = Color(red: 1.000, green: 0.624, blue: 0.039)
    static let error = Color(red: 1.000, green: 0.271, blue: 0.227)
    static let info = Color(red: 0.039, green: 0.518, blue: 1.000)

    // MARK: Surface (light)
    static let surfaceBaseLight = Color(red: 1.000, green: 1.000, blue: 1.000)
    static let surfaceSurfaceLight = Color(red: 0.961, green: 0.961, blue: 0.969)
    static let surfaceElevLight = Color(red: 0.984, green: 0.984, blue: 0.992)
    static let surfaceHairlineLight = Color(red: 0.824, green: 0.824, blue: 0.843)

    // MARK: Surface (dark)
    static let surfaceBaseDark = Color(red: 0.000, green: 0.000, blue: 0.000)
    static let surfaceSurfaceDark = Color(red: 0.110, green: 0.110, blue: 0.118)
    static let surfaceElevDark = Color(red: 0.039, green: 0.039, blue: 0.047)
    static let surfaceHairlineDark = Color(red: 0.173, green: 0.173, blue: 0.180)

    // MARK: Text (light)
    static let textPrimaryLight = Color(red: 0.114, green: 0.114, blue: 0.122)
    static let textSecondaryLight = Color(red: 0.431, green: 0.431, blue: 0.451)
    static let textMutedLight = Color(red: 0.631, green: 0.631, blue: 0.651)

    // MARK: Text (dark)
    static let textPrimaryDark = Color(red: 0.961, green: 0.961, blue: 0.969)
    static let textSecondaryDark = Color(red: 0.631, green: 0.631, blue: 0.651)
    static let textMutedDark = Color(red: 0.431, green: 0.431, blue: 0.451)

    // MARK: Partner
    static let partnerTwitch = Color(red: 0.569, green: 0.275, blue: 1.000)
    static let partnerDiscord = Color(red: 0.345, green: 0.396, blue: 0.949)
    static let partnerDiscordSurface = Color(red: 0.169, green: 0.176, blue: 0.192)
    static let partnerDiscordControl = Color(red: 0.306, green: 0.314, blue: 0.345)
    static let partnerAppleMusicStart = Color(red: 1.000, green: 0.365, blue: 0.545)
    static let partnerAppleMusicEnd = Color(red: 0.980, green: 0.137, blue: 0.231)
    static let partnerAppleMusicSurfaceStart = Color(red: 0.980, green: 0.361, blue: 0.459)
    static let partnerAppleMusicSurfaceEnd = Color(red: 0.980, green: 0.141, blue: 0.231)
    static let partnerAppleMusicPulseStart = Color(red: 0.988, green: 0.278, blue: 0.451)
    static let partnerAppleMusicPulseEnd = Color(red: 0.980, green: 0.102, blue: 0.322)
    static let partnerObsStart = Color(red: 0.173, green: 0.173, blue: 0.180)
    static let partnerObsEnd = Color(red: 0.102, green: 0.102, blue: 0.110)
    static let partnerWolfwaveGradientStart = Color(red: 0.039, green: 0.145, blue: 0.251)
    static let partnerWolfwaveGradientEnd = Color(red: 0.145, green: 0.388, blue: 0.922)
}

/// Generated typography sizes. CGFloat literals match prior hand-coded sizes.
nonisolated enum DSFont {
    enum Size {
        static let x9: CGFloat = 9
        static let x15: CGFloat = 15
        static let x16: CGFloat = 16
        static let x18: CGFloat = 18
        static let x24: CGFloat = 24
        static let x26: CGFloat = 26
        static let x28: CGFloat = 28
        static let x36: CGFloat = 36
        static let xs: CGFloat = 10
        static let sm: CGFloat = 11
        static let body: CGFloat = 12
        static let base: CGFloat = 13
        static let md: CGFloat = 14
        static let lg: CGFloat = 17
        static let xl: CGFloat = 20
        static let x2xl: CGFloat = 22
    }

    enum Weight {
        static let regular: Font.Weight = .regular
        static let medium: Font.Weight = .medium
        static let semibold: Font.Weight = .semibold
        static let bold: Font.Weight = .bold
    }
}

/// Generated spacing scale.
nonisolated enum DSSpace {
    static let s0: CGFloat = 2
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 10
    static let s4: CGFloat = 12
    static let s5: CGFloat = 14
    static let s6: CGFloat = 16
    static let s7: CGFloat = 20
    static let s8: CGFloat = 24
    static let s9: CGFloat = 28
    static let s10: CGFloat = 32
    static let s11: CGFloat = 44
    static let s1h: CGFloat = 6
}

/// Generated radius scale.
nonisolated enum DSRadius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 10
    static let lg2: CGFloat = 12
    static let xl: CGFloat = 14
    static let x2xl: CGFloat = 16
    static let pill: CGFloat = 9999
}

/// Generated motion tokens (durations in seconds for SwiftUI animations).
nonisolated enum DSMotion {
    enum Duration {
        static let instant: Double = 0
        static let fast: Double = 0.15
        static let base: Double = 0.22
        static let slow: Double = 0.32
        static let long: Double = 0.4
        static let pulse: Double = 0.9
        static let pulseSlow: Double = 1.4
    }

    /// Named spring presets. Use via `.spring(DSMotion.Spring.snappy)`.
    enum Spring {
        static let snappy = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.82, blendDuration: 0)
        static let bouncy = SwiftUI.Animation.spring(response: 0.45, dampingFraction: 0.78, blendDuration: 0)
        static let gentle = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0)
        static let expressive = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0)
    }
}

/// Window and onboarding dimension tokens (preserves legacy AppConstants values).
nonisolated enum DSDimension {
    enum Settings {
        static let minWidth: CGFloat = 880
        static let minHeight: CGFloat = 620
        static let idealWidth: CGFloat = 1240
        static let idealHeight: CGFloat = 780
        static let maxContentWidth: CGFloat = 720
        static let contentPaddingH: CGFloat = 28
        static let contentPaddingV: CGFloat = 22
        static let sectionSpacing: CGFloat = 24
        static let cardPadding: CGFloat = 16
        static let cardCornerRadius: CGFloat = 14
    }

    enum Onboarding {
        static let windowWidth: CGFloat = 680
        static let windowHeight: CGFloat = 560
        static let primaryButtonHeight: CGFloat = 32
        static let primaryButtonMinWidth: CGFloat = 200
        static let navButtonMinWidth: CGFloat = 80
        static let stepContentMinHeight: CGFloat = 220
        static let brandTileSize: CGFloat = 56
        static let brandTileRadius: CGFloat = 14
        static let primaryButtonRadius: CGFloat = 8
        static let iconTileSize: CGFloat = 28
        static let iconTileRadius: CGFloat = 7
    }

    enum About {
        static let windowWidth: CGFloat = 380
        static let windowHeight: CGFloat = 520
        static let minWidth: CGFloat = 360
        static let minHeight: CGFloat = 480
    }

    enum WhatsNew {
        static let windowWidth: CGFloat = 460
        static let windowHeight: CGFloat = 580
    }

    enum IconButton {
        static let minWidth: CGFloat = 22
        static let minHeight: CGFloat = 20
    }

    enum HistoryStats {
        static let recentCardMinHeight: CGFloat = 160
        static let chartHeight: CGFloat = 150
        static let twoColumnFloor: CGFloat = 580
        static let topListMinHeight: CGFloat = 190
        static let topTrackMinHeight: CGFloat = 44
        static let chartYAxisGutter: CGFloat = 28
    }
}

/// Generated widget theme palette. Mirrors `widget.html` so the in-app
/// appearance preview matches what overlays render. `nil` color = the
/// widget draws nothing for that layer (transparent background, no border).
nonisolated struct DSWidgetTheme {
    let containerBg: Color?
    let borderColor: Color?
    let cornerRadius: CGFloat
    let overlayBg: Color?
    let textPrimary: Color
    let textSecondary: Color
    let textMuted: Color
    let progressTrack: Color
    let progressFill: Color
    let showArtworkBlur: Bool
    /// `true` for themes whose text + background colors the user can override
    /// (Default, Glass). Preset themes ship fixed palettes.
    let userCustomizable: Bool
}

/// Generated widget theme + layout lookup for the appearance preview.
nonisolated enum DSWidgetThemes {
    /// Picker order, excluding `hidden` themes.
    static let order: [String] = ["Default", "Dark", "Light", "Glass", "Neon"]

    static let all: [String: DSWidgetTheme] = [
        "Default": DSWidgetTheme(
            containerBg: nil,
            borderColor: nil,
            cornerRadius: 12,
            overlayBg: Color(red: 0.000, green: 0.000, blue: 0.000, opacity: 0.500),
            textPrimary: Color(red: 1.000, green: 1.000, blue: 1.000),
            textSecondary: Color(red: 1.000, green: 1.000, blue: 1.000, opacity: 0.900),
            textMuted: Color(red: 1.000, green: 1.000, blue: 1.000, opacity: 0.700),
            progressTrack: Color(red: 1.000, green: 1.000, blue: 1.000, opacity: 0.200),
            progressFill: Color(red: 1.000, green: 1.000, blue: 1.000),
            showArtworkBlur: true,
            userCustomizable: true
        ),
        "Dark": DSWidgetTheme(
            containerBg: Color(red: 0.051, green: 0.051, blue: 0.051),
            borderColor: Color(red: 1.000, green: 1.000, blue: 1.000, opacity: 0.080),
            cornerRadius: 12,
            overlayBg: nil,
            textPrimary: Color(red: 0.894, green: 0.894, blue: 0.906),
            textSecondary: Color(red: 0.631, green: 0.631, blue: 0.667),
            textMuted: Color(red: 0.443, green: 0.443, blue: 0.478),
            progressTrack: Color(red: 1.000, green: 1.000, blue: 1.000, opacity: 0.080),
            progressFill: Color(red: 0.655, green: 0.545, blue: 0.980),
            showArtworkBlur: false,
            userCustomizable: false
        ),
        "Light": DSWidgetTheme(
            containerBg: Color(red: 1.000, green: 1.000, blue: 1.000, opacity: 0.920),
            borderColor: Color(red: 0.000, green: 0.000, blue: 0.000, opacity: 0.080),
            cornerRadius: 12,
            overlayBg: nil,
            textPrimary: Color(red: 0.094, green: 0.094, blue: 0.106),
            textSecondary: Color(red: 0.247, green: 0.247, blue: 0.275),
            textMuted: Color(red: 0.443, green: 0.443, blue: 0.478),
            progressTrack: Color(red: 0.000, green: 0.000, blue: 0.000, opacity: 0.080),
            progressFill: Color(red: 0.231, green: 0.510, blue: 0.965),
            showArtworkBlur: false,
            userCustomizable: false
        ),
        "Glass": DSWidgetTheme(
            containerBg: Color(red: 0.000, green: 0.000, blue: 0.000, opacity: 0.300),
            borderColor: Color(red: 1.000, green: 1.000, blue: 1.000, opacity: 0.100),
            cornerRadius: 16,
            overlayBg: nil,
            textPrimary: Color(red: 0.961, green: 0.961, blue: 0.969),
            textSecondary: Color(red: 0.961, green: 0.961, blue: 0.969, opacity: 0.800),
            textMuted: Color(red: 0.961, green: 0.961, blue: 0.969, opacity: 0.500),
            progressTrack: Color(red: 1.000, green: 1.000, blue: 1.000, opacity: 0.100),
            progressFill: Color(red: 0.000, green: 0.478, blue: 1.000),
            showArtworkBlur: false,
            userCustomizable: true
        ),
        "Neon": DSWidgetTheme(
            containerBg: Color(red: 0.039, green: 0.039, blue: 0.118, opacity: 0.850),
            borderColor: Color(red: 0.000, green: 1.000, blue: 0.667),
            cornerRadius: 12,
            overlayBg: nil,
            textPrimary: Color(red: 0.000, green: 1.000, blue: 0.667),
            textSecondary: Color(red: 0.000, green: 0.898, blue: 1.000),
            textMuted: Color(red: 0.000, green: 1.000, blue: 0.667, opacity: 0.500),
            progressTrack: Color(red: 0.000, green: 1.000, blue: 0.667, opacity: 0.150),
            progressFill: Color(red: 0.000, green: 1.000, blue: 0.667),
            showArtworkBlur: false,
            userCustomizable: false
        ),
        "WolfWave": DSWidgetTheme(
            containerBg: Color(red: 0.110, green: 0.110, blue: 0.118, opacity: 0.920),
            borderColor: Color(red: 0.039, green: 0.518, blue: 1.000, opacity: 0.400),
            cornerRadius: 14,
            overlayBg: nil,
            textPrimary: Color(red: 0.961, green: 0.961, blue: 0.969),
            textSecondary: Color(red: 0.631, green: 0.631, blue: 0.651),
            textMuted: Color(red: 0.431, green: 0.431, blue: 0.451),
            progressTrack: Color(red: 0.039, green: 0.518, blue: 1.000, opacity: 0.150),
            progressFill: Color(red: 0.039, green: 0.518, blue: 1.000),
            showArtworkBlur: true,
            userCustomizable: false
        ),
    ]

    static let fallback = DSWidgetTheme(
            containerBg: nil,
            borderColor: nil,
            cornerRadius: 12,
            overlayBg: Color(red: 0.000, green: 0.000, blue: 0.000, opacity: 0.500),
            textPrimary: Color(red: 1.000, green: 1.000, blue: 1.000),
            textSecondary: Color(red: 1.000, green: 1.000, blue: 1.000, opacity: 0.900),
            textMuted: Color(red: 1.000, green: 1.000, blue: 1.000, opacity: 0.700),
            progressTrack: Color(red: 1.000, green: 1.000, blue: 1.000, opacity: 0.200),
            progressFill: Color(red: 1.000, green: 1.000, blue: 1.000),
            showArtworkBlur: true,
            userCustomizable: true
        )

    /// Theme palette by name, falling back to Default for unknown names.
    static func resolve(_ name: String) -> DSWidgetTheme { all[name] ?? fallback }
}

/// Generated widget layout dimensions (points) used to size the preview.
nonisolated enum DSWidgetLayouts {
    static let sizes: [String: CGSize] = [
        "Horizontal": CGSize(width: 500, height: 100),
        "Vertical": CGSize(width: 220, height: 280),
        "Compact": CGSize(width: 350, height: 56),
    ]

    static func size(_ name: String) -> CGSize { sizes[name] ?? CGSize(width: 500, height: 100) }
}

