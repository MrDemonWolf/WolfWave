//
//  CopyButton.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-03-27.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// A reusable copy-to-clipboard button with optional visual feedback.
/// Shows a checkmark icon briefly after copying.
struct CopyButton: View {

    // MARK: - Properties

    let text: String
    var label: String? = nil
    var copiedLabel: String? = nil
    var buttonStyle: CopyButtonStyle = .bordered
    var isDisabled: Bool = false
    var accessibilityLabel: String
    var accessibilityIdentifier: String? = nil
    var feedbackDuration: TimeInterval = 2.0
    /// Optional side effect fired right after the text is copied (e.g. a parent
    /// status update). The pasteboard write + checkmark feedback are handled
    /// internally regardless.
    var action: (() -> Void)? = nil

    @State private var copied = false

    // MARK: - Body

    var body: some View {
        let button = Button {
            Pasteboard.copy(text)
            action?()
            copied = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(feedbackDuration))
                copied = false
            }
        } label: {
            if let label, let copiedLabel {
                HStack(spacing: DSSpace.s1) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: DSFont.Size.sm))
                    Text(copied ? copiedLabel : label)
                        .font(.system(size: DSFont.Size.sm))
                }
            } else {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: DSFont.Size.sm))
            }
        }
        .modifier(CopyButtonStyleModifier(style: buttonStyle))
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Copies text to clipboard")
        .accessibilityValue(copied ? "Copied" : "Not copied")

        button.accessibilityIdentifier(optional: accessibilityIdentifier)
    }

    // MARK: - Style

    enum CopyButtonStyle {
        case bordered
        case borderless
    }
}

// MARK: - Style Modifier

private struct CopyButtonStyleModifier: ViewModifier {
    let style: CopyButton.CopyButtonStyle

    func body(content: Content) -> some View {
        switch style {
        case .bordered:
            content
                .buttonStyle(.bordered)
                .controlSize(.small)
        case .borderless:
            content
                .buttonStyle(.borderless)
                .pointerCursor()
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: DSSpace.s6) {
        CopyButton(
            text: "ws://localhost:9090",
            accessibilityLabel: "Copy URL"
        )

        CopyButton(
            text: "http://localhost:9091/widget",
            label: "Copy Link",
            copiedLabel: "Copied",
            accessibilityLabel: "Copy widget URL"
        )

        CopyButton(
            text: "brew upgrade wolfwave",
            buttonStyle: .borderless,
            accessibilityLabel: "Copy brew command"
        )
    }
    .padding()
}
