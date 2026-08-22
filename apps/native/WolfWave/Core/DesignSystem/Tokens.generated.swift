// WolfWave Design System. GENERATED FILE. Do not edit by hand.
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
    static let neutral = Color(red: 0.557, green: 0.557, blue: 0.576)

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

    /// Every token above, in source order. Drives the Debug design-system gallery.
    static let groups: [(name: String, tokens: [(name: String, hex: String, color: Color)])] = [
        (name: "Brand", tokens: [
            (name: "brand50", hex: "#F0F7FF", color: brand50),
            (name: "brand100", hex: "#D9ECFF", color: brand100),
            (name: "brand200", hex: "#B0D6FF", color: brand200),
            (name: "brand300", hex: "#7FB8FF", color: brand300),
            (name: "brand400", hex: "#4A9CFF", color: brand400),
            (name: "brand500", hex: "#0A84FF", color: brand500),
            (name: "brand600", hex: "#0066CC", color: brand600),
            (name: "brand700", hex: "#004E9F", color: brand700),
            (name: "brand800", hex: "#003A78", color: brand800),
            (name: "brand900", hex: "#002551", color: brand900),
        ]),
        (name: "Semantic", tokens: [
            (name: "success", hex: "#34C759", color: success),
            (name: "warning", hex: "#FF9F0A", color: warning),
            (name: "error", hex: "#FF453A", color: error),
            (name: "info", hex: "#0A84FF", color: info),
            (name: "neutral", hex: "#8E8E93", color: neutral),
        ]),
        (name: "Surface (light)", tokens: [
            (name: "surfaceBaseLight", hex: "#FFFFFF", color: surfaceBaseLight),
            (name: "surfaceSurfaceLight", hex: "#F5F5F7", color: surfaceSurfaceLight),
            (name: "surfaceElevLight", hex: "#FBFBFD", color: surfaceElevLight),
            (name: "surfaceHairlineLight", hex: "#D2D2D7", color: surfaceHairlineLight),
        ]),
        (name: "Surface (dark)", tokens: [
            (name: "surfaceBaseDark", hex: "#000000", color: surfaceBaseDark),
            (name: "surfaceSurfaceDark", hex: "#1C1C1E", color: surfaceSurfaceDark),
            (name: "surfaceElevDark", hex: "#0A0A0C", color: surfaceElevDark),
            (name: "surfaceHairlineDark", hex: "#2C2C2E", color: surfaceHairlineDark),
        ]),
        (name: "Text (light)", tokens: [
            (name: "textPrimaryLight", hex: "#1D1D1F", color: textPrimaryLight),
            (name: "textSecondaryLight", hex: "#6E6E73", color: textSecondaryLight),
            (name: "textMutedLight", hex: "#A1A1A6", color: textMutedLight),
        ]),
        (name: "Text (dark)", tokens: [
            (name: "textPrimaryDark", hex: "#F5F5F7", color: textPrimaryDark),
            (name: "textSecondaryDark", hex: "#A1A1A6", color: textSecondaryDark),
            (name: "textMutedDark", hex: "#6E6E73", color: textMutedDark),
        ]),
        (name: "Partner", tokens: [
            (name: "partnerTwitch", hex: "#9146FF", color: partnerTwitch),
            (name: "partnerDiscord", hex: "#5865F2", color: partnerDiscord),
            (name: "partnerDiscordSurface", hex: "#2B2D31", color: partnerDiscordSurface),
            (name: "partnerDiscordControl", hex: "#4E5058", color: partnerDiscordControl),
            (name: "partnerAppleMusicStart", hex: "#FF5D8B", color: partnerAppleMusicStart),
            (name: "partnerAppleMusicEnd", hex: "#FA233B", color: partnerAppleMusicEnd),
            (name: "partnerAppleMusicSurfaceStart", hex: "#FA5C75", color: partnerAppleMusicSurfaceStart),
            (name: "partnerAppleMusicSurfaceEnd", hex: "#FA243B", color: partnerAppleMusicSurfaceEnd),
            (name: "partnerAppleMusicPulseStart", hex: "#FC4773", color: partnerAppleMusicPulseStart),
            (name: "partnerAppleMusicPulseEnd", hex: "#FA1A52", color: partnerAppleMusicPulseEnd),
            (name: "partnerObsStart", hex: "#2C2C2E", color: partnerObsStart),
            (name: "partnerObsEnd", hex: "#1A1A1C", color: partnerObsEnd),
            (name: "partnerWolfwaveGradientStart", hex: "#0A2540", color: partnerWolfwaveGradientStart),
            (name: "partnerWolfwaveGradientEnd", hex: "#2563EB", color: partnerWolfwaveGradientEnd),
        ]),
    ]
}

/// Generated typography sizes. CGFloat literals match prior hand-coded sizes.
nonisolated enum DSFont {
    enum Size {
        static let xs: CGFloat = 10
        static let sm: CGFloat = 11
        static let body: CGFloat = 12
        static let base: CGFloat = 13
        static let md: CGFloat = 14
        static let lg: CGFloat = 17
        static let xl: CGFloat = 20
        static let x2xl: CGFloat = 22
        static let x3xl: CGFloat = 26
        static let display: CGFloat = 52

        /// Every token above, in source order. Drives the Debug design-system gallery.
        static let all: [(name: String, value: CGFloat)] = [
            (name: "xs", value: xs),
            (name: "sm", value: sm),
            (name: "body", value: body),
            (name: "base", value: base),
            (name: "md", value: md),
            (name: "lg", value: lg),
            (name: "xl", value: xl),
            (name: "x2xl", value: x2xl),
            (name: "x3xl", value: x3xl),
            (name: "display", value: display),
        ]
    }

    enum Weight {
        static let regular: Font.Weight = .regular
        static let medium: Font.Weight = .medium
        static let semibold: Font.Weight = .semibold
        static let bold: Font.Weight = .bold

        /// Every token above, in source order. Drives the Debug design-system gallery.
        static let all: [(name: String, value: Font.Weight)] = [
            (name: "regular", value: regular),
            (name: "medium", value: medium),
            (name: "semibold", value: semibold),
            (name: "bold", value: bold),
        ]
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

    /// Every token above, in source order. Drives the Debug design-system gallery.
    static let all: [(name: String, value: CGFloat)] = [
        (name: "s0", value: s0),
        (name: "s1", value: s1),
        (name: "s1h", value: s1h),
        (name: "s2", value: s2),
        (name: "s3", value: s3),
        (name: "s4", value: s4),
        (name: "s5", value: s5),
        (name: "s6", value: s6),
        (name: "s7", value: s7),
        (name: "s8", value: s8),
        (name: "s9", value: s9),
        (name: "s10", value: s10),
        (name: "s11", value: s11),
    ]
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

    /// Every token above, in source order. Drives the Debug design-system gallery.
    static let all: [(name: String, value: CGFloat)] = [
        (name: "xs", value: xs),
        (name: "sm", value: sm),
        (name: "md", value: md),
        (name: "lg", value: lg),
        (name: "lg2", value: lg2),
        (name: "xl", value: xl),
        (name: "x2xl", value: x2xl),
        (name: "pill", value: pill),
    ]
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

        /// Every token above, in source order. Drives the Debug design-system gallery.
        static let all: [(name: String, value: Double)] = [
            (name: "instant", value: instant),
            (name: "fast", value: fast),
            (name: "base", value: base),
            (name: "slow", value: slow),
            (name: "long", value: long),
            (name: "pulse", value: pulse),
            (name: "pulseSlow", value: pulseSlow),
        ]
    }

    /// Named spring presets. Use via `.spring(DSMotion.Spring.snappy)`.
    enum Spring {
        static let snappy = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.82, blendDuration: 0)
        static let bouncy = SwiftUI.Animation.spring(response: 0.45, dampingFraction: 0.78, blendDuration: 0)
        static let gentle = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0)
        static let expressive = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0)

        /// Every token above, in source order. Drives the Debug design-system gallery.
        static let all: [(name: String, response: Double, damping: Double, animation: SwiftUI.Animation)] = [
            (name: "snappy", response: 0.35, damping: 0.82, animation: snappy),
            (name: "bouncy", response: 0.45, damping: 0.78, animation: bouncy),
            (name: "gentle", response: 0.3, damping: 0.6, animation: gentle),
            (name: "expressive", response: 0.5, damping: 0.6, animation: expressive),
        ]
    }
}

/// Window and onboarding dimension tokens (preserves legacy AppConstants values).
nonisolated enum DSDimension {
    enum Settings {
        static let minWidth: CGFloat = 880
        static let minHeight: CGFloat = 620
        static let idealWidth: CGFloat = 1240
        static let idealHeight: CGFloat = 780
        static let sidebarWidth: CGFloat = 230
        static let maxContentWidth: CGFloat = 720
        static let contentPaddingH: CGFloat = 28
        static let contentPaddingV: CGFloat = 22
        static let sectionSpacing: CGFloat = 24
        static let cardPadding: CGFloat = 16
        static let cardCornerRadius: CGFloat = 14
        static let stepNumberGutter: CGFloat = 18
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

    /// Every token above, in source order. Drives the Debug design-system gallery.
    static let groups: [(name: String, tokens: [(name: String, value: CGFloat)])] = [
        (name: "Settings", tokens: [
            (name: "minWidth", value: Settings.minWidth),
            (name: "minHeight", value: Settings.minHeight),
            (name: "idealWidth", value: Settings.idealWidth),
            (name: "idealHeight", value: Settings.idealHeight),
            (name: "sidebarWidth", value: Settings.sidebarWidth),
            (name: "maxContentWidth", value: Settings.maxContentWidth),
            (name: "contentPaddingH", value: Settings.contentPaddingH),
            (name: "contentPaddingV", value: Settings.contentPaddingV),
            (name: "sectionSpacing", value: Settings.sectionSpacing),
            (name: "cardPadding", value: Settings.cardPadding),
            (name: "cardCornerRadius", value: Settings.cardCornerRadius),
            (name: "stepNumberGutter", value: Settings.stepNumberGutter),
        ]),
        (name: "Onboarding", tokens: [
            (name: "windowWidth", value: Onboarding.windowWidth),
            (name: "windowHeight", value: Onboarding.windowHeight),
            (name: "primaryButtonHeight", value: Onboarding.primaryButtonHeight),
            (name: "primaryButtonMinWidth", value: Onboarding.primaryButtonMinWidth),
            (name: "navButtonMinWidth", value: Onboarding.navButtonMinWidth),
            (name: "stepContentMinHeight", value: Onboarding.stepContentMinHeight),
            (name: "brandTileSize", value: Onboarding.brandTileSize),
            (name: "brandTileRadius", value: Onboarding.brandTileRadius),
            (name: "primaryButtonRadius", value: Onboarding.primaryButtonRadius),
            (name: "iconTileSize", value: Onboarding.iconTileSize),
            (name: "iconTileRadius", value: Onboarding.iconTileRadius),
        ]),
        (name: "About", tokens: [
            (name: "windowWidth", value: About.windowWidth),
            (name: "windowHeight", value: About.windowHeight),
            (name: "minWidth", value: About.minWidth),
            (name: "minHeight", value: About.minHeight),
        ]),
        (name: "WhatsNew", tokens: [
            (name: "windowWidth", value: WhatsNew.windowWidth),
            (name: "windowHeight", value: WhatsNew.windowHeight),
        ]),
        (name: "IconButton", tokens: [
            (name: "minWidth", value: IconButton.minWidth),
            (name: "minHeight", value: IconButton.minHeight),
        ]),
        (name: "HistoryStats", tokens: [
            (name: "recentCardMinHeight", value: HistoryStats.recentCardMinHeight),
            (name: "chartHeight", value: HistoryStats.chartHeight),
            (name: "twoColumnFloor", value: HistoryStats.twoColumnFloor),
            (name: "topListMinHeight", value: HistoryStats.topListMinHeight),
            (name: "topTrackMinHeight", value: HistoryStats.topTrackMinHeight),
            (name: "chartYAxisGutter", value: HistoryStats.chartYAxisGutter),
        ]),
    ]
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
            containerBg: Color(red: 0.000, green: 0.000, blue: 0.000, opacity: 0.500),
            borderColor: Color(red: 1.000, green: 1.000, blue: 1.000, opacity: 0.100),
            cornerRadius: 16,
            overlayBg: nil,
            textPrimary: Color(red: 0.961, green: 0.961, blue: 0.969),
            textSecondary: Color(red: 0.961, green: 0.961, blue: 0.969, opacity: 0.800),
            textMuted: Color(red: 0.961, green: 0.961, blue: 0.969, opacity: 0.600),
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
        "Vinyl": CGSize(width: 260, height: 300),
        "Classic": CGSize(width: 440, height: 112),
    ]

    static func size(_ name: String) -> CGSize { sizes[name] ?? CGSize(width: 500, height: 100) }
}

