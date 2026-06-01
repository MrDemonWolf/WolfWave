//
//  TwitchCommandsCard.swift
//  WolfWave
//
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Bot Commands card for the Twitch settings pane.
///
/// Hosts the `!song`, `!last`, and "Include song.link" controls plus their
/// per-command cooldown sliders and custom-alias text fields. Extracted from
/// `SettingsView` so toggling any of its `@AppStorage` keys does not invalidate
/// the parent settings shell on each tap.
struct TwitchCommandsCard: View {

    @AppStorage(AppConstants.UserDefaults.currentSongCommandEnabled)
    private var currentSongCommandEnabled = false

    @AppStorage(AppConstants.UserDefaults.lastSongCommandEnabled)
    private var lastSongCommandEnabled = false

    @AppStorage(AppConstants.UserDefaults.songCommandSongLinkEnabled)
    private var songCommandSongLinkEnabled = false

    @AppStorage(AppConstants.UserDefaults.songCommandGlobalCooldown)
    private var songGlobalCooldown: Double = 15.0
    @AppStorage(AppConstants.UserDefaults.songCommandUserCooldown)
    private var songUserCooldown: Double = 15.0
    @AppStorage(AppConstants.UserDefaults.lastSongCommandGlobalCooldown)
    private var lastSongGlobalCooldown: Double = 15.0
    @AppStorage(AppConstants.UserDefaults.lastSongCommandUserCooldown)
    private var lastSongUserCooldown: Double = 15.0

    @AppStorage(AppConstants.UserDefaults.songCommandAliases)
    private var songCommandAliases = ""
    @AppStorage(AppConstants.UserDefaults.lastSongCommandAliases)
    private var lastSongCommandAliases = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: DSSpace.s2) {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: DSFont.Size.x15))
                        .foregroundStyle(Color(nsColor: .controlAccentColor))
                    Text("Bot Commands")
                        .sectionSubHeader()
                }

                Text("Choose which commands people can use in chat.")
                    .font(.system(size: DSFont.Size.base))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 1) {
                commandToggleRow(
                    title: "!song Command",
                    subtitle: "!song  ·  !currentsong  ·  !nowplaying",
                    isOn: $currentSongCommandEnabled,
                    accessibilityLabel: "Enable Current Playing Song command",
                    accessibilityIdentifier: "currentSongCommandToggle",
                    isFirst: true
                ) { enabled in
                    Log.debug("TwitchCommandsCard: !song \(enabled ? "enabled" : "disabled")", category: "Twitch")
                }

                if currentSongCommandEnabled {
                    cooldownRow(
                        label: "!song cooldowns",
                        globalCooldown: $songGlobalCooldown,
                        userCooldown: $songUserCooldown
                    )
                    commandAliasRow(aliases: $songCommandAliases,
                                    accessibilityIdentifier: "songCommandAliases")
                }

                commandToggleRow(
                    title: "!last Command",
                    subtitle: "!last  ·  !lastsong  ·  !prevsong",
                    isOn: $lastSongCommandEnabled,
                    accessibilityLabel: "Enable Last Played Song command",
                    accessibilityIdentifier: "lastSongCommandToggle",
                    isLast: !lastSongCommandEnabled && !currentSongCommandEnabled
                ) { enabled in
                    Log.debug("TwitchCommandsCard: !last \(enabled ? "enabled" : "disabled")", category: "Twitch")
                }

                if lastSongCommandEnabled {
                    cooldownRow(
                        label: "!last cooldowns",
                        globalCooldown: $lastSongGlobalCooldown,
                        userCooldown: $lastSongUserCooldown
                    )
                    commandAliasRow(aliases: $lastSongCommandAliases,
                                    accessibilityIdentifier: "lastSongCommandAliases")
                }

                if currentSongCommandEnabled || lastSongCommandEnabled {
                    commandToggleRow(
                        title: "Include song.link",
                        subtitle: "Appends a cross-platform link to !song and !last replies",
                        isOn: $songCommandSongLinkEnabled,
                        accessibilityLabel: "Include song.link URL in song command reply",
                        accessibilityIdentifier: "songCommandSongLinkToggle",
                        isLast: true
                    ) { _ in }
                }
            }
            .cardStyleUnpadded()

            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.secondary)
                Text("Cooldowns don't apply to you or your mods.")
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func commandToggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        isFirst: Bool = false,
        isLast: Bool = false,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        ToggleSettingRow(
            title: title,
            subtitle: subtitle,
            isOn: isOn,
            accessibilityLabel: accessibilityLabel,
            accessibilityIdentifier: accessibilityIdentifier,
            onChange: onChange
        )
        .padding(.horizontal, AppConstants.SettingsUI.cardPadding)
        .padding(.vertical, DSSpace.s4)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
                    .padding(.leading, AppConstants.SettingsUI.cardPadding)
            }
        }
    }

    @ViewBuilder
    private func cooldownRow(
        label: String,
        globalCooldown: Binding<Double>,
        userCooldown: Binding<Double>,
        isLast: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: DSSpace.s2) {
            Text(label)
                .sectionEyebrow()

            HStack(spacing: DSSpace.s4) {
                VStack(alignment: .leading, spacing: DSSpace.s0) {
                    Text("Everyone: \(Int(globalCooldown.wrappedValue))s")
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(.secondary)
                    Slider(value: globalCooldown, in: 0...30, step: 5)
                        .controlSize(.small)
                        .accessibilityLabel("\(label) global cooldown")
                        .accessibilityValue("\(Int(globalCooldown.wrappedValue)) seconds")
                        .accessibilityHint("Adjusts the global cooldown between 0 and 30 seconds")
                }

                VStack(alignment: .leading, spacing: DSSpace.s0) {
                    Text("Per person: \(Int(userCooldown.wrappedValue))s")
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(.secondary)
                    Slider(value: userCooldown, in: 0...60, step: 5)
                        .controlSize(.small)
                        .accessibilityLabel("\(label) per-user cooldown")
                        .accessibilityValue("\(Int(userCooldown.wrappedValue)) seconds")
                        .accessibilityHint("Adjusts the per-user cooldown between 0 and 60 seconds")
                }
            }
        }
        .padding(.horizontal, AppConstants.SettingsUI.cardPadding)
        .padding(.vertical, DSSpace.s2)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
                    .padding(.leading, AppConstants.SettingsUI.cardPadding)
            }
        }
    }

    @ViewBuilder
    private func commandAliasRow(
        aliases: Binding<String>,
        accessibilityIdentifier: String,
        isLast: Bool = false
    ) -> some View {
        HStack(spacing: DSSpace.s2) {
            Text("Custom aliases:")
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.tertiary)
            TextField("e.g. np, track", text: aliases)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: DSFont.Size.sm))
                .frame(maxWidth: 200)
                .accessibilityLabel("Custom aliases")
                .accessibilityIdentifier(accessibilityIdentifier)
        }
        .padding(.horizontal, AppConstants.SettingsUI.cardPadding)
        .padding(.vertical, DSSpace.s2)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
                    .padding(.leading, AppConstants.SettingsUI.cardPadding)
            }
        }
    }
}

// MARK: - Preview

#Preview("Twitch Commands") {
    TwitchCommandsCard()
        .padding()
        .frame(width: 700)
}
