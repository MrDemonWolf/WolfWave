//
//  OnboardingOBSWidgetStepView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-02-13.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// OBS overlay step. One toggle drives both the WebSocket feed and the widget
/// HTTP server so streamers see a single, useful Browser Source URL instead of
/// chaining two switches. Advanced users can split them later in Settings.
struct OnboardingOBSWidgetStepView: View {

    // MARK: - Properties

    @Binding var websocketEnabled: Bool

    @AppStorage(AppConstants.UserDefaults.streamerModeEnabled)
    private var streamerMode = false

    @AppStorage(AppConstants.UserDefaults.widgetHTTPEnabled)
    private var widgetHTTPEnabled = false

    @AppStorage(AppConstants.UserDefaults.widgetPort)
    private var storedWidgetPort: Int = Int(AppConstants.WebSocketServer.widgetDefaultPort)

    private var overlayURL: String {
        "http://localhost:\(String(storedWidgetPort))/"
    }

    /// Combined state — the step treats the two servers as one user-facing feature.
    private var overlayEnabled: Bool {
        websocketEnabled && widgetHTTPEnabled
    }

    // MARK: - Body

    var body: some View {
        OnboardingStepScaffold(
            title: "Your overlay, ready to drop in",
            description: "One toggle. We'll give you the URL to paste into OBS.",
            icon: {
                BrandTile(
                    background: AnyShapeStyle(
                        LinearGradient(
                            colors: [AppConstants.Brand.obsGradientStart, AppConstants.Brand.obsGradientEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    ),
                    glowColor: Color.black,
                    glyph:
                        Image("OBSLogo")
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 30, height: 30)
                            .foregroundStyle(.white)
                )
            },
            extras: {
                VStack(spacing: DSSpace.s4) {
                    overlayToggleCard
                    urlReveal
                }
                .animation(.easeInOut(duration: DSMotion.Duration.base), value: overlayEnabled)
            }
        )
    }

    // MARK: - Toggle Card

    private var overlayToggleCard: some View {
        ToggleSettingRow(
            title: "Turn on Stream Widgets",
            subtitle: "Streams your now-playing card to OBS.",
            isOn: Binding(
                get: { overlayEnabled },
                set: { setOverlayEnabled($0) }
            ),
            controlSize: .regular,
            accessibilityLabel: "Turn on Stream Widgets",
            accessibilityIdentifier: "onboardingOverlayToggle"
        )
        .padding(DSSpace.s5)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(overlayEnabled
                      ? Color.accentColor.opacity(0.08)
                      : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    overlayEnabled
                        ? Color.accentColor.opacity(0.40)
                        : Color.primary.opacity(0.06),
                    lineWidth: 0.5
                )
        )
        .shadow(
            color: overlayEnabled ? Color.accentColor.opacity(0.16) : .clear,
            radius: 16, x: 0, y: 4
        )
        .animation(.easeInOut(duration: DSMotion.Duration.base), value: overlayEnabled)
    }

    // MARK: - URL Reveal

    @ViewBuilder
    private var urlReveal: some View {
        if overlayEnabled {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: DSSpace.s2) {
                    Text("BROWSER SOURCE URL")
                        .font(.system(size: DSFont.Size.xs, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.6)
                    if streamerMode { StreamerModeBadge() }
                }

                HStack(spacing: 8) {
                    Text(verbatim: StreamerMode.mask(overlayURL, style: .url, isOn: streamerMode))
                        .font(.system(size: DSFont.Size.md, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    CopyButton(
                        text: overlayURL,
                        isDisabled: streamerMode,
                        accessibilityLabel: "Copy overlay URL"
                    )
                }
                .padding(.horizontal, DSSpace.s4)
                .padding(.vertical, DSSpace.s3)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )

                Text("Paste this into OBS as a Browser Source.")
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Need the live now-playing feed? Settings → Stream Widgets.")
                    .font(.system(size: DSFont.Size.xs))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DSSpace.s4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Private Helpers

    /// Flip both servers as one. Notifications fire in the same order
    /// `AppDelegate` listens for them.
    private func setOverlayEnabled(_ enabled: Bool) {
        websocketEnabled = enabled
        widgetHTTPEnabled = enabled

        NotificationCenter.default.postWebSocketServerChanged()
        NotificationCenter.default.post(name: .widgetHTTPServerChanged, object: nil)
    }
}

// MARK: - Preview

#Preview {
    OnboardingOBSWidgetStepView(websocketEnabled: .constant(true))
        .frame(width: 600, height: 480)
}
