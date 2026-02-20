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

    private var widgetURL: String {
        #if DEBUG
        "http://localhost:3000/widget/?port=\(storedPort)"
        #else
        "https://mrdemonwolf.github.io/wolfwave/widget/?port=\(storedPort)"
        #endif
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "rectangle.inset.filled.and.person.filled")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)

                Text("OBS Stream Widget")
                    .font(.system(size: 20, weight: .bold))

                Text("Optional — you can set this up later in Settings.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 16) {
                Text("Show what you're listening to on your stream with a browser source overlay in OBS.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable OBS Widget Server")
                            .font(.system(size: 13, weight: .medium))
                        Text("Starts a local server to send now-playing data")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Toggle("", isOn: $websocketEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.regular)
                        .pointerCursor()
                        .accessibilityLabel("Enable OBS Widget server")
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
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.green)
                            Text("Widget server enabled!")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Add this URL as a Browser Source in OBS:")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)

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
                        }
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
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
