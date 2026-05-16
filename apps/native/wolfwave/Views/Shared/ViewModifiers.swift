//
//  ViewModifiers.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import SwiftUI
import AppKit

// MARK: - Cursor Modifiers

/// A view modifier that changes the cursor to a pointing hand on hover.
/// Use this for clickable elements that aren't standard buttons.
struct PointerCursorModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

/// A view modifier that shows the not-allowed cursor for disabled elements.
struct DisabledCursorModifier: ViewModifier {
    let isDisabled: Bool

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if isDisabled {
                    if hovering {
                        NSCursor.operationNotAllowed.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
    }
}

// MARK: - View Extensions

extension View {
    /// Adds a pointing hand cursor when hovering over this view.
    /// Use for clickable elements that aren't standard buttons.
    func pointerCursor() -> some View {
        modifier(PointerCursorModifier())
    }

    /// Shows not-allowed cursor when the element is disabled.
    func disabledCursor(_ isDisabled: Bool) -> some View {
        modifier(DisabledCursorModifier(isDisabled: isDisabled))
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
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
                if isEnabled {
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
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
            .font(.system(size: 17, weight: .semibold))
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
            .font(.system(size: 15, weight: .semibold))
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
