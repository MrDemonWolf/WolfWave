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

/// Advanced settings: diagnostics and the destructive reset operations.
///
/// Cards, top to bottom: rerun the setup wizard, log diagnostics (export /
/// copy / reveal / clear), artwork cache (size + clear), opt-in MetricKit
/// diagnostics share card, settings backup (export / import), and the Danger
/// Zone full reset.
///
/// `showingResetAlert` is a @Binding from the parent `SettingsView` because the
/// actual reset is performed by `SettingsView.resetSettings()` after the alert
/// confirms. Everything else uses local @State.
struct AdvancedSettingsView: View {
    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - State

    /// Whether the reset confirmation alert is currently shown.
    ///
    /// Passed as binding from parent to control alert visibility.
    @Binding var showingResetAlert: Bool

    /// True when the previous run left a crash breadcrumb (set at launch in
    /// `applicationDidFinishLaunching`). Drives the "Recovered from a crash"
    /// callout at the top of this pane.
    @AppStorage(AppConstants.UserDefaults.lastLaunchCrashed) private var lastLaunchCrashed = false

    /// Mirrors the opt-in MetricKit diagnostics toggle so the crash callout can
    /// point the user at it without enabling anything on their behalf.
    @AppStorage(AppConstants.UserDefaults.shareDiagnosticsEnabled) private var shareDiagnosticsEnabled = false

    /// Whether the onboarding reset confirmation alert is shown.
    @State private var showingOnboardingResetAlert = false

    /// Whether the clear-logs confirmation alert is shown.
    @State private var showingClearLogsAlert = false

    /// Formatted log file size (e.g. "248 KB"). Refreshed on appear and after diagnostics actions.
    @State private var logSizeText: String = "N/A"

    /// Formatted log line count (e.g. "4,512 lines").
    @State private var logLineCountText: String = "N/A"

    /// Whether the "Copied!" feedback row is shown after copying logs.
    @State private var showingCopyFeedback = false

    /// Whether the clear-artwork-cache confirmation alert is shown.
    @State private var showingClearArtworkAlert = false

    /// Formatted artwork cache summary (e.g. "42 tracks · 18 KB").
    @State private var artworkStatsText: String = "N/A"

    /// The decoded backup awaiting the user's import confirmation.
    @State private var pendingBackup: SettingsBackup?

    /// Whether the import review sheet is shown.
    @State private var showingImportSheet = false

    /// Message shown when an import file can't be read.
    @State private var importErrorMessage: String?

    /// Whether the import error alert is shown.
    @State private var showingImportError = false

    /// Message shown after a successful import.
    @State private var importSuccessMessage: String?

    /// Whether the import success alert is shown.
    @State private var showingImportSuccess = false

    /// Message shown when an export can't be built or saved.
    @State private var exportErrorMessage: String?

    /// Whether the export error alert is shown.
    @State private var showingExportError = false

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

            Pasteboard.copy(trimmed)

            withAnimation(reduceMotion ? nil : .default) { showingCopyFeedback = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                withAnimation(reduceMotion ? nil : .default) { showingCopyFeedback = false }
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
    ///
    /// The read is offloaded to a detached task: `logLineCount()` drains queued
    /// writes then streams the whole log file (up to the 5 MB rotation cap)
    /// through `fileQueue.sync`, which would stall first paint on a big log if
    /// run on the main thread. State is assigned back on the MainActor. Mirrors
    /// `DebugLogsAndEventsCard`.
    private func refreshLogStats() {
        Task { @MainActor in
            let stats = await Task.detached(priority: .userInitiated) {
                (bytes: Log.logFileSize(), lines: Log.logLineCount())
            }.value

            logSizeText = ByteFormatting.string(stats.bytes)

            let numberFormatter = NumberFormatter()
            numberFormatter.numberStyle = .decimal
            let formattedLines = numberFormatter.string(from: NSNumber(value: stats.lines)) ?? String(stats.lines)
            logLineCountText = "\(formattedLines) lines"
        }
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
        let size = ByteFormatting.string(stats.diskBytes)
        let trackWord = stats.entryCount == 1 ? "track" : "tracks"
        artworkStatsText = "\(stats.entryCount) \(trackWord) · \(size)"
    }

    /// Returns the host window for sheet presentation, or nil if none is visible.
    @MainActor
    private func hostWindow() -> NSWindow? {
        if let key = NSApp.keyWindow { return key }
        return NSApp.windows.first { $0.isVisible && !$0.className.contains("NSStatusBar") }
    }

    /// "Recovered from a crash" callout shown at the top of the pane after the
    /// previous run crashed. The breadcrumb that drives it is written by
    /// `CrashReporter`; reporting a bug or dismissing clears the flag.
    @ViewBuilder
    private var crashRecoveryCallout: some View {
        VStack(alignment: .leading, spacing: DSSpace.s2) {
            CalloutBanner(
                shareDiagnosticsEnabled
                    ? "WolfWave closed unexpectedly last time. If it keeps happening, send a bug report so we can dig in."
                    : "WolfWave closed unexpectedly last time. If it keeps happening, send a bug report. You can also turn on the private, on-device diagnostics below. Nothing leaves your Mac.",
                title: "Recovered from a crash",
                style: .warning
            )

            HStack(spacing: DSSpace.s2) {
                Button("Report a Bug\u{2026}") {
                    AppDelegate.shared?.reportBug()
                    lastLaunchCrashed = false
                }
                Spacer()
                Button("Dismiss") { lastLaunchCrashed = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: DSFont.Size.sm))
        }
    }

    /// Main view body with setup wizard, diagnostics, and danger zone sections.
    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            SectionHeaderWithStatus(
                title: "Advanced",
                subtitle: "Diagnostics and reset options."
            )

            if lastLaunchCrashed {
                crashRecoveryCallout
            }

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

            // Back Up / Restore Settings Card
            backupCard

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
                    .accessibilityAddTraits(.isHeader)

                    Text("Erase & Reset wipes everything and restarts the app. Clear Logs can't be undone. Clearing the artwork cache just forces a fresh lookup.")
                        .font(.system(size: DSFont.Size.body))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: DSSpace.s2) {
                    DestructiveButton(
                        title: "Clear Logs",
                        systemImage: "trash",
                        accessibilityIdentifier: "clearLogsButton",
                        action: { showingClearLogsAlert = true }
                    )
                    .accessibilityHint("Erases the current log file")

                    DestructiveButton(
                        title: "Clear Artwork Cache",
                        systemImage: "trash",
                        accessibilityIdentifier: "clearArtworkCacheButton",
                        action: { showingClearArtworkAlert = true }
                    )
                    .accessibilityHint("Erases saved album art links")

                    DestructiveButton(
                        title: "Erase All Data & Reset",
                        systemImage: "trash",
                        accessibilityIdentifier: "resetAllSettingsButton",
                        action: { showingResetAlert = true }
                    )
                    .accessibilityHint("Permanently erase all settings, credentials, logs, listening history, and caches, then relaunch")
                }
            }
            .cardStyle()
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

                Text("Export logs, copy them to your clipboard, or reveal the file in Finder.")
                    .font(.system(size: DSFont.Size.body))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Uniform 2-up action grid keeps the read actions visually quiet
            // and aligned, instead of one bright full-width bar plus two
            // smaller ones at mixed control sizes.
            ActionGrid(columns: 2) {
                GridRow {
                    ActionGridButton(
                        title: "Export Logs",
                        systemImage: "square.and.arrow.up",
                        action: exportLogs,
                        accessibilityIdentifier: "exportLogsButton"
                    )
                    ActionGridButton(
                        title: "Copy to Clipboard",
                        systemImage: "doc.on.clipboard",
                        action: copyLogsToClipboard,
                        accessibilityIdentifier: "copyLogsButton"
                    )
                }
                GridRow {
                    ActionGridButton(
                        title: "Reveal in Finder",
                        systemImage: "folder",
                        action: revealLogsInFinder,
                        accessibilityIdentifier: "revealLogsButton"
                    )
                    .gridCellColumns(2)
                }
            }

            if showingCopyFeedback {
                SuccessFeedbackRow(text: "Copied to clipboard!")
                    .transition(.opacity)
            }
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

                Text("Saved album art links so tracks don't reload every launch.")
                    .font(.system(size: DSFont.Size.body))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    // MARK: - Backup Card

    @ViewBuilder
    private var backupCard: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            VStack(alignment: .leading, spacing: DSSpace.s1) {
                Text("Back Up Settings")
                    .font(.system(size: DSFont.Size.base, weight: .semibold))

                Text("Save your preferences to a file, or restore them on another Mac. Accounts and permissions aren't included, so after importing you'll reconnect Twitch and re-grant access like Apple Music control.")
                    .font(.system(size: DSFont.Size.body))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ActionGrid(columns: 2) {
                GridRow {
                    ActionGridButton(
                        title: "Export Settings",
                        systemImage: "square.and.arrow.up",
                        action: exportSettings,
                        accessibilityIdentifier: "exportSettingsButton"
                    )
                    ActionGridButton(
                        title: "Import Settings",
                        systemImage: "square.and.arrow.down",
                        action: chooseImportFile,
                        accessibilityIdentifier: "importSettingsButton"
                    )
                }
            }
        }
        .cardStyle()
        .sheet(isPresented: $showingImportSheet) {
            if let backup = pendingBackup {
                SettingsImportSheet(
                    backup: backup,
                    restorableCount: SettingsBackupService().restorableCount(backup),
                    onConfirm: applyImport,
                    onCancel: {
                        showingImportSheet = false
                        pendingBackup = nil
                    }
                )
            }
        }
        .alert("Couldn't Import", isPresented: $showingImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "That file couldn't be read.")
        }
        .alert("Settings Imported", isPresented: $showingImportSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importSuccessMessage ?? "Your settings were restored.")
        }
        .alert("Couldn't Export", isPresented: $showingExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "Couldn't save your backup.")
        }
    }

    // MARK: - Backup Actions

    /// Exports portable settings to a user-chosen JSON file. Accounts and
    /// secrets are excluded. See `AppConstants.UserDefaults.exportableKeys`.
    /// Build or write failures surface the export error alert.
    @MainActor
    private func exportSettings() {
        let service = SettingsBackupService()
        let data: Data
        do {
            data = try service.makeBackupData()
        } catch {
            Log.error("Failed to build settings backup: \(error.localizedDescription)", category: "App")
            exportErrorMessage = "Couldn't save your backup. \(error.localizedDescription)"
            showingExportError = true
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "wolfwave-settings-\(Self.fileDateStamp()).json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
                Log.info("Settings exported to \(url.lastPathComponent)", category: "App")
            } catch {
                Log.error("Failed to write settings backup: \(error.localizedDescription)", category: "App")
                exportErrorMessage = "Couldn't save your backup. \(error.localizedDescription)"
                showingExportError = true
            }
        }

        if let window = hostWindow() {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    /// Presents an open panel to pick a backup file, then decodes it.
    @MainActor
    private func chooseImportFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            loadImportFile(url)
        }

        if let window = hostWindow() {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    /// Reads and validates a backup file, then opens the review sheet or shows
    /// an error alert.
    @MainActor
    private func loadImportFile(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            pendingBackup = try SettingsBackupService().decode(data)
            showingImportSheet = true
        } catch let error as SettingsBackupCoder.BackupError {
            importErrorMessage = Self.message(for: error)
            showingImportError = true
        } catch {
            importErrorMessage = "That file couldn't be read."
            showingImportError = true
        }
    }

    /// Applies the reviewed backup with the user's per-account choices.
    @MainActor
    private func applyImport(_ choices: SettingsBackupCoder.ImportChoices) {
        guard let backup = pendingBackup else { return }
        let summary = SettingsBackupService().apply(backup, choices: choices)
        showingImportSheet = false
        pendingBackup = nil
        importSuccessMessage = Self.successMessage(summary)
        showingImportSuccess = true
        Log.info(
            "Settings imported (\(summary.restoredCount) restored, twitch=\(summary.reconnectedTwitch))",
            category: "App"
        )
    }

    /// Cached: `DateFormatter` allocation is expensive and this runs per export.
    private static let fileDateStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// `yyyy-MM-dd` stamp for the default export filename.
    private static func fileDateStamp() -> String {
        fileDateStampFormatter.string(from: Date())
    }

    /// Human-readable message for a backup decode error.
    private static func message(for error: SettingsBackupCoder.BackupError) -> String {
        switch error {
        case .notReadable:
            return "That file couldn't be read. It may be damaged or not a WolfWave backup."
        case .notWolfWaveFile:
            return "That's not a WolfWave settings file."
        case .unsupportedNewerSchema:
            return "This backup was made by a newer version of WolfWave. Update WolfWave, then try again."
        }
    }

    /// Confirmation message summarizing an applied import.
    private static func successMessage(_ summary: SettingsBackupService.ApplySummary) -> String {
        let noun = SettingsBackupService.ApplySummary.preferenceNoun(summary.restoredCount)
        var message = "Restored \(summary.restoredCount) \(noun)."
        if summary.reconnectedTwitch {
            message += " Open the Twitch tab to finish signing in."
        }
        return message
    }

}

// MARK: - Preview

#Preview("Default State") {
    @Previewable @State var showingResetAlert = false
    AdvancedSettingsView(showingResetAlert: $showingResetAlert)
        .padding()
        .frame(width: 700)
}

