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
    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - State

    @State private var updateAvailable = false
    @State private var latestVersion: String?

    @AppStorage(AppConstants.UserDefaults.updateSkippedVersion)
    private var skippedVersion: String = ""

    @AppStorage(AppConstants.UserDefaults.updateCheckEnabled)
    private var updateCheckEnabled = true

    @AppStorage(AppConstants.UserDefaults.updateChannel)
    private var storedChannel = UpdateChannel.stable.rawValue

    @State private var isCheckingForUpdates = false
    @State private var isManualCheck = false
    @State private var isHomebrewInstall = false
    @State private var showNightlyWarning = false

    private var appDelegate: AppDelegate? { AppDelegate.shared }

    private var currentVersion: String { AppConstants.AppInfo.shortVersion }

    /// The channel currently persisted, used to drive the picker and banner.
    private var selectedChannel: UpdateChannel { UpdateChannel.from(rawValue: storedChannel) }

    /// Picker binding that gates the switch to Nightly behind a warning alert.
    /// Switching to Stable is safe and commits immediately.
    private var channelBinding: Binding<UpdateChannel> {
        Binding(
            get: { UpdateChannel.from(rawValue: storedChannel) },
            set: { newValue in
                switch newValue {
                case .nightly:
                    // Don't commit yet. The alert's confirm button applies it,
                    // so Cancel leaves the picker reverted to its stored value.
                    if UpdateChannel.from(rawValue: storedChannel) != .nightly {
                        showNightlyWarning = true
                    }
                case .stable:
                    applyChannel(.stable)
                }
            }
        )
    }

    /// Persists the channel via the updater and silently re-checks the new feed.
    private func applyChannel(_ channel: UpdateChannel) {
        appDelegate?.sparkleUpdater?.channel = channel
        appDelegate?.sparkleUpdater?.recheckAfterChannelChange()
    }

    /// Header chip text derived from live update state.
    private var statusText: String {
        if isHomebrewInstall { return "Homebrew" }
        if isCheckingForUpdates { return "Checking…" }
        if updateAvailable, let latestVersion { return "v\(latestVersion) ready" }
        if latestVersion != nil { return "Up to date" }
        return updateCheckEnabled ? "Auto on" : "Auto off"
    }

    /// Header chip color matching `statusText`.
    private var statusColor: Color {
        if isHomebrewInstall { return .gray }
        if isCheckingForUpdates { return .orange }
        if updateAvailable { return .accentColor }
        if latestVersion != nil { return .green }
        return updateCheckEnabled ? .green : .gray
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            SectionHeaderWithStatus(
                title: "Software Update",
                subtitle: "Check for new versions and manage automatic updates.",
                statusText: statusText,
                statusColor: statusColor
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
            Text("Version \(currentVersion)")
                .font(.system(size: DSFont.Size.base, weight: .semibold))

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
            VStack(alignment: .leading, spacing: DSSpace.s1) {
                Text("Version \(currentVersion)")
                    .font(.system(size: DSFont.Size.base, weight: .semibold))

                if updateAvailable, let version = latestVersion {
                    Text("Version \(version) is ready to install.")
                        .font(.system(size: DSFont.Size.body))
                        .foregroundStyle(.secondary)
                }
            }

            if selectedChannel == .nightly {
                CalloutBanner(
                    "You're on Nightly. These are dev builds off main and can be unstable. Switch back to Stable below, then reinstall the latest Stable build.",
                    title: "Nightly channel",
                    style: .warning,
                    systemImage: "flask.fill"
                )
                .transition(.opacity)
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

            VStack(alignment: .leading, spacing: DSSpace.s2) {
                Text("Update Channel")
                    .font(.system(size: DSFont.Size.body, weight: .medium))

                Picker("Update Channel", selection: channelBinding) {
                    Text("Stable").tag(UpdateChannel.stable)
                    Text("Nightly (dev)").tag(UpdateChannel.nightly)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Update channel")
                .accessibilityHint("Stable ships releases. Nightly is opt-in dev builds off main.")
                .accessibilityValue(selectedChannel.title)
                #if DEBUG
                .disabled(true)
                .opacity(0.5)
                #endif

                Text(selectedChannel == .nightly
                    ? "Dev builds straight off main. Newer, but can be unstable."
                    : "Shipped releases. Recommended for most people.")
                    .font(.system(size: DSFont.Size.body))
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Toggle("Check automatically", isOn: Binding(
                    get: { appDelegate?.sparkleUpdater?.automaticCheckEnabled ?? true },
                    set: { newValue in
                        appDelegate?.sparkleUpdater?.automaticCheckEnabled = newValue
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
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
        .animation(reduceMotion ? nil : .easeInOut(duration: DSMotion.Duration.base), value: updateAvailable)
        .animation(reduceMotion ? nil : .easeInOut(duration: DSMotion.Duration.base), value: updateCheckEnabled)
        .animation(reduceMotion ? nil : .easeInOut(duration: DSMotion.Duration.base), value: selectedChannel)
        .alert("Switch to Nightly builds?", isPresented: $showNightlyWarning) {
            Button("Switch to Nightly", role: .destructive) {
                applyChannel(.nightly)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Nightly builds come straight off main. They're newer but can be buggy, get no support, and update often.\n\nTo go back to Stable later, pick Stable here, then reinstall the latest Stable build.")
        }
    }
}

// MARK: - Preview

#Preview("Default") {
    SoftwareUpdateSettingsView()
        .padding()
        .frame(width: 700)
}
