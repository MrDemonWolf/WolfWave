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

    @AppStorage(AppConstants.UserDefaults.websocketServerPort)
    private var storedPort: Int = Int(AppConstants.WebSocketServer.defaultPort)

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

                Text("We'll start a local widget server. Add the link as an OBS browser source.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ToggleSettingRow(
                title: "Enable now-playing widget",
                subtitle: "Starts an HTTP & WebSocket server on your Mac.",
                isOn: $websocketEnabled,
                controlSize: .regular,
                accessibilityLabel: "Enable now-playing widget",
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
            .frame(maxWidth: 440)
            .padding(.horizontal, 24)
            .animation(.easeInOut(duration: 0.20), value: websocketEnabled)

            urlReveal
                .frame(maxWidth: 440)
                .padding(.horizontal, 24)

            Spacer(minLength: 0)
        }
    }

    // MARK: - URL Reveal

    @ViewBuilder
    private var urlReveal: some View {
        if websocketEnabled {
            VStack(alignment: .leading, spacing: 8) {
                Text("WEBSOCKET URL")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.6)

                HStack(spacing: 8) {
                    Text("ws://localhost:\(storedPort)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    CopyButton(
                        text: "ws://localhost:\(storedPort)",
                        accessibilityLabel: "Copy WebSocket URL"
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

                Text("Add as a Browser Source. We'll show the rest in Settings.")
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
}

// MARK: - Preview

#Preview {
    OnboardingOBSWidgetStepView(websocketEnabled: .constant(true))
        .frame(width: 600, height: 480)
}
