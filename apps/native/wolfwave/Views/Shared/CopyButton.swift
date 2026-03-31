//
//  CopyButton.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 3/22/26.
//

import SwiftUI
import AppKit

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

    @State private var copied = false

    // MARK: - Body

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + feedbackDuration) {
                copied = false
            }
        } label: {
            if let label, let copiedLabel {
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                    Text(copied ? copiedLabel : label)
                        .font(.system(size: 11))
                }
            } else {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
            }
        }
        .modifier(CopyButtonStyleModifier(style: buttonStyle))
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Copies text to clipboard")
        .accessibilityValue(copied ? "Copied" : "Not copied")
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
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
    VStack(spacing: 16) {
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
