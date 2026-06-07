//
//  OnboardingPermissionsStepView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-30.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Apple Music permission step. Asks for the one system grant WolfWave needs to
/// work: **Apple Music** automation (the TCC bucket `MusicPlaybackMonitor` reads
/// the current track from). We never read the catalog or library. Notification
/// alerts live on their own step right after this one.
struct OnboardingPermissionsStepView: View {

    // MARK: - Apple Music State

    @State private var permissionState: MusicPermissionState = MusicPermissionChecker.currentState()
    @State private var isRequesting = false
    @State private var isRechecking = false

    // MARK: - Body

    var body: some View {
        OnboardingStepScaffold(
            title: "Let WolfWave read your music",
            description: "WolfWave reads the current track from the Music app so it can share what you're playing. That's the only access it needs.",
            icon: {
                BrandTile(
                    background: AnyShapeStyle(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    ),
                    glowColor: Color.accentColor,
                    glyph:
                        Image(systemName: "lock.shield.fill")
                            .font(BrandTileGlyph.font)
                            .foregroundStyle(.white)
                )
            },
            extras: {
                appleMusicSection
                    .animation(.easeInOut(duration: DSMotion.Duration.base), value: permissionState)
            }
        )
    }

    // MARK: - Apple Music Section

    @ViewBuilder
    private var appleMusicSection: some View {
        VStack(alignment: .leading, spacing: DSSpace.s3) {
            Label("Apple Music access", systemImage: "music.note")
                .sectionEyebrow()

            switch permissionState {
            case .granted:
                HStack(spacing: DSSpace.s3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: DSFont.Size.lg))
                        .foregroundStyle(.green)
                    Text("Access granted. Sync Music is on.")
                        .font(.system(size: DSFont.Size.base))
                        .foregroundStyle(.primary)
                }
                .padding(DSSpace.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

            case .denied:
                VStack(spacing: DSSpace.s3) {
                    HStack(alignment: .top, spacing: DSSpace.s2) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Access was denied. Enable in **System Settings → Privacy & Security → Automation → WolfWave → Music**.")
                            .font(.system(size: DSFont.Size.base))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(DSSpace.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                            .fill(DSColor.warning.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                            .stroke(DSColor.warning.opacity(0.40), lineWidth: 0.5)
                    )

                    HStack(spacing: DSSpace.s2) {
                        Button(action: recheckTapped) {
                            HStack(spacing: DSSpace.s1h) {
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
                VStack(spacing: DSSpace.s3) {
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
                        disabled: isRequesting,
                        action: requestAccess,
                        label: {
                            HStack(spacing: DSSpace.s2) {
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
    }

    // MARK: - Apple Music Actions

    /// Re-queries Apple Music automation permission with a brief spinner so
    /// the user gets visible feedback even when the state doesn't change.
    private func recheckTapped() {
        guard !isRechecking else { return }
        withAnimation(.easeInOut(duration: DSMotion.Duration.fast)) {
            isRechecking = true
        }
        Task {
            let next = await MusicPermissionChecker.recheck()
            await MainActor.run {
                withAnimation(.easeInOut(duration: DSMotion.Duration.base)) {
                    permissionState = next
                    isRechecking = false
                }
            }
        }
    }

    /// Prompts the user for Apple Music automation permission via
    /// `MusicPermissionChecker.requestAccess()` and refreshes the UI state.
    private func requestAccess() {
        isRequesting = true
        Task {
            let resolved = await MusicPermissionChecker.requestAccess()
            permissionState = resolved
            isRequesting = false
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingPermissionsStepView()
        .frame(width: 600, height: 520)
}
