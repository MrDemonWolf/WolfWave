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

// MARK: - Card Style

/// Standard card background styling.
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppConstants.SettingsUI.cardPadding)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))
    }
}

extension View {
    /// Applies standard card styling with padding, background, and corner radius.
    func cardStyle() -> some View {
        modifier(CardModifier())
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
