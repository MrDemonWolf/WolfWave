//
//  OnboardingOBSWidgetStepView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/13/26.
//

import SwiftUI

/// Optional onboarding step to enable the OBS stream overlay WebSocket server.
struct OnboardingOBSWidgetStepView: View {

    // MARK: - Properties

    @Binding var websocketEnabled: Bool

    @AppStorage(AppConstants.UserDefaults.websocketServerPort)
    private var storedPort: Int = Int(AppConstants.WebSocketServer.defaultPort)

    @State private var copiedURL = false

    @AppStorage(AppConstants.UserDefaults.widgetPort)
    private var storedWidgetPort: Int = Int(AppConstants.WebSocketServer.widgetDefaultPort)

    private var widgetURL: String {
        let widgetPort = storedWidgetPort > 0 ? storedWidgetPort : Int(AppConstants.WebSocketServer.widgetDefaultPort)
        return "http://localhost:\(widgetPort)/?port=\(storedPort)"
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 8) {
                Image("OBSLogo")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)

                Text("Now-Playing Widget")
                    .font(.system(size: 20, weight: .bold))

                Text("Totally optional. You can always do this later.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 16) {
                Text("Display a now-playing widget in OBS or any browser.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable now-playing widget")
                            .font(.system(size: 13, weight: .medium))
                        Text("Runs a small local server so your widget stays up to date")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Toggle("", isOn: $websocketEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.regular)
                        .pointerCursor()
                        .accessibilityLabel("Enable now-playing widget server")
                        .accessibilityIdentifier("onboardingWebsocketToggle")
                        .onChange(of: websocketEnabled) { _, newValue in
                            NotificationCenter.default.post(
                                name: NSNotification.Name(AppConstants.Notifications.websocketServerChanged),
                                object: nil,
                                userInfo: nil
                            )
                        }
                }
                .padding(14)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if websocketEnabled {
                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.green)
                            Text("Overlay enabled!")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            Text(widgetURL)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(widgetURL, forType: .string)
                                copiedURL = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copiedURL = false
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: copiedURL ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 11))
                                    Text(copiedURL ? "Copied" : "Copy")
                                        .font(.system(size: 11))
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityLabel("Copy widget URL")
                        }
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        Text("Add as a Browser Source in OBS")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Text("Customize colors and layout in Settings → Now-Playing Widget")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: 400)
            .padding(.horizontal, 24)
            .animation(.easeInOut(duration: 0.2), value: websocketEnabled)

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingOBSWidgetStepView(websocketEnabled: .constant(false))
        .frame(width: 520, height: 500)
}
