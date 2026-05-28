//
//  AdvancedSettingsView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-01-13.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Advanced settings interface providing software update controls and dangerous operations.
///
/// Provides controls for:
/// - Checking for software updates (manual and automatic)
/// - Resetting the onboarding wizard so it shows again on next launch
/// - Resetting all application settings to defaults
/// - Clearing stored authentication tokens from Keychain
/// - Disconnecting from Twitch
///
/// State:
/// - Uses @Binding for showingResetAlert (passed from parent SettingsView)
/// - Shares context with AppDelegate via NSApplication.shared.delegate
///
/// Actions:
/// - Software Update card shows current version, update availability, and install instructions
/// - Reset Onboarding clears the onboarding flag so the wizard runs on next launch
/// - Reset All button shows confirmation dialog before proceeding
/// - Actual full reset is performed by SettingsView.resetSettings()
struct AdvancedSettingsView: View {
    // MARK: - State

    /// Whether the reset confirmation alert is currently shown.
    ///
    /// Passed as binding from parent to control alert visibility.
    @Binding var showingResetAlert: Bool

    /// Whether the onboarding reset confirmation alert is shown.
    @State private var showingOnboardingResetAlert = false

    /// Whether the clear-logs confirmation alert is shown.
    @State private var showingClearLogsAlert = false

    /// Formatted log file size (e.g. "248 KB"). Refreshed on appear and after diagnostics actions.
    @State private var logSizeText: String = "—"

    /// Formatted log line count (e.g. "4,512 lines").
    @State private var logLineCountText: String = "—"

    /// Whether the "Copied!" feedback row is shown after copying logs.
    @State private var showingCopyFeedback = false

    /// Whether a software update is available.
    @State private var updateAvailable = false

    /// The latest version string from GitHub Releases.
    @State private var latestVersion: String?

    /// Version the user chose to skip.
    @AppStorage(AppConstants.UserDefaults.updateSkippedVersion)
    private var skippedVersion: String = ""

    /// Reference to AppDelegate for Sparkle updater access.
    private var appDelegate: AppDelegate? { AppDelegate.shared }

    /// Whether automatic update checking is enabled.
    @AppStorage(AppConstants.UserDefaults.updateCheckEnabled)
    private var updateCheckEnabled = true

    /// Whether a manual update check is in progress.
    @State private var isCheckingForUpdates = false

    /// Whether the last update check was triggered manually (vs automatic/scheduled).
    @State private var isManualCheck = false

    /// Whether the app was installed via Homebrew (Sparkle is disabled in this case)
    @State private var isHomebrewInstall = false

    /// Current app version from the bundle.
    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    /// Opens a save panel to export the application log file.
    ///
    /// Presents the panel as a sheet on the settings window when available,
    /// falling back to a modal run loop. Previously used `panel.begin` with
    /// no host window, which crashed when the menu bar was the only frontmost
    /// UI (no key window).
    @MainActor
    private func exportLogs() {
        guard let logURL = Log.exportLogFile() else {
            Log.warn("No log file available for export", category: "App")
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "wolfwave-logs.log"
        let logType = UTType(filenameExtension: "log") ?? .plainText
        panel.allowedContentTypes = [logType, .plainText]
        panel.canCreateDirectories = true

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let destination = panel.url else { return }
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: logURL, to: destination)
                Log.info("Logs exported to \(destination.lastPathComponent)", category: "App")
                refreshLogStats()
            } catch {
                Log.error("Failed to export logs: \(error.localizedDescription)", category: "App")
            }
        }

        if let window = hostWindow() {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            let response = panel.runModal()
            completion(response)
        }
    }

    /// Reveals the current log file in Finder.
    private func revealLogsInFinder() {
        guard let logURL = Log.exportLogFile() else {
            Log.warn("No log file available to reveal", category: "App")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([logURL])
    }

    /// Copies the tail of the log file to the system clipboard.
    ///
    /// Limited to the last 64 KB to avoid pasteboard overload.
    private func copyLogsToClipboard() {
        guard let logURL = Log.exportLogFile() else {
            Log.warn("No log file available to copy", category: "App")
            return
        }

        do {
            let contents = try String(contentsOf: logURL, encoding: .utf8)
            let maxChars = 64 * 1024
            let trimmed: String
            if contents.count > maxChars {
                let startIndex = contents.index(contents.endIndex, offsetBy: -maxChars)
                trimmed = "… (truncated to last 64KB)\n" + String(contents[startIndex...])
            } else {
                trimmed = contents
            }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(trimmed, forType: .string)

            withAnimation { showingCopyFeedback = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                withAnimation { showingCopyFeedback = false }
            }
            Log.info("Logs copied to clipboard", category: "App")
        } catch {
            Log.error("Failed to copy logs: \(error.localizedDescription)", category: "App")
        }
    }

    /// Clears the current log file (truncates in place).
    private func clearLogs() {
        Log.clearLogFile()
        Log.info("Logs cleared by user", category: "App")
        refreshLogStats()
    }

    /// Refreshes the displayed log size + line count from the Log singleton.
    private func refreshLogStats() {
        let bytes = Log.logFileSize()
        let lines = Log.logLineCount()

        let byteFormatter = ByteCountFormatter()
        byteFormatter.allowedUnits = [.useKB, .useMB]
        byteFormatter.countStyle = .file
        logSizeText = byteFormatter.string(fromByteCount: bytes)

        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        let formattedLines = numberFormatter.string(from: NSNumber(value: lines)) ?? String(lines)
        logLineCountText = "\(formattedLines) lines"
    }

    /// Returns the host window for sheet presentation, or nil if none is visible.
    @MainActor
    private func hostWindow() -> NSWindow? {
        if let key = NSApp.keyWindow { return key }
        return NSApp.windows.first { $0.isVisible && !$0.className.contains("NSStatusBar") }
    }

    /// Main view body with update card, setup wizard, diagnostics, and danger zone sections.
    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            SectionHeaderWithStatus(
                title: "Advanced",
                subtitle: "Updates, diagnostics, and reset options."
            )

            // Software Update
            softwareUpdateCard

            Divider()
                .padding(.vertical, DSSpace.s1)

            // Onboarding Card
            VStack(alignment: .leading, spacing: DSSpace.s4) {
                VStack(alignment: .leading, spacing: DSSpace.s1) {
                    Text("Setup Wizard")
                        .font(.system(size: DSFont.Size.base, weight: .semibold))

                    Text("Walk through the setup steps again to review your connections.")
                        .font(.system(size: DSFont.Size.body))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: { showingOnboardingResetAlert = true }) {
                    Label("Rerun Setup Wizard", systemImage: "arrow.counterclockwise")
                        .font(.system(size: DSFont.Size.base, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .pointerCursor()
                .accessibilityLabel("Reset onboarding wizard")
                .accessibilityHint("Opens the setup wizard")
            }
            .cardStyle()
            .alert("Rerun Setup Wizard?", isPresented: $showingOnboardingResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset") {
                    UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.hasCompletedOnboarding)
                    Log.info("Onboarding reset by user", category: "Onboarding")
                    AppDelegate.shared?.showOnboarding()
                }
            } message: {
                Text("This will open the setup wizard. Your current settings will not be changed.")
            }

            // Diagnostics Card
            diagnosticsCard

            // Diagnostics & Privacy (on-device MetricKit opt-in)
            DiagnosticsShareCardView()

            Divider()
                .padding(.vertical, DSSpace.s1)

            // Danger Zone Card
            VStack(alignment: .leading, spacing: DSSpace.s6) {
                VStack(alignment: .leading, spacing: DSSpace.s2) {
                    HStack(spacing: DSSpace.s2) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: DSFont.Size.md))
                            .foregroundStyle(DSColor.error)
                        Text("Danger Zone")
                            .font(.system(size: DSFont.Size.md, weight: .semibold))
                            .foregroundStyle(DSColor.error)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Danger Zone")

                    Text("Permanently erases all settings and saved accounts. This can't be undone.")
                        .font(.system(size: DSFont.Size.body))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                DestructiveButton(
                    title: "Reset All Settings to Defaults",
                    systemImage: "trash",
                    accessibilityIdentifier: "resetAllSettingsButton",
                    action: { showingResetAlert = true }
                )
                .accessibilityHint("Permanently delete all settings and stored credentials")
            }
            .padding(AppConstants.SettingsUI.cardPadding)
            .background(DSColor.error.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius)
                    .stroke(DSColor.error.opacity(0.2), lineWidth: 1)
            )
        }
        .onAppear {
            isHomebrewInstall = Bundle.main.isHomebrewInstall
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.updateStateChanged)) { notification in
            isCheckingForUpdates = false
            if let version = notification.userInfo?["latestVersion"] as? String,
               let available = notification.userInfo?["isUpdateAvailable"] as? Bool {
                latestVersion = version
                updateAvailable = available && skippedVersion != version

                isManualCheck = false
            }
        }
    }

    // MARK: - Diagnostics Card

    @ViewBuilder
    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            VStack(alignment: .leading, spacing: DSSpace.s1) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Diagnostics")
                        .font(.system(size: DSFont.Size.base, weight: .semibold))
                    Spacer()
                    Text("\(logSizeText) · \(logLineCountText)")
                        .font(.system(size: DSFont.Size.sm, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Log file size \(logSizeText), \(logLineCountText)")
                }

                Text("Export logs, copy them to your clipboard, or clear them.")
                    .font(.system(size: DSFont.Size.body))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: exportLogs) {
                Label("Export Logs", systemImage: "square.and.arrow.up")
                    .font(.system(size: DSFont.Size.base, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .pointerCursor()
            .accessibilityLabel("Export application logs")
            .accessibilityHint("Save logs to a file for debugging")

            HStack(spacing: DSSpace.s2) {
                Button(action: revealLogsInFinder) {
                    Label("Reveal in Finder", systemImage: "folder")
                        .font(.system(size: DSFont.Size.body))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .pointerCursor()
                .accessibilityLabel("Reveal log file in Finder")

                Button(action: copyLogsToClipboard) {
                    Label("Copy to Clipboard", systemImage: "doc.on.clipboard")
                        .font(.system(size: DSFont.Size.body))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .pointerCursor()
                .accessibilityLabel("Copy log contents to clipboard")
            }

            if showingCopyFeedback {
                SuccessFeedbackRow(text: "Copied to clipboard!")
                    .transition(.opacity)
            }

            DestructiveButton(
                title: "Clear Logs",
                systemImage: "trash",
                accessibilityIdentifier: "clearLogsButton",
                action: { showingClearLogsAlert = true }
            )
            .accessibilityHint("Erases the current log file")
        }
        .cardStyle()
        .alert("Clear logs?", isPresented: $showingClearLogsAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { clearLogs() }
        } message: {
            Text("The current log file will be erased. This can't be undone.")
        }
        .onAppear { refreshLogStats() }
    }

    // MARK: - Software Update Card

    /// Routes to the correct update card based on install method (Homebrew vs DMG).
    @ViewBuilder
    private var softwareUpdateCard: some View {
        if isHomebrewInstall {
            homebrewUpdateCard
        } else {
            sparkleUpdateCard
        }
    }

    /// Update card shown for Homebrew installations (Sparkle disabled)
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

            HStack(spacing: DSSpace.s3) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: DSFont.Size.md))
                    .foregroundStyle(DSColor.info)

                VStack(alignment: .leading, spacing: DSSpace.s1) {
                    Text("Homebrew installation detected")
                        .font(.system(size: DSFont.Size.body, weight: .semibold))
                    Text("Use Homebrew to check for and install updates.")
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpace.s3)
            .background(DSColor.info.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.sm))

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

    /// Update card shown for DMG installations (uses Sparkle)
    @ViewBuilder
    private var sparkleUpdateCard: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            // Header row: title + version badge
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
            // Development build indicator
            HStack(spacing: DSSpace.s3) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: DSFont.Size.md))
                    .foregroundStyle(DSColor.warning)

                Text("Development build — update checks use dev-appcast.xml")
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpace.s3)
            .background(DSColor.warning.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.sm))
            #endif

            // Info banner reflecting actual toggle state
            if updateCheckEnabled && !updateAvailable {
                HStack(spacing: DSSpace.s3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: DSFont.Size.md))
                        .foregroundStyle(DSColor.success)

                    Text("Auto-updates on. We'll notify you of new versions.")
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DSSpace.s3)
                .background(DSColor.success.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.sm))
                .transition(.opacity)
            } else if !updateCheckEnabled && !updateAvailable {
                HStack(spacing: DSSpace.s3) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: DSFont.Size.md))
                        .foregroundStyle(.secondary)

                    Text("Automatic updates are off. Use Check Now to look for updates.")
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DSSpace.s3)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.sm))
                .transition(.opacity)
            }

            Divider()

            // Bottom row: auto-check toggle + Check Now button
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
                    // Reset after a delay — Sparkle's delegate callbacks
                    // will update the UI with actual results.
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(5))
                        isCheckingForUpdates = false
                    }
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

#Preview("Default State") {
    @Previewable @State var showingResetAlert = false
    AdvancedSettingsView(showingResetAlert: $showingResetAlert)
        .padding()
        .frame(width: 700)
}
#Preview("With Update Available") {
    @Previewable @State var showingResetAlert = false
    @Previewable @AppStorage(AppConstants.UserDefaults.updateCheckEnabled) var updateCheckEnabled = true
    
    let view = AdvancedSettingsView(showingResetAlert: $showingResetAlert)
    return view
        .padding()
        .frame(width: 700)
        .onAppear {
            NotificationCenter.default.post(
                name: Notification.Name.updateStateChanged,
                object: nil,
                userInfo: [
                    "latestVersion": "1.2.0",
                    "isUpdateAvailable": true
                ]
            )
        }
}

#Preview("Checking for Updates") {
    @Previewable @State var showingResetAlert = false
    
    struct CheckingView: View {
        var body: some View {
            VStack(alignment: .leading, spacing: DSSpace.s6) {
                Text("Advanced")
                    .sectionHeader()

                VStack(alignment: .leading, spacing: DSSpace.s4) {
                    HStack {
                        VStack(alignment: .leading, spacing: DSSpace.s1) {
                            Text("Software Update")
                                .font(.system(size: DSFont.Size.base, weight: .semibold))
                            
                            Text("Current version: 1.1.0")
                                .font(.system(size: DSFont.Size.body))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    
                    Divider()
                    
                    HStack {
                        Toggle("Check automatically", isOn: .constant(true))
                            .toggleStyle(.checkbox)
                            .font(.system(size: DSFont.Size.body))
                        
                        Spacer()
                        
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                    }
                }
                .cardStyle()
            }
        }
    }
    
    return CheckingView()
        .padding()
        .frame(width: 700)
}

