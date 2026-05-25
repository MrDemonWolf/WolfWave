//
//  DiscordButtonConfigRow.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 5/16/26.
//

import SwiftUI

/// Settings row for configuring a single Discord Rich Presence button.
///
/// Lets the user toggle the button on/off and previews the URL that will be sent.
struct DiscordButtonConfigRow: View {

    // MARK: - Properties

    /// Section title shown above the toggle (e.g. "Apple Music link").
    let title: String

    /// URL that the service would send for this button, or nil if unavailable.
    /// Displayed in monospaced gray below the toggle; "(no track playing)" when nil.
    let resolvedURL: String?

    /// User-visible accessibility identifier prefix (e.g. "discordButton1").
    let accessibilityPrefix: String

    @Binding var isEnabled: Bool

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s3) {
            ToggleSettingRow(
                title: title,
                subtitle: isEnabled
                    ? "Shown on your Discord profile."
                    : "Hidden from your Discord profile.",
                isOn: $isEnabled,
                accessibilityLabel: "\(title) enabled",
                accessibilityIdentifier: "\(accessibilityPrefix)Toggle"
            )

            Text(urlPreviewText)
                .font(.system(size: DSFont.Size.xs, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(resolvedURL ?? "")
                .opacity(isEnabled ? 1.0 : 0.5)
        }
    }

    // MARK: - Helpers

    private var urlPreviewText: String {
        if let url = resolvedURL, !url.isEmpty {
            return url
        }
        return "(no track playing — URL fills in once a song starts)"
    }
}

// MARK: - Preview

#Preview("Enabled") {
    DiscordButtonConfigRow(
        title: "Apple Music link",
        resolvedURL: "https://music.apple.com/us/album/example/123?i=456",
        accessibilityPrefix: "discordButton1Preview",
        isEnabled: .constant(true)
    )
    .padding()
    .frame(width: 480)
}

#Preview("Disabled") {
    DiscordButtonConfigRow(
        title: "Apple Music link",
        resolvedURL: nil,
        accessibilityPrefix: "discordButton1Preview",
        isEnabled: .constant(false)
    )
    .padding()
    .frame(width: 480)
}
