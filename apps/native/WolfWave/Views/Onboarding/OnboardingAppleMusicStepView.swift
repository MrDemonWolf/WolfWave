//
//  OnboardingAppleMusicStepView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Apple Music access step. Requests Apple Events automation permission for
/// Music.app — the actual TCC bucket `MusicPlaybackMonitor` needs. We do not
/// request MusicKit catalog auth because we never read the catalog or library;
/// `AppleMusicSource` only asks the running Music app for the current track.
struct OnboardingAppleMusicStepView: View {

    // MARK: - Properties

    @State private var permissionState: MusicPermissionState = MusicPermissionChecker.currentState()
    @State private var isRequesting = false
    @State private var isRechecking = false

    // MARK: - Body

    var body: some View {
        OnboardingStepScaffold(
            title: "Let WolfWave see what's playing",
            description: "WolfWave reads the current track from the Music app. We never play, pause, skip, or change your library.",
            icon: {
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
            },
            extras: {
                content
                    .animation(.easeInOut(duration: DSMotion.Duration.base), value: permissionState)
            }
        )
    }

    // MARK: - State Content

    @ViewBuilder
    private var content: some View {
        switch permissionState {
        case .granted:
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: DSFont.Size.x18))
                    .foregroundStyle(.green)
                Text("Access granted. Sync Music is on.")
                    .font(.system(size: DSFont.Size.base))
                    .foregroundStyle(.primary)
            }
            .padding(DSSpace.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()

        case .denied:
            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Access was denied. Enable in **System Settings → Privacy & Security → Automation → WolfWave → Music**.")
                        .font(.system(size: DSFont.Size.body))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DSSpace.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DSColor.warning.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DSColor.warning.opacity(0.40), lineWidth: 0.5)
                )

                HStack(spacing: 8) {
                    Button(action: recheckTapped) {
                        HStack(spacing: 6) {
                            if isRechecking {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .controlSize(.small)
                            }
                            Text("Recheck")
                        }
                    }
                    .buttonStyle(.bordered)
                    .pointerCursor()
                    .disabled(isRechecking)
                    .accessibilityLabel("Recheck Apple Music access")
                    .accessibilityHint("Re-queries macOS for the current automation permission state")
                    .accessibilityIdentifier("onboardingAppleMusic.recheckButton")

                    Button("Open System Settings") {
                        MusicPermissionChecker.openAutomationSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .pointerCursor()
                    .accessibilityLabel("Open System Settings")
                    .accessibilityHint("Opens Privacy and Security to grant Apple Music access")
                    .accessibilityIdentifier("onboardingAppleMusic.openSystemSettingsButton")
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
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Actions

    /// Re-queries Apple Music automation permission with a brief spinner so
    /// the user gets visible feedback even when the state doesn't change.
    private func recheckTapped() {
        guard !isRechecking else { return }
        withAnimation(.easeInOut(duration: DSMotion.Duration.fast)) {
            isRechecking = true
        }
        Task {
            let start = Date()
            let next = MusicPermissionChecker.currentState()
            let elapsed = Date().timeIntervalSince(start)
            let minSpin: TimeInterval = 0.25
            if elapsed < minSpin {
                try? await Task.sleep(nanoseconds: UInt64((minSpin - elapsed) * 1_000_000_000))
            }
            await MainActor.run {
                withAnimation(.easeInOut(duration: DSMotion.Duration.base)) {
                    permissionState = next
                    isRechecking = false
                }
            }
        }
    }

    /// Prompts the user for Apple Music automation permission via
    /// `MusicPermissionChecker.requestAccess()` and refreshes the UI state
    /// after the prompt completes.
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
