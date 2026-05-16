//
//  DiscordButtonConfigRow.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 5/16/26.
//

import SwiftUI

/// Settings row for configuring a single Discord Rich Presence button.
///
/// Lets the user toggle the button on/off, override its label (with placeholder
/// showing the default), and preview the URL that will be sent. The label field
/// enforces Discord's 32-character cap with a live counter.
struct DiscordButtonConfigRow: View {

    // MARK: - Properties

    /// Section title shown above the toggle (e.g. "Button 1").
    let title: String

    /// Default label shown as `TextField` placeholder when the override is empty.
    let defaultLabel: String

    /// URL that the service would send for this button, or nil if unavailable.
    /// Displayed in monospaced gray below the field; "(no track playing)" when nil.
    let resolvedURL: String?

    /// User-visible accessibility identifier prefix (e.g. "discordButton1").
    let accessibilityPrefix: String

    @Binding var isEnabled: Bool
    @Binding var customLabel: String

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    Text(isEnabled
                         ? "Shown on your Discord profile."
                         : "Hidden from your Discord profile.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("\(title) enabled")
                    .accessibilityIdentifier("\(accessibilityPrefix)Toggle")
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField(defaultLabel, text: $customLabel)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!isEnabled)
                        .accessibilityLabel("\(title) label")
                        .accessibilityIdentifier("\(accessibilityPrefix)LabelField")
                        .onChange(of: customLabel) { _, newValue in
                            let max = AppConstants.Discord.buttonLabelMaxLength
                            if newValue.count > max {
                                customLabel = String(newValue.prefix(max))
                            }
                        }

                    if !customLabel.isEmpty {
                        Button("Reset") {
                            customLabel = ""
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Restore the default label: \(defaultLabel)")
                        .accessibilityIdentifier("\(accessibilityPrefix)ResetButton")
                    }

                    Text("\(customLabel.count)/\(AppConstants.Discord.buttonLabelMaxLength)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .frame(minWidth: 38, alignment: .trailing)
                }

                Text(urlPreviewText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(resolvedURL ?? "")
            }
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

#Preview("Enabled, default label") {
    DiscordButtonConfigRow(
        title: "Button 1",
        defaultLabel: "Listen on Apple Music",
        resolvedURL: "https://music.apple.com/us/album/example/123?i=456",
        accessibilityPrefix: "discordButton1Preview",
        isEnabled: .constant(true),
        customLabel: .constant("")
    )
    .padding()
    .frame(width: 480)
}

#Preview("Custom label") {
    DiscordButtonConfigRow(
        title: "Button 2",
        defaultLabel: "Find on Other Services",
        resolvedURL: "https://song.link/i/123456",
        accessibilityPrefix: "discordButton2Preview",
        isEnabled: .constant(true),
        customLabel: .constant("Stream it 🎧")
    )
    .padding()
    .frame(width: 480)
}

#Preview("Disabled") {
    DiscordButtonConfigRow(
        title: "Button 1",
        defaultLabel: "Listen on Apple Music",
        resolvedURL: nil,
        accessibilityPrefix: "discordButton1Preview",
        isEnabled: .constant(false),
        customLabel: .constant("")
    )
    .padding()
    .frame(width: 480)
}
