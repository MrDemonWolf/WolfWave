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
    static let partnerAppleMusicStart = Color(red: 1.000, green: 0.365, blue: 0.545)
    static let partnerAppleMusicEnd = Color(red: 0.980, green: 0.137, blue: 0.231)
    static let partnerObsStart = Color(red: 0.173, green: 0.173, blue: 0.180)
    static let partnerObsEnd = Color(red: 0.102, green: 0.102, blue: 0.110)
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
}

/// Generated radius scale.
nonisolated enum DSRadius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 10
    static let xl: CGFloat = 14
    static let x2xl: CGFloat = 16
    static let pill: CGFloat = 9999
}

/// Generated motion tokens (durations in seconds for SwiftUI animations).
nonisolated enum DSMotion {
    enum Duration {
        static let fast: Double = 0.15
        static let base: Double = 0.22
        static let slow: Double = 0.32
    }
}

/// Window and onboarding dimension tokens (preserves legacy AppConstants values).
nonisolated enum DSDimension {
    enum Settings {
        static let minWidth: CGFloat = 720
        static let minHeight: CGFloat = 520
        static let idealWidth: CGFloat = 900
        static let idealHeight: CGFloat = 600
        static let maxContentWidth: CGFloat = 720
        static let contentPaddingH: CGFloat = 28
        static let contentPaddingV: CGFloat = 22
        static let sectionSpacing: CGFloat = 24
        static let cardPadding: CGFloat = 16
        static let cardCornerRadius: CGFloat = 14
    }

    enum Onboarding {
        static let windowWidth: CGFloat = 600
        static let windowHeight: CGFloat = 480
        static let primaryButtonHeight: CGFloat = 32
        static let primaryButtonMinWidth: CGFloat = 200
        static let navButtonMinWidth: CGFloat = 80
        static let stepContentMinHeight: CGFloat = 220
        static let brandTileSize: CGFloat = 56
        static let brandTileRadius: CGFloat = 14
        static let primaryButtonRadius: CGFloat = 8
    }
}

