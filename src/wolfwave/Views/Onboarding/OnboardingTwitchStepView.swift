//
//  OnboardingTwitchStepView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 2/6/26.
//

import SwiftUI

/// Twitch connection step of the onboarding wizard.
///
/// Reuses the existing `TwitchViewModel` and `DeviceCodeView` for the
/// OAuth Device Code flow. Provides a simplified interface with:
/// - Explanation of what connecting Twitch enables
/// - "Connect with Twitch" button to start OAuth
/// - Device code display (reuses `DeviceCodeView`)
/// - Success confirmation when auth completes
///
/// This step is optional — users can skip it from the navigation bar.
struct OnboardingTwitchStepView: View {

    // MARK: - Properties

    /// Shared Twitch view model managing auth state and credentials.
    @ObservedObject var twitchViewModel: TwitchViewModel

    /// Whether the user has clicked the activation link or copied the code.
    @State private var hasStartedActivation = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Header
            VStack(spacing: 8) {
                Image("TwitchLogo")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)

                Text("Connect to Twitch")
                    .font(.system(size: 20, weight: .bold))

                Text("Optional — you can set this up later in Settings.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            // Content switches based on auth state
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
            .frame(maxWidth: 400)
            .padding(.horizontal, 24)

            Spacer()
        }
        .onAppear {
            twitchViewModel.loadSavedCredentials()

            if twitchViewModel.twitchService == nil {
                if let appDelegate = AppDelegate.shared {
                    twitchViewModel.twitchService = appDelegate.twitchService
                }
            }
        }
    }

    // MARK: - Not Connected

    private var notConnectedContent: some View {
        VStack(spacing: 16) {
            Text("Link your Twitch account to let viewers see what music you're playing via chat commands.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: {
                hasStartedActivation = false
                twitchViewModel.startOAuth()
            }) {
                HStack(spacing: 8) {
                    Image("TwitchLogo")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                    Text("Connect with Twitch")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .pointerCursor()
            .accessibilityLabel("Connect with Twitch authorization")
        }
    }

    // MARK: - Authorizing

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

            if hasStartedActivation {
                HStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)

                    Text("Waiting for authorization\u{2026}")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Cancel") {
                        hasStartedActivation = false
                        twitchViewModel.cancelOAuth()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                    .pointerCursor()
                }
            } else {
                HStack {
                    Spacer()

                    Button("Cancel") {
                        twitchViewModel.cancelOAuth()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                    .pointerCursor()
                }
            }
        }
    }

    // MARK: - Connected

    private var connectedContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)

            Text("Connected as \(twitchViewModel.botUsername)")
                .font(.system(size: 15, weight: .semibold))

            Text("You're all set! Click Finish to start using WolfWave.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Error

    @ViewBuilder
    private func errorContent(message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                twitchViewModel.startOAuth()
            }
            .buttonStyle(.bordered)
            .pointerCursor()
        }
    }
}
