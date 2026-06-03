//
//  SettingsImportSheet.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-02.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Review sheet shown after the user picks a settings backup to import.
///
/// Portable preferences are always restored. For each account the backup had
/// configured (Twitch is the only OAuth account in WolfWave), the user opts in
/// to restore it and reconnect; leaving it off skips that account entirely. The
/// backup never contains credentials, so reconnecting always means signing in
/// again afterward.
struct SettingsImportSheet: View {

    // MARK: - Input

    /// The decoded backup being reviewed.
    let backup: SettingsBackup

    /// How many portable preferences will be restored.
    let restorableCount: Int

    /// Called with the user's choices when they confirm the import.
    let onConfirm: (SettingsBackupCoder.ImportChoices) -> Void

    /// Called when the user cancels.
    let onCancel: () -> Void

    // MARK: - State

    /// Whether to restore the Twitch channel and prompt re-sign-in.
    @State private var reconnectTwitch = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            header

            Text(summaryLine)
                .font(.system(size: DSFont.Size.base))
                .fixedSize(horizontal: false, vertical: true)

            accountsSection

            Spacer(minLength: 0)

            buttons
        }
        .padding(DSSpace.s7)
        .frame(width: 460)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpace.s1) {
            Text("Import Settings")
                .font(.system(size: DSFont.Size.lg, weight: .semibold))
            Text(sourceLine)
                .font(.system(size: DSFont.Size.body))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var accountsSection: some View {
        if let twitch = backup.integrations.twitch {
            VStack(alignment: .leading, spacing: DSSpace.s2) {
                Text("Accounts")
                    .font(.system(size: DSFont.Size.sm, weight: .semibold))
                    .foregroundStyle(.secondary)

                ToggleSettingRow(
                    title: "Reconnect Twitch",
                    subtitle: "This backup was connected to \(channelDisplay(twitch.channelName)). Turn on to restore it and sign in again. Your login is not part of the backup.",
                    isOn: $reconnectTwitch,
                    accessibilityLabel: "Reconnect Twitch",
                    accessibilityIdentifier: "importReconnectTwitchToggle"
                )
                .cardStyle()
            }
        } else {
            Text("No connected accounts to restore. Only your preferences will be imported.")
                .font(.system(size: DSFont.Size.body))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var buttons: some View {
        HStack(spacing: DSSpace.s3) {
            Spacer()
            Button("Cancel", role: .cancel) { onCancel() }
                .keyboardShortcut(.cancelAction)
                .pointerCursor()
            Button("Import") {
                onConfirm(SettingsBackupCoder.ImportChoices(reconnectTwitch: reconnectTwitch))
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .pointerCursor()
            .accessibilityIdentifier("confirmImportButton")
        }
    }

    // MARK: - Copy Helpers

    private var summaryLine: String {
        let noun = restorableCount == 1 ? "preference" : "preferences"
        return "\(restorableCount) \(noun) will be restored. Existing settings not in the backup are left as they are."
    }

    private var sourceLine: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let date = formatter.string(from: backup.exportedAt)
        return "From a backup made \(date), WolfWave \(backup.appVersion) (\(backup.appBuild))."
    }

    private func channelDisplay(_ name: String) -> String {
        name.hasPrefix("#") ? name : "#\(name)"
    }
}

// MARK: - Preview

#Preview("With Twitch") {
    SettingsImportSheet(
        backup: SettingsBackup(
            format: SettingsBackup.currentFormat,
            schemaVersion: SettingsBackup.currentSchemaVersion,
            appVersion: "1.4.0",
            appBuild: "140",
            exportedAt: Date(),
            settings: [:],
            integrations: SettingsBackup.Integrations(
                twitch: SettingsBackup.Integrations.Twitch(channelName: "mrdemonwolf")
            )
        ),
        restorableCount: 42,
        onConfirm: { _ in },
        onCancel: {}
    )
}

#Preview("No Accounts") {
    SettingsImportSheet(
        backup: SettingsBackup(
            format: SettingsBackup.currentFormat,
            schemaVersion: SettingsBackup.currentSchemaVersion,
            appVersion: "1.4.0",
            appBuild: "140",
            exportedAt: Date(),
            settings: [:],
            integrations: SettingsBackup.Integrations(twitch: nil)
        ),
        restorableCount: 18,
        onConfirm: { _ in },
        onCancel: {}
    )
}
