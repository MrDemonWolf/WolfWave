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

                ToggleSettingRow(
                    title: "Enable now-playing widget",
                    subtitle: "Powers the live-updating widget",
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
                .cardStyle()

                if websocketEnabled {
                    VStack(spacing: 10) {
                        SuccessFeedbackRow(text: "You're all set!", fontWeight: .medium)

                        Text("Configure the widget in Settings → Now-Playing Widget")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
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
