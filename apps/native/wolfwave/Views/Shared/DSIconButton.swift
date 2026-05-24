import SwiftUI

/// Bordered, small-control icon button sized to align with `CopyButton` and
/// other `.bordered .small` neighbors. Use this instead of hand-rolling
/// `Button { Image(...) } .buttonStyle(.bordered) .controlSize(.small)` so
/// every icon-only button shares the same width/height baseline.
struct DSIconButton: View {

    // MARK: - Properties

    let systemImage: String
    let action: () -> Void
    var isDisabled: Bool = false
    var accessibilityLabel: String
    var accessibilityIdentifier: String?

    // MARK: - Body

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: DSFont.Size.sm))
                .frame(
                    minWidth: DSDimension.IconButton.minWidth,
                    minHeight: DSDimension.IconButton.minHeight
                )
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: DSSpace.s2) {
        DSIconButton(
            systemImage: "eye",
            action: {},
            accessibilityLabel: "Reveal"
        )
        DSIconButton(
            systemImage: "arrow.clockwise",
            action: {},
            accessibilityLabel: "Refresh"
        )
        CopyButton(
            text: "preview",
            label: "Copy",
            copiedLabel: "Copied",
            accessibilityLabel: "Copy"
        )
    }
    .padding()
}
