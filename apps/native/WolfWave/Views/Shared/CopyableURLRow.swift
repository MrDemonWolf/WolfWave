//
//  CopyableURLRow.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-02.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// A settings row that shows a copyable URL: an optional label with a
/// ``StreamerModeBadge``, the URL in a masked monospaced font, an optional
/// helper subtitle, and a trailing ``CopyButton``.
///
/// Folds together the four hand-rolled masked-URL rows in Stream Widgets
/// settings (local / network WebSocket addresses, widget webpage / network
/// widget addresses) so Streamer Mode masking, the badge guard, and the
/// copy-disabled rule live in one place instead of being re-typed per row.
///
/// Streamer Mode behavior is uniform: when `isStreamerMode` is on, the URL is
/// replaced with `StreamerMode.mask(_:style:.url:)`, the badge renders beside
/// the label, and the copy button (plus any `trailing` accessory) is disabled.
/// Pass `actionsDisabled` for an additional gate (e.g. the server is off).
///
/// ```swift
/// CopyableURLRow(
///     label: "Local Address",
///     url: connectionURL,
///     isStreamerMode: streamerMode,
///     actionsDisabled: !websocketEnabled,
///     copyAccessibilityLabel: "Copy local connection URL",
///     copyAccessibilityIdentifier: "copyConnectionURLButton"
/// )
/// ```
struct CopyableURLRow<Trailing: View>: View {

    // MARK: - Properties

    /// Optional leading label (e.g. "Local Address"). When `nil` the row leads
    /// straight into the URL, with the badge floated above it when masked.
    var label: String?

    /// The real URL. Used verbatim for copy + any `trailing` action; the
    /// displayed text is run through `StreamerMode.mask` first.
    let url: String

    /// Optional helper line beneath the URL (e.g. "Use this for two-PC setups.").
    var subtitle: String?

    /// Whether Streamer Mode masking is active. Drives the mask, the badge, and
    /// the disabled state of the copy button + trailing accessory.
    let isStreamerMode: Bool

    /// Extra disable gate beyond Streamer Mode (e.g. the server is stopped).
    var actionsDisabled: Bool = false

    /// Line limit for the URL text. `nil` lets it wrap freely; pass `2` for the
    /// wide standalone rows that have no competing trailing label column.
    var urlLineLimit: Int?

    /// Text label for the copy button. When `nil` the button renders icon-only.
    var copyLabel: String?

    /// "Copied" feedback label, paired with `copyLabel`.
    var copiedLabel: String?

    /// VoiceOver label for the copy button.
    let copyAccessibilityLabel: String

    /// Accessibility identifier for the copy button.
    var copyAccessibilityIdentifier: String?

    /// Optional trailing accessory rendered after the copy button (e.g.
    /// ``OpenInBrowserButton``). Receives the same effective disabled state via
    /// the caller: pass `isDisabled: actionsDisabled || isStreamerMode`.
    @ViewBuilder var trailing: () -> Trailing

    // MARK: - Init

    init(
        label: String? = nil,
        url: String,
        subtitle: String? = nil,
        isStreamerMode: Bool,
        actionsDisabled: Bool = false,
        urlLineLimit: Int? = nil,
        copyLabel: String? = nil,
        copiedLabel: String? = nil,
        copyAccessibilityLabel: String,
        copyAccessibilityIdentifier: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.label = label
        self.url = url
        self.subtitle = subtitle
        self.isStreamerMode = isStreamerMode
        self.actionsDisabled = actionsDisabled
        self.urlLineLimit = urlLineLimit
        self.copyLabel = copyLabel
        self.copiedLabel = copiedLabel
        self.copyAccessibilityLabel = copyAccessibilityLabel
        self.copyAccessibilityIdentifier = copyAccessibilityIdentifier
        self.trailing = trailing
    }

    // MARK: - Derived

    /// Copy + trailing actions are off whenever the server gate is closed or
    /// Streamer Mode is masking the value.
    private var effectiveDisabled: Bool {
        actionsDisabled || isStreamerMode
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: DSSpace.s2) {
            VStack(alignment: .leading, spacing: DSSpace.s0) {
                if let label {
                    HStack(spacing: DSSpace.s2) {
                        Text(label)
                            .font(.system(size: DSFont.Size.sm, weight: .medium))
                            .foregroundStyle(.secondary)
                        if isStreamerMode { StreamerModeBadge() }
                    }
                } else if isStreamerMode {
                    HStack { StreamerModeBadge(); Spacer() }
                }

                Text(StreamerMode.mask(url, style: .url, isOn: isStreamerMode))
                    .font(.system(size: DSFont.Size.body, design: .monospaced))
                    .textSelection(.enabled)
                    .contentTransition(.opacity)
                    .lineLimit(urlLineLimit)
                    .fixedSize(horizontal: false, vertical: urlLineLimit != nil)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: DSFont.Size.xs))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            HStack(spacing: DSSpace.s2) {
                CopyButton(
                    text: url,
                    label: copyLabel,
                    copiedLabel: copiedLabel,
                    isDisabled: effectiveDisabled,
                    accessibilityLabel: copyAccessibilityLabel,
                    accessibilityIdentifier: copyAccessibilityIdentifier
                )
                trailing()
            }
        }
    }
}

// MARK: - Preview

#Preview("Address rows") {
    VStack(spacing: DSSpace.s6) {
        CopyableURLRow(
            label: "Local Address",
            url: "ws://localhost:8765/?token=abcdef",
            isStreamerMode: false,
            copyAccessibilityLabel: "Copy local connection URL"
        )

        Divider()

        CopyableURLRow(
            label: "Network Address",
            url: "ws://192.168.1.20:8765/?token=abcdef",
            subtitle: "Use this for two-PC setups.",
            isStreamerMode: false,
            copyAccessibilityLabel: "Copy network connection URL"
        )

        Divider()

        CopyableURLRow(
            url: "http://localhost:8766",
            isStreamerMode: false,
            urlLineLimit: 2,
            copyLabel: "Copy Link",
            copiedLabel: "Copied",
            copyAccessibilityLabel: "Copy widget URL"
        ) {
            OpenInBrowserButton(
                urlString: "http://localhost:8766",
                accessibilityLabel: "Open widget in browser"
            )
        }

        Divider()

        CopyableURLRow(
            label: "Network Address",
            url: "http://192.168.1.20:8766/?token=abcdef",
            subtitle: "Use this for two-PC setups.",
            isStreamerMode: true,
            copyLabel: "Copy Link",
            copiedLabel: "Copied",
            copyAccessibilityLabel: "Copy network widget URL"
        ) {
            OpenInBrowserButton(
                urlString: "http://192.168.1.20:8766",
                isDisabled: true,
                accessibilityLabel: "Open network widget in browser"
            )
        }
    }
    .padding()
    .frame(width: 520)
}
