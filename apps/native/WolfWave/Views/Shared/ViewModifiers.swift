//
//  ViewModifiers.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-02-06.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI
import AppKit

// MARK: - Cursor Modifiers

extension View {
    /// Adds a pointing hand cursor when hovering over this view.
    ///
    /// Use for clickable elements that aren't standard buttons. Wraps SwiftUI's
    /// `.pointerStyle(.link)` (macOS 15+). The system manages push/pop so this
    /// never leaks like a manual `NSCursor.push`/`pop` pair would.
    func pointerCursor() -> some View {
        pointerStyle(.link)
    }
}

// MARK: - Interactive Row Style

/// A view modifier for interactive list rows with hover feedback.
struct InteractiveRowModifier: ViewModifier {
    @State private var isHovering = false
    let isEnabled: Bool

    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovering && isEnabled ? Color.primary.opacity(0.04) : Color.clear)
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: DSMotion.Duration.fast)) {
                    isHovering = hovering
                }
            }
            .pointerStyle(isEnabled ? .link : nil)
    }
}

extension View {
    /// Adds interactive row styling with hover feedback and pointer cursor.
    func interactiveRow(isEnabled: Bool = true) -> some View {
        modifier(InteractiveRowModifier(isEnabled: isEnabled))
    }
}

// MARK: - Card Style (macOS default surface)

/// Standard macOS card styling on an opaque grouped-content surface.
///
/// Uses the system `controlBackgroundColor` (the macOS default for grouped
/// content) with a `separatorColor` hairline border. Opaque on purpose. The
/// translucent `.glassEffect` version sampled a different backdrop per screen
/// position, so two identical cards rendered as different shades. A solid
/// surface is the same color everywhere and adapts to light and dark on its
/// own. Apply last in the chain: padding goes inside, frame/layout outside.
struct CardModifier: ViewModifier {
    var padded: Bool = true

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius)
        return Group {
            if padded {
                content
                    .padding(AppConstants.SettingsUI.cardPadding)
            } else {
                content
            }
        }
        .background(Color(nsColor: .controlBackgroundColor), in: shape)
        .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
    }
}

extension View {
    /// Applies the standard macOS card surface with padding and rounded corners.
    func cardStyle() -> some View {
        modifier(CardModifier(padded: true))
    }

    /// Applies the standard macOS card surface without internal padding, for
    /// rows that own their own padding.
    func cardStyleUnpadded() -> some View {
        modifier(CardModifier(padded: false))
    }

    /// Applies just the card clip-shape using a design-system radius.
    ///
    /// Use when you've already composed the background/material yourself
    /// (e.g. a custom-tinted card or an `.overlay`-based stroke) and only
    /// need the standard rounded corner. Defaults to the settings-card radius;
    /// pass a `DSRadius.*` value for nested rows.
    ///
    /// Prefer `cardStyle()` for the full card shell.
    func cardClipShape(radius: CGFloat = AppConstants.SettingsUI.cardCornerRadius) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - Pane Title Style (H1)

/// Top-level pane title styling: the single biggest heading on a settings pane.
///
/// This is the H1 of the type ramp. It sits two clear steps above the section
/// header (`.sectionHeader()`, 17pt) so the eye reads "pane → section → label"
/// without ambiguity. Per NN/g visual-hierarchy guidance, the most important
/// element is the biggest, and adjacent levels need a perceptible size step
/// (here 22 → 17 → 11) rather than the old 2pt 17 → 15 collision.
///
/// Carries the `.isHeader` accessibility trait so VoiceOver's heading rotor can
/// jump straight to each pane title. Use exactly once per pane, on the title.
struct PaneTitleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: DSFont.Size.x2xl, weight: .bold))
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// Applies the pane title style: 22pt bold, tagged as an accessibility header.
    ///
    /// H1 of the ramp. One per pane. For section titles inside a pane use
    /// `.sectionHeader()`; for in-card labels use `.sectionEyebrow()`.
    func paneTitle() -> some View {
        modifier(PaneTitleModifier())
    }
}

// MARK: - Section Header Style (H2)

/// Section header styling: the title of a section inside a pane.
///
/// H2 of the ramp (17pt semibold), one clear step below `.paneTitle()` (22pt)
/// and well above `.sectionEyebrow()` (11pt). Tagged as an accessibility header
/// so the VoiceOver heading rotor lands on every section.
struct SectionHeaderModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: DSFont.Size.lg, weight: .semibold))
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// Applies section header styling (17pt semibold, accessibility header).
    func sectionHeader() -> some View {
        modifier(SectionHeaderModifier())
    }
}

// MARK: - Section Eyebrow (Sentence-case micro-header)

/// Sentence-case micro-header used inside cards to label sub-sections
/// ("Recently played", "Top artists", "Bundle & build"). Replaces the
/// legacy ALL-CAPS + letter-spacing pattern. HIG (macOS 26) prefers
/// sentence case for in-card labels; reserve full caps for tiny eyebrow
/// tags above hero cards only.
struct SectionEyebrowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: DSFont.Size.sm, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

extension View {
    /// Applies the section eyebrow style: sentence-case, sm, semibold, secondary.
    ///
    /// Use for in-card sub-section labels (e.g. `Text("Recently played").sectionEyebrow()`).
    /// Pairs naturally with a leading SF Symbol via `Label(_, systemImage:)`.
    func sectionEyebrow() -> some View {
        modifier(SectionEyebrowModifier())
    }
}

// MARK: - Body Subtitle / Caption (secondary text levels)

/// Secondary body text that sits under a `.paneTitle()` or `.sectionHeader()`:
/// the one-line "what this does" subtitle, and inline helper copy.
///
/// One source of truth for the `base` (13pt) secondary text that had been
/// hand-rolled as `.font(.system(size: DSFont.Size.base)).foregroundStyle(.secondary)`
/// across most panes. Keeps the ramp at three heading sizes + one body size.
struct FieldSubtitleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: DSFont.Size.base))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Smallest text level: footnotes, legal lines, timestamps. 10pt secondary.
struct CaptionTextModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: DSFont.Size.xs))
            .foregroundStyle(.secondary)
    }
}

extension View {
    /// Secondary subtitle/helper text (13pt secondary). Pairs with a heading.
    func fieldSubtitle() -> some View {
        modifier(FieldSubtitleModifier())
    }

    /// Caption/footnote text (10pt secondary). The bottom of the type ramp.
    func captionText() -> some View {
        modifier(CaptionTextModifier())
    }
}

// MARK: - Stable Width (No State-Change Resize)

extension View {
    /// Locks the view's width to the widest of the provided ghost labels so
    /// state changes (idle → testing → success/failure, etc.) never resize
    /// the button or pill. Ghost labels render hidden in the background and
    /// are excluded from hit-testing and accessibility.
    ///
    /// Adapts automatically to localization, dynamic type, and new states;
    /// no magic `minWidth` values needed.
    func stableWidth<Ghost: View>(@ViewBuilder ghosts: () -> Ghost) -> some View {
        background(
            ZStack { ghosts() }
                .hidden()
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Reduce-Motion Helpers

/// Returns the supplied animation, or `.none` when the user has Reduce Motion
/// enabled in System Settings → Accessibility.
///
/// Use at call sites that opt in to motion:
///
/// ```swift
/// @Environment(\.accessibilityReduceMotion) private var reduceMotion
/// // …
/// .animation(.reducedMotion(.easeInOut(duration: DSMotion.Duration.base),
///                           reduceMotion: reduceMotion),
///            value: state)
/// ```
extension Animation {
    /// Returns `self` when reduce-motion is off, `nil` otherwise.
    static func reducedMotion(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

extension View {
    /// Applies an animation that respects the user's Reduce Motion preference.
    ///
    /// Wraps `.animation(_:value:)` and substitutes `nil` (no animation) when
    /// `reduceMotion` is `true`. Pull the value via
    /// `@Environment(\.accessibilityReduceMotion)`.
    func reduceMotionAware<V: Equatable>(
        _ animation: Animation,
        reduceMotion: Bool,
        value: V
    ) -> some View {
        self.animation(reduceMotion ? nil : animation, value: value)
    }
}

// MARK: - Skeleton Loading

/// A view modifier that renders the content as a redacted placeholder while
/// `isLoading` is true. Use instead of swapping in custom shimmer rows. The
/// system handles VoiceOver suppression and respects Reduce Motion.
struct SkeletonModifier: ViewModifier {
    let isLoading: Bool

    func body(content: Content) -> some View {
        content
            .redacted(reason: isLoading ? .placeholder : [])
            .accessibilityHidden(isLoading)
            .allowsHitTesting(!isLoading)
    }
}

extension View {
    /// Renders this view as a redacted placeholder when `isLoading` is true.
    ///
    /// Use for first-paint loading states (queue lists, validation results,
    /// search-in-flight). The redacted reason is `.placeholder`, which renders
    /// the content as opaque shapes. Hit-testing and VoiceOver are suppressed
    /// while loading so the user can't tap or hear stale data.
    func skeleton(_ isLoading: Bool) -> some View {
        modifier(SkeletonModifier(isLoading: isLoading))
    }
}

// MARK: - Notification Posting Helper

extension NotificationCenter {
    /// Posts a notification using a string name from `AppConstants.Notifications`.
    ///
    /// Shorthand for the verbose `post(name: NSNotification.Name(...), object: nil, userInfo:)` pattern.
    func post(_ name: String, userInfo: [String: Any]? = nil) {
        post(name: NSNotification.Name(name), object: nil, userInfo: userInfo)
    }
}

// MARK: - Color Hex Initializer

extension Color {
    /// Creates a Color from a hex string (e.g. "#FF0000" or "FF0000").
    /// `nonisolated` — a pure parser with no main-actor state, so non-UI code
    /// (e.g. the widget theme resolver) can call it off the main actor.
    nonisolated init?(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") { hexString.removeFirst() }
        guard hexString.count == 6, let value = UInt64(hexString, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    /// Converts the color to an uppercase hex string (e.g. "#FF0000").
    ///
    /// Returns `nil` if the color cannot be represented in the sRGB color space.
    func toHex() -> String? {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = Int((components.redComponent * 255).rounded())
        let g = Int((components.greenComponent * 255).rounded())
        let b = Int((components.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Previews

#Preview("Modifier samples") {
    VStack(alignment: .leading, spacing: DSSpace.s5) {
        // The type ramp, top to bottom: 22 → 17 → 11 headings + body + caption.
        Text("Pane Title (H1)")
            .paneTitle()

        Text("Section Header (H2)")
            .sectionHeader()

        Text("In-card eyebrow (H3)")
            .sectionEyebrow()

        VStack(alignment: .leading, spacing: DSSpace.s2) {
            Text("Card with .cardStyle()")
                .sectionHeader()
            Text("Opaque surface, internal padding, rounded corners.")
                .fieldSubtitle()
            Text("Caption / footnote level.")
                .captionText()
        }
        .cardStyle()

        Text("Hover for pointer cursor")
            .font(.system(size: DSFont.Size.body))
            .padding(DSSpace.s3)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .pointerCursor()
    }
    .padding()
    .frame(width: 480)
}
