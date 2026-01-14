//
//  TwitchReauthView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/13/26.
//

import SwiftUI

/// View for re-authenticating with Twitch when the session has expired.
///
/// Displays a session expired banner and OAuth Device Code flow UI for user re-authentication.
struct TwitchReauthView: View {
    @ObservedObject var viewModel: TwitchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Session Expired Banner
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundColor(.orange)
                Text("Session Expired")
                    .font(.body)
                    .fontWeight(.medium)
            }

            Text("Your Twitch session has expired. Please sign in again to continue using Twitch Integration.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Sign In Button
            Button(action: { viewModel.startOAuth() }) {
                Label {
                    Text("Sign in with Twitch")
                        .fontWeight(.semibold)
                } icon: {
                    Image("TwitchLogo")
                        .renderingMode(.original)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            // Device Code Flow (shown after user clicks Sign In)
            if !viewModel.authState.userCode.isEmpty {
                DeviceCodeView(
                    userCode: viewModel.authState.userCode,
                    verificationURI: viewModel.authState.verificationURI,
                    onCopy: { viewModel.statusMessage = "Code copied to clipboard!" }
                )
            }

            // Progress Indicator
            if viewModel.authState.isInProgress {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Color(nsColor: .controlAccentColor))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(8)
    }
}

#Preview {
    TwitchReauthView(viewModel: TwitchViewModel())}