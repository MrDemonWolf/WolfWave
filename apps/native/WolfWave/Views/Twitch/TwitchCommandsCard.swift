//
//  TwitchCommandsCard.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-28.
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

    @AppStorage(AppConstants.UserDefaults.wolfwaveCommandEnabled)
    private var wolfwaveCommandEnabled = false
    @AppStorage(AppConstants.UserDefaults.wolfwaveCommandGlobalCooldown)
    private var wolfwaveGlobalCooldown: Double = 15.0
    @AppStorage(AppConstants.UserDefaults.wolfwaveCommandUserCooldown)
    private var wolfwaveUserCooldown: Double = 15.0
    @AppStorage(AppConstants.UserDefaults.wolfwaveCommandAliases)
    private var wolfwaveCommandAliases = ""
    @AppStorage(AppConstants.UserDefaults.wolfwaveCommandReplyStyle)
    private var wolfwaveReplyStyle = WolfWaveReplyStyle.default.rawValue

    /// Resolved reply text for the selected style, shown as a live preview.
    private var selectedWolfwaveMessage: String {
        (WolfWaveReplyStyle(rawValue: wolfwaveReplyStyle) ?? .default).message
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            VStack(alignment: .leading, spacing: DSSpace.s1h) {
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
                    accessibilityIdentifier: "lastSongCommandToggle"
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
                        accessibilityIdentifier: "songCommandSongLinkToggle"
                    ) { _ in }
                }

                commandToggleRow(
                    title: "!wolfwave Command",
                    subtitle: "!wolfwave  ·  what WolfWave is + where to get it",
                    isOn: $wolfwaveCommandEnabled,
                    accessibilityLabel: "Enable WolfWave info command",
                    accessibilityIdentifier: "wolfwaveCommandToggle",
                    isLast: !wolfwaveCommandEnabled
                ) { enabled in
                    Log.debug("TwitchCommandsCard: !wolfwave \(enabled ? "enabled" : "disabled")", category: "Twitch")
                }

                if wolfwaveCommandEnabled {
                    wolfwaveReplyRow(selection: $wolfwaveReplyStyle)
                    cooldownRow(
                        label: "!wolfwave cooldowns",
                        globalCooldown: $wolfwaveGlobalCooldown,
                        userCooldown: $wolfwaveUserCooldown
                    )
                    commandAliasRow(aliases: $wolfwaveCommandAliases,
                                    accessibilityIdentifier: "wolfwaveCommandAliases",
                                    isLast: true)
                }
            }
            .cardStyleUnpadded()

            HintRow("Cooldowns don't apply to you or your mods.")
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

    @ViewBuilder
    private func wolfwaveReplyRow(selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: DSSpace.s2) {
            HStack(spacing: DSSpace.s2) {
                Text("Reply")
                    .sectionEyebrow()
                Spacer()
                Picker("Reply style", selection: selection) {
                    ForEach(WolfWaveReplyStyle.allCases) { style in
                        Text(style.label).tag(style.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(maxWidth: 200)
                .accessibilityLabel("WolfWave reply style")
                .accessibilityIdentifier("wolfwaveReplyStyle")
            }

            // Live preview of exactly what viewers will see in chat.
            Text(selectedWolfwaveMessage)
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Reply preview")
        }
        .padding(.horizontal, AppConstants.SettingsUI.cardPadding)
        .padding(.vertical, DSSpace.s2)
        .overlay(alignment: .bottom) {
            Divider()
                .padding(.leading, AppConstants.SettingsUI.cardPadding)
        }
    }
}

// MARK: - Preview

#Preview("Twitch Commands") {
    TwitchCommandsCard()
        .padding()
        .frame(width: 700)
}
