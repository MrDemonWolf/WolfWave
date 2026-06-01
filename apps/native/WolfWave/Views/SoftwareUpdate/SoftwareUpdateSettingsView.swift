//
//  SoftwareUpdateSettingsView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-28.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit
import SwiftUI

/// Software Update settings pane.
///
/// Shows the current version, update availability, and lets users toggle
/// automatic checks or trigger a manual check. Routes to the Homebrew-flavored
/// card for Homebrew installs (Sparkle disabled) and to the Sparkle-flavored
/// card for DMG installs.
struct SoftwareUpdateSettingsView: View {
    // MARK: - State

    @State private var updateAvailable = false
    @State private var latestVersion: String?

    @AppStorage(AppConstants.UserDefaults.updateSkippedVersion)
    private var skippedVersion: String = ""

    @AppStorage(AppConstants.UserDefaults.updateCheckEnabled)
    private var updateCheckEnabled = true

    @State private var isCheckingForUpdates = false
    @State private var isManualCheck = false
    @State private var isHomebrewInstall = false

    private var appDelegate: AppDelegate? { AppDelegate.shared }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            SectionHeaderWithStatus(
                title: "Software Update",
                subtitle: "Check for new versions and manage automatic updates."
            )

            softwareUpdateCard
        }
        .onAppear {
            isHomebrewInstall = Bundle.main.isHomebrewInstall
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.updateStateChanged)) { notification in
            isCheckingForUpdates = false
            if let update = notification.updateState {
                latestVersion = update.latestVersion
                updateAvailable = update.isUpdateAvailable && skippedVersion != update.latestVersion
                isManualCheck = false
            }
        }
    }

    // MARK: - Software Update Card

    @ViewBuilder
    private var softwareUpdateCard: some View {
        if isHomebrewInstall {
            homebrewUpdateCard
        } else {
            sparkleUpdateCard
        }
    }

    @ViewBuilder
    private var homebrewUpdateCard: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            VStack(alignment: .leading, spacing: DSSpace.s1) {
                Text("Software Update")
                    .font(.system(size: DSFont.Size.base, weight: .semibold))

                Text("Current version: \(currentVersion)")
                    .font(.system(size: DSFont.Size.body))
                    .foregroundStyle(.secondary)
            }

            CalloutBanner(
                "Use Homebrew to check for and install updates.",
                title: "Homebrew installation detected",
                style: .info
            )

            HStack(spacing: DSSpace.s2) {
                Text("$ brew upgrade wolfwave")
                    .font(.system(size: DSFont.Size.body, design: .monospaced))
                    .foregroundStyle(.primary)

                Spacer()

                CopyButton(
                    text: "brew upgrade wolfwave",
                    buttonStyle: .borderless,
                    accessibilityLabel: "Copy brew command"
                )
            }
            .padding(.horizontal, DSSpace.s3)
            .padding(.vertical, DSSpace.s2)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.sm))
        }
        .cardStyle()
    }

    @ViewBuilder
    private var sparkleUpdateCard: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            HStack {
                VStack(alignment: .leading, spacing: DSSpace.s1) {
                    Text("Software Update")
                        .font(.system(size: DSFont.Size.base, weight: .semibold))

                    Text("Current version: \(currentVersion)")
                        .font(.system(size: DSFont.Size.body))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if updateAvailable, let version = latestVersion {
                    Text("v\(version) available")
                        .font(.system(size: DSFont.Size.sm, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, DSSpace.s2)
                        .padding(.vertical, DSSpace.s1)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                        .transition(.opacity)
                        .accessibilityLabel("Version \(version) available for update")
                }
            }

            #if DEBUG
            CalloutBanner(
                "Development build. Update checks use dev-appcast.xml",
                style: .warning,
                systemImage: "hammer.fill"
            )
            #endif

            if updateCheckEnabled && !updateAvailable {
                CalloutBanner(
                    "Auto-updates on. We'll notify you of new versions.",
                    style: .success
                )
                .transition(.opacity)
            } else if !updateCheckEnabled && !updateAvailable {
                CalloutBanner(
                    "Automatic updates are off. Use Check Now to look for updates.",
                    style: .neutral
                )
                .transition(.opacity)
            }

            Divider()

            HStack {
                Toggle("Check automatically", isOn: Binding(
                    get: { appDelegate?.sparkleUpdater?.automaticCheckEnabled ?? true },
                    set: { newValue in
                        appDelegate?.sparkleUpdater?.automaticCheckEnabled = newValue
                    }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: DSFont.Size.body))
                .accessibilityLabel("Check for updates automatically")
                .accessibilityHint("Enables periodic background checks for new versions")
                .accessibilityValue(updateCheckEnabled ? "Enabled" : "Disabled")
                #if DEBUG
                .disabled(true)
                .opacity(0.5)
                #endif

                Spacer()

                Button {
                    isCheckingForUpdates = true
                    isManualCheck = true
                    appDelegate?.sparkleUpdater?.checkForUpdates()
                    // The `updateStateChanged` notification observer resets
                    // `isCheckingForUpdates` when Sparkle's delegate reports
                    // a result, so no fixed timer is needed.
                } label: {
                    if isCheckingForUpdates {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                    } else {
                        Text("Check Now")
                            .font(.system(size: DSFont.Size.body, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isCheckingForUpdates)
                .pointerCursor()
                .accessibilityLabel("Check for updates now")
                .accessibilityHint("Manually checks for a newer version of WolfWave")
                .accessibilityValue(isCheckingForUpdates ? "Checking" : "Idle")
                #if DEBUG
                .disabled(true)
                .opacity(0.5)
                #endif
            }
        }
        .cardStyle()
        .animation(.easeInOut(duration: DSMotion.Duration.base), value: updateAvailable)
        .animation(.easeInOut(duration: DSMotion.Duration.base), value: updateCheckEnabled)
    }
}

// MARK: - Preview

#Preview("Default") {
    SoftwareUpdateSettingsView()
        .padding()
        .frame(width: 700)
}
