//
//  OnboardingOBSWidgetStepView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/13/26.
//

import SwiftUI

/// OBS overlay step. One toggle drives both the WebSocket feed and the widget
/// HTTP server so streamers see a single, useful Browser Source URL instead of
/// chaining two switches. Advanced users can split them later in Settings.
struct OnboardingOBSWidgetStepView: View {

    // MARK: - Properties

    @Binding var websocketEnabled: Bool

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
        VStack(spacing: 16) {
            Spacer(minLength: 0)

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

            VStack(spacing: 6) {
                Text("Your overlay, ready to drop in")
                    .font(.system(size: 20, weight: .bold))

                Text("One toggle. We'll give you the URL to paste into OBS.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                    .fixedSize(horizontal: false, vertical: true)
            }

            overlayToggleCard
                .frame(maxWidth: 440)
                .padding(.horizontal, 24)

            urlReveal
                .frame(maxWidth: 440)
                .padding(.horizontal, 24)

            Spacer(minLength: 0)
        }
        .animation(.easeInOut(duration: 0.20), value: overlayEnabled)
    }

    // MARK: - Toggle Card

    private var overlayToggleCard: some View {
        ToggleSettingRow(
            title: "Enable OBS overlay",
            subtitle: "Streams your now-playing card to OBS.",
            isOn: Binding(
                get: { overlayEnabled },
                set: { setOverlayEnabled($0) }
            ),
            controlSize: .regular,
            accessibilityLabel: "Enable OBS overlay",
            accessibilityIdentifier: "onboardingOverlayToggle"
        )
        .padding(14)
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
        .animation(.easeInOut(duration: 0.20), value: overlayEnabled)
    }

    // MARK: - URL Reveal

    @ViewBuilder
    private var urlReveal: some View {
        if overlayEnabled {
            VStack(alignment: .leading, spacing: 10) {
                Text("BROWSER SOURCE URL")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.6)

                HStack(spacing: 8) {
                    Text(verbatim: overlayURL)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    CopyButton(
                        text: overlayURL,
                        accessibilityLabel: "Copy overlay URL"
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )

                Text("Paste this into OBS as a Browser Source.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Need the raw WebSocket feed? Settings → Overlay.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
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

        NotificationCenter.default.post(
            name: NSNotification.Name(AppConstants.Notifications.websocketServerChanged),
            object: nil,
            userInfo: nil
        )
        NotificationCenter.default.post(
            name: NSNotification.Name(AppConstants.Notifications.widgetHTTPServerChanged),
            object: nil,
            userInfo: nil
        )
    }
}

// MARK: - Preview

#Preview {
    OnboardingOBSWidgetStepView(websocketEnabled: .constant(true))
        .frame(width: 600, height: 480)
}
