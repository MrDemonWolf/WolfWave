//
//  OnboardingAppleMusicStepView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 4/8/26.
//

import MusicKit
import SwiftUI

/// Optional onboarding step to grant Apple Music access for song requests.
struct OnboardingAppleMusicStepView: View {

    // MARK: - Properties

    @State private var authStatus: MusicAuthorization.Status = MusicAuthorization.currentStatus
    @State private var isRequesting = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "music.note")
                    .font(.system(size: 36))
                    .foregroundStyle(.pink)
                    .accessibilityHidden(true)

                Text("Apple Music Access")
                    .font(.system(size: 20, weight: .bold))

                Text("Needed for song requests. You can always do this later.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 16) {
                Text("WolfWave needs Apple Music access so your Twitch viewers can request songs via chat.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if authStatus == .authorized {
                    SuccessFeedbackRow(text: "Apple Music access granted!")
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .accessibilityLabel("Apple Music access has been granted")
                } else if authStatus == .denied {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Access was denied. You can enable it in System Settings → Privacy & Security → Media & Apple Music.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                } else {
                    Button {
                        isRequesting = true
                        Task {
                            _ = await MusicAuthorization.request()
                            authStatus = MusicAuthorization.currentStatus
                            isRequesting = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isRequesting {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text("Grant Apple Music Access")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .tint(.pink)
                    .disabled(isRequesting)
                    .accessibilityLabel("Grant Apple Music access")
                    .accessibilityIdentifier("onboardingAppleMusicGrant")
                }
            }
            .frame(maxWidth: 400)
            .padding(.horizontal, 24)
            .animation(.easeInOut(duration: 0.2), value: authStatus)

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingAppleMusicStepView()
        .frame(width: 520, height: 400)
}
