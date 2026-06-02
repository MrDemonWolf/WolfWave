//
//  OnboardingTwitchStepView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-02-06.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Twitch connection step with branded tile, pill CTA, and reused `DeviceCodeView`
/// for the OAuth Device Code flow. Optional — can be skipped from the nav bar.
struct OnboardingTwitchStepView: View {

    // MARK: - Properties

    @Bindable var twitchViewModel: TwitchViewModel

    @State private var hasStartedActivation = false

    // MARK: - Body

    var body: some View {
        OnboardingStepScaffold(
            title: "Connect WolfWave to Twitch",
            description: "So !song works in your chat automatically. We only listen, we never post unless you ask.",
            icon: {
                BrandTile(
                    background: AnyShapeStyle(AppConstants.Brand.twitch),
                    glowColor: AppConstants.Brand.twitch,
                    glyph:
                        Image("TwitchLogo")
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 28, height: 28)
                            .foregroundStyle(.white)
                )
            },
            extras: {
                Group {
                    switch twitchViewModel.integrationState {
                    case .notConnected:
                        notConnectedContent
                    case .authorizing:
                        authorizingContent
                    case .connected:
                        connectedContent
                    case .error(let message):
                        errorContent(message: message)
                    }
                }
                .animation(.easeInOut(duration: DSMotion.Duration.base), value: stateKey)
            }
        )
        .onAppear {
            twitchViewModel.loadSavedCredentials()
            if twitchViewModel.twitchService == nil {
                if let appDelegate = AppDelegate.shared {
                    twitchViewModel.twitchService = appDelegate.twitchService
                }
            }
        }
    }

    // MARK: - States

    private var notConnectedContent: some View {
        VStack(spacing: 10) {
            PillButton(
                background: AnyShapeStyle(AppConstants.Brand.twitch),
                action: {
                    hasStartedActivation = false
                    twitchViewModel.startOAuth()
                },
                label: {
                    HStack(spacing: 8) {
                        Image("TwitchLogo")
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                            .foregroundStyle(.white)
                        Text("Connect with Twitch")
                    }
                }
            )
            .accessibilityLabel("Connect with Twitch")
            .accessibilityHint("Opens Twitch in your browser to authorize WolfWave")

            Text("Opens twitch.tv/activate in your browser. Takes about 10 seconds.")
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.tertiary)
        }
    }

    private var authorizingContent: some View {
        VStack(spacing: 12) {
            if case .waitingForAuth(let code, let uri) = twitchViewModel.authState {
                DeviceCodeView(
                    userCode: code,
                    verificationURI: uri,
                    onCopy: {
                        twitchViewModel.statusMessage = "Code copied"
                        hasStartedActivation = true
                    },
                    onActivate: {
                        hasStartedActivation = true
                    }
                )
            }

            HStack(spacing: 12) {
                LoadingRow(text: "Waiting for Twitch\u{2026}")

                Spacer()

                Button("Cancel") {
                    hasStartedActivation = false
                    twitchViewModel.cancelOAuth()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .pointerCursor()
                .accessibilityLabel("Cancel authorization")
            }
        }
    }

    private var connectedContent: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(DSColor.success)
                    .frame(width: 36, height: 36)
                    .shadow(color: DSColor.success.opacity(0.40), radius: 8, x: 0, y: 4)

                Image(systemName: "checkmark")
                    .font(.system(size: DSFont.Size.x16, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Connected")
                    .sectionEyebrow()

                Text("@\(twitchViewModel.botUsername)")
                    .font(.system(size: DSFont.Size.x15, weight: .semibold))
            }

            Spacer()

            Button("Sign Out") {
                twitchViewModel.cancelOAuth()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .pointerCursor()
        }
        .padding(DSSpace.s5)
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Twitch connected as \(twitchViewModel.botUsername).")
    }

    /// Error-state subview shown when the Twitch device-code flow fails.
    /// Displays a warning icon plus a wrap-friendly explanation message.
    ///
    /// - Parameter message: Localized error string from the auth flow.
    @ViewBuilder
    private func errorContent(message: String) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: DSFont.Size.base))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DSSpace.s4)
            .cardStyle()

            Button("Try Again") {
                twitchViewModel.startOAuth()
            }
            .buttonStyle(.bordered)
            .pointerCursor()
        }
    }

    // MARK: - Helpers

    private var stateKey: Int {
        switch twitchViewModel.integrationState {
        case .notConnected: return 0
        case .authorizing: return 1
        case .connected: return 2
        case .error: return 3
        }
    }
}

// MARK: - Previews

#Preview("Not connected") {
    OnboardingTwitchStepView(twitchViewModel: TwitchViewModel())
        .frame(
            width: AppConstants.OnboardingUI.windowWidth,
            height: AppConstants.OnboardingUI.windowHeight
        )
}
