//
//  OnboardingOBSWidgetStepView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/13/26.
//

import SwiftUI

/// OBS overlay step. Brand tile + smart toggle card + URL reveal panel that slides
/// into view when the WebSocket server is enabled.
struct OnboardingOBSWidgetStepView: View {

    // MARK: - Properties

    @Binding var websocketEnabled: Bool

    @AppStorage(AppConstants.UserDefaults.widgetHTTPEnabled)
    private var widgetHTTPEnabled = false

    @AppStorage(AppConstants.UserDefaults.websocketServerPort)
    private var storedPort: Int = Int(AppConstants.WebSocketServer.defaultPort)

    @AppStorage(AppConstants.UserDefaults.widgetPort)
    private var storedWidgetPort: Int = Int(AppConstants.WebSocketServer.widgetDefaultPort)

    private var overlayURL: String {
        "http://localhost:\(String(storedWidgetPort))/"
    }

    private var websocketURL: String {
        "ws://localhost:\(String(storedPort))"
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

                Text("Enable the servers below, then drop the overlay URL into OBS as a Browser Source.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                ToggleSettingRow(
                    title: "Enable WebSocket server",
                    subtitle: "Streams now-playing data to widgets and custom overlays.",
                    isOn: $websocketEnabled,
                    controlSize: .regular,
                    accessibilityLabel: "Enable WebSocket server",
                    accessibilityIdentifier: "onboardingWebsocketToggle",
                    onChange: { _ in
                        NotificationCenter.default.post(
                            name: NSNotification.Name(AppConstants.Notifications.websocketServerChanged),
                            object: nil,
                            userInfo: nil
                        )
                    }
                )
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(websocketEnabled
                              ? Color.accentColor.opacity(0.08)
                              : Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            websocketEnabled
                                ? Color.accentColor.opacity(0.40)
                                : Color.primary.opacity(0.06),
                            lineWidth: 0.5
                        )
                )
                .shadow(
                    color: websocketEnabled ? Color.accentColor.opacity(0.16) : .clear,
                    radius: 16, x: 0, y: 4
                )
                .animation(.easeInOut(duration: 0.20), value: websocketEnabled)

                ToggleSettingRow(
                    title: "Enable overlay widget",
                    subtitle: "Serve the browser-source page over HTTP.",
                    isOn: $widgetHTTPEnabled,
                    controlSize: .regular,
                    accessibilityLabel: "Enable overlay widget",
                    accessibilityIdentifier: "onboardingWidgetHTTPToggle",
                    onChange: { _ in
                        NotificationCenter.default.post(
                            name: NSNotification.Name(AppConstants.Notifications.widgetHTTPServerChanged),
                            object: nil,
                            userInfo: nil
                        )
                    }
                )
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(widgetHTTPEnabled
                              ? Color.accentColor.opacity(0.08)
                              : Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            widgetHTTPEnabled
                                ? Color.accentColor.opacity(0.40)
                                : Color.primary.opacity(0.06),
                            lineWidth: 0.5
                        )
                )
                .shadow(
                    color: widgetHTTPEnabled ? Color.accentColor.opacity(0.16) : .clear,
                    radius: 16, x: 0, y: 4
                )
                .opacity(websocketEnabled ? 1.0 : 0.45)
                .disabled(!websocketEnabled)
                .animation(.easeInOut(duration: 0.20), value: widgetHTTPEnabled)
                .animation(.easeInOut(duration: 0.20), value: websocketEnabled)
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, 24)

            urlReveal
                .frame(maxWidth: 440)
                .padding(.horizontal, 24)

            Spacer(minLength: 0)
        }
        .animation(.easeInOut(duration: 0.20), value: websocketEnabled)
    }

    // MARK: - URL Reveal

    @ViewBuilder
    private var urlReveal: some View {
        if websocketEnabled {
            VStack(alignment: .leading, spacing: 8) {
                Text("OVERLAY URL")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.6)

                HStack(spacing: 8) {
                    Text(verbatim: overlayURL)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    CopyButton(
                        text: overlayURL,
                        accessibilityLabel: "Copy overlay URL"
                    )
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )

                HStack(spacing: 6) {
                    Text("WEBSOCKET")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.quaternary)
                        .tracking(0.5)
                    Text(verbatim: websocketURL)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                widgetPreview
                    .padding(.top, 2)

                Text("Add the Overlay URL as an OBS Browser Source. We'll show the rest in Settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
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

    // MARK: - Widget Preview

    /// Decorative SwiftUI mock of the now-playing chip OBS will receive. Shape
    /// only — sample data, no live binding. `accessibilityHidden` because the
    /// surrounding copy already explains what this is.
    private var widgetPreview: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                )
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("Midnight City")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("M83")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.55))
        )
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

#Preview {
    OnboardingOBSWidgetStepView(websocketEnabled: .constant(true))
        .frame(width: 600, height: 480)
}
