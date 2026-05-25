//
//  ViewModifiers.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import SwiftUI
import AppKit

// MARK: - Cursor Modifiers

extension View {
    /// Adds a pointing hand cursor when hovering over this view.
    ///
    /// Use for clickable elements that aren't standard buttons. Wraps SwiftUI's
    /// `.pointerStyle(.link)` (macOS 15+) — the system manages push/pop so this
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

// MARK: - Card Style (Liquid Glass)

/// Glass card styling using macOS 26 `.glassEffect()`.
///
/// Replaces the legacy `controlBackgroundColor` fill with a translucent
/// glass surface that picks up wallpaper bloom and adapts to light/dark
/// automatically. Apply glass last in the modifier chain — padding goes
/// inside, frame/layout goes outside.
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
        .glassEffect(.regular, in: shape)
    }
}

extension View {
    /// Applies standard glass card styling with padding and rounded corners.
    func cardStyle() -> some View {
        modifier(CardModifier(padded: true))
    }

    /// Applies glass card styling without internal padding — for rows that
    /// own their own padding.
    func cardStyleUnpadded() -> some View {
        modifier(CardModifier(padded: false))
    }
}

// MARK: - Section Header Style

/// Standard section header styling.
struct SectionHeaderModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: DSFont.Size.lg, weight: .semibold))
    }
}

extension View {
    /// Applies standard section header styling.
    func sectionHeader() -> some View {
        modifier(SectionHeaderModifier())
    }
}

// MARK: - Section Sub-Header Style

/// Sub-section header styling (H2 level).
struct SectionSubHeaderModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: DSFont.Size.x15, weight: .semibold))
    }
}

extension View {
    /// Applies sub-section header styling (15pt semibold).
    func sectionSubHeader() -> some View {
        modifier(SectionSubHeaderModifier())
    }
}

// MARK: - Stable Width (No State-Change Resize)

extension View {
    /// Locks the view's width to the widest of the provided ghost labels so
    /// state changes (idle → testing → success/failure, etc.) never resize
    /// the button or pill. Ghost labels render hidden in the background and
    /// are excluded from hit-testing and accessibility.
    ///
    /// Adapts automatically to localization, dynamic type, and new states —
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
/// `isLoading` is true. Use instead of swapping in custom shimmer rows — the
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
    init?(hex: String) {
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
        Text("Section Header")
            .sectionHeader()

        Text("Sub-section header")
            .sectionSubHeader()

        VStack(alignment: .leading, spacing: DSSpace.s2) {
            Text("Card with .cardStyle()")
                .sectionSubHeader()
            Text("Glass surface, internal padding, rounded corners.")
                .font(.system(size: DSFont.Size.body))
                .foregroundStyle(.secondary)
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
