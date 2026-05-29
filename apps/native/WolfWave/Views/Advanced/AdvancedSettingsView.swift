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

/// Advanced settings interface providing diagnostics and dangerous operations.
///
/// Provides controls for:
/// - Resetting the onboarding wizard so it shows again on next launch
/// - Exporting / clearing diagnostic logs
/// - Resetting all application settings to defaults
/// - Clearing stored authentication tokens from Keychain
/// - Disconnecting from Twitch
///
/// State:
/// - Uses @Binding for showingResetAlert (passed from parent SettingsView)
/// - Shares context with AppDelegate via NSApplication.shared.delegate
///
/// Actions:
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

    /// Whether the clear-artwork-cache confirmation alert is shown.
    @State private var showingClearArtworkAlert = false

    /// Formatted artwork cache summary (e.g. "42 tracks · 18 KB").
    @State private var artworkStatsText: String = "—"

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

    /// Clears the persisted artwork links cache (memory + disk).
    private func clearArtworkCache() {
        ArtworkService.shared.clearCache()
        Log.info("Artwork cache cleared by user", category: "App")
        refreshArtworkStats()
    }

    /// Refreshes the displayed artwork cache entry count + disk size.
    private func refreshArtworkStats() {
        let stats = ArtworkService.shared.cacheStats()
        let byteFormatter = ByteCountFormatter()
        byteFormatter.allowedUnits = [.useKB, .useMB]
        byteFormatter.countStyle = .file
        let size = byteFormatter.string(fromByteCount: stats.diskBytes)
        let trackWord = stats.entryCount == 1 ? "track" : "tracks"
        artworkStatsText = "\(stats.entryCount) \(trackWord) · \(size)"
    }

    /// Returns the host window for sheet presentation, or nil if none is visible.
    @MainActor
    private func hostWindow() -> NSWindow? {
        if let key = NSApp.keyWindow { return key }
        return NSApp.windows.first { $0.isVisible && !$0.className.contains("NSStatusBar") }
    }

    /// Main view body with setup wizard, diagnostics, and danger zone sections.
    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            SectionHeaderWithStatus(
                title: "Advanced",
                subtitle: "Diagnostics and reset options."
            )

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

            // Artwork Cache Card
            artworkCacheCard

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

    // MARK: - Artwork Cache Card

    @ViewBuilder
    private var artworkCacheCard: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            VStack(alignment: .leading, spacing: DSSpace.s1) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Artwork Cache")
                        .font(.system(size: DSFont.Size.base, weight: .semibold))
                    Spacer()
                    Text(artworkStatsText)
                        .font(.system(size: DSFont.Size.sm, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Artwork cache: \(artworkStatsText)")
                }

                Text("Saved album art links so tracks don't reload every launch. Clear to force a fresh lookup.")
                    .font(.system(size: DSFont.Size.body))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DestructiveButton(
                title: "Clear Artwork Cache",
                systemImage: "trash",
                accessibilityIdentifier: "clearArtworkCacheButton",
                action: { showingClearArtworkAlert = true }
            )
            .accessibilityHint("Erases saved album art links")
        }
        .cardStyle()
        .alert("Clear artwork cache?", isPresented: $showingClearArtworkAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { clearArtworkCache() }
        } message: {
            Text("Saved album art links will be erased. They'll be fetched again as tracks play.")
        }
        .onAppear { refreshArtworkStats() }
    }

}

// MARK: - Preview

#Preview("Default State") {
    @Previewable @State var showingResetAlert = false
    AdvancedSettingsView(showingResetAlert: $showingResetAlert)
        .padding()
        .frame(width: 700)
}

