//
//  OnboardingAppleMusicStepView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 4/8/26.
//

import AppKit
import SwiftUI

/// Apple Music access step. Requests Apple Events automation permission for
/// Music.app — the actual TCC bucket `MusicPlaybackMonitor` needs. We do not
/// request MusicKit catalog auth because we never read the catalog or library;
/// `AppleMusicSource` only asks the running Music app for the current track.
struct OnboardingAppleMusicStepView: View {

    // MARK: - Properties

    @State private var permissionState: MusicPermissionState = MusicPermissionChecker.currentState()
    @State private var isRequesting = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            BrandTile(
                background: AnyShapeStyle(
                    LinearGradient(
                        colors: [
                            AppConstants.Brand.appleMusicGradientStart,
                            AppConstants.Brand.appleMusicGradientEnd
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                ),
                glowColor: AppConstants.Brand.appleMusicGradientEnd,
                glyph:
                    Image("AppleMusicLogo")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .foregroundStyle(.white)
            )

            VStack(spacing: 6) {
                Text("Let WolfWave see what's playing")
                    .font(.system(size: 20, weight: .bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("WolfWave reads the current track from the Music app. We never play, pause, skip, or change your library.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
                .frame(maxWidth: 440)
                .padding(.horizontal, 24)
                .animation(.easeInOut(duration: 0.20), value: permissionState)

            Spacer(minLength: 0)
        }
    }

    // MARK: - State Content

    @ViewBuilder
    private var content: some View {
        switch permissionState {
        case .granted:
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.green)
                Text("Access granted. Sync Music is on.")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()

        case .denied:
            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Access was denied. Enable in **System Settings → Privacy & Security → Automation → WolfWave → Music**.")
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.orange.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.orange.opacity(0.40), lineWidth: 0.5)
                )

                HStack(spacing: 8) {
                    Button("Recheck") {
                        permissionState = MusicPermissionChecker.currentState()
                    }
                    .buttonStyle(.bordered)
                    .pointerCursor()

                    Button("Open System Settings") {
                        MusicPermissionChecker.openAutomationSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .pointerCursor()
                }
            }

        case .unknown:
            VStack(spacing: 10) {
                PillButton(
                    background: AnyShapeStyle(
                        LinearGradient(
                            colors: [
                                AppConstants.Brand.appleMusicGradientStart,
                                AppConstants.Brand.appleMusicGradientEnd
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    ),
                    glowColor: AppConstants.Brand.appleMusicGradientEnd,
                    disabled: isRequesting,
                    action: requestAccess,
                    label: {
                        HStack(spacing: 8) {
                            if isRequesting {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .controlSize(.small)
                                    .tint(.white)
                            }
                            Text("Allow Music access")
                        }
                    }
                )
                .accessibilityLabel("Allow Music access")
                .accessibilityIdentifier("onboardingAppleMusicGrant")

                Text("macOS will ask once. You can change this later in System Settings → Privacy → Automation.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Actions

    private func requestAccess() {
        isRequesting = true
        Task {
            let resolved = MusicPermissionChecker.requestAccess()
            permissionState = resolved
            isRequesting = false
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingAppleMusicStepView()
        .frame(width: 600, height: 480)
}
