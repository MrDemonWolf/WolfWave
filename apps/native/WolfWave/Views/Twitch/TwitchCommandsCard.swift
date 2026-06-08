//
//  TwitchCommandsCard.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-28.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit
import SwiftUI

/// Bot Commands card for the Twitch settings pane.
///
/// Hosts the `!song`, `!last`, and "Include song.link" controls plus their
/// per-command cooldown sliders and custom-alias text fields. Extracted from
/// `SettingsView` so toggling any of its `@AppStorage` keys does not invalidate
/// the parent settings shell on each tap.
struct TwitchCommandsCard: View {

    /// Shared Twitch state, read to gate the card on a live, authorized connection.
    /// Stored as a plain `let`: the Observation framework tracks property reads in
    /// `body` regardless, and this card never writes back, so `@Bindable` isn't needed.
    let viewModel: TwitchViewModel

    /// Commands can only fire when chat is connected and the sign-in hasn't expired.
    /// When false, every control is disabled and a lock banner explains why.
    private var twitchReady: Bool {
        viewModel.channelConnected && !viewModel.reauthNeeded
    }

    /// Lock-banner copy. Both lines point "above" at the Twitch auth card in the
    /// same pane rather than duplicating its connect/reconnect button. The
    /// expired-vs-disconnected split is rendered by ``TwitchConnectionNotice``.
    private let expiredMessage =
        "Your Twitch sign-in expired. Reconnect above to keep chat commands working."
    private let disconnectedMessage =
        "Connect with Twitch above to let people use these chat commands."

    /// Apple Events automation grant for Music.app. `!song` / `!last` read the
    /// now-playing track through it, so a denial means those two commands return
    /// nothing even with Twitch connected. Seeded from the cheap cache, then
    /// refreshed with a live probe on appear / app reactivation.
    @State private var musicPermission: MusicPermissionState = MusicPermissionCache.read() ?? .unknown

    /// Surfaces the Apple Music access callout only when it's actionable: Twitch
    /// is fine (so the card isn't already blocked), automation is denied, and at
    /// least one now-playing command that depends on it is enabled. `!wolfwave`
    /// needs no Music access, so an all-`!wolfwave` setup never nags.
    private var needsMusicAccess: Bool {
        twitchReady
            && musicPermission == .denied
            && (currentSongCommandEnabled || lastSongCommandEnabled)
    }

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
                Text("Bot Commands")
                    .sectionHeader()

                Text("Choose which commands people can use in chat.")
                    .fieldSubtitle()
            }

            TwitchConnectionNotice(
                isConnected: viewModel.channelConnected,
                reauthNeeded: viewModel.reauthNeeded,
                expiredMessage: expiredMessage,
                disconnectedMessage: disconnectedMessage
            )

            if needsMusicAccess {
                MusicPermissionBanner(
                    message: "WolfWave needs Apple Music automation access to read your now-playing track for !song and !last. Enable it in System Settings → Privacy & Security → Automation."
                )
            }

            VStack(spacing: 1) {
                CommandSettingRow(
                    title: "!song Command",
                    triggers: "!song  ·  !currentsong  ·  !nowplaying",
                    isOn: $currentSongCommandEnabled,
                    accessibilityLabel: "Enable Current Playing Song command",
                    accessibilityIdentifier: "currentSongCommandToggle",
                    cooldown: .init(global: $songGlobalCooldown, user: $songUserCooldown),
                    aliases: $songCommandAliases,
                    aliasAccessibilityIdentifier: "songCommandAliases",
                    onChange: { enabled in
                        Log.debug("TwitchCommandsCard: !song \(enabled ? "enabled" : "disabled")", category: "Twitch")
                    }
                )

                CommandSettingRow(
                    title: "!last Command",
                    triggers: "!last  ·  !lastsong  ·  !prevsong",
                    isOn: $lastSongCommandEnabled,
                    accessibilityLabel: "Enable Last Played Song command",
                    accessibilityIdentifier: "lastSongCommandToggle",
                    cooldown: .init(global: $lastSongGlobalCooldown, user: $lastSongUserCooldown),
                    aliases: $lastSongCommandAliases,
                    aliasPlaceholder: "e.g. ll, lp",
                    aliasAccessibilityIdentifier: "lastSongCommandAliases",
                    onChange: { enabled in
                        Log.debug("TwitchCommandsCard: !last \(enabled ? "enabled" : "disabled")", category: "Twitch")
                    }
                )

                if currentSongCommandEnabled || lastSongCommandEnabled {
                    CommandSettingRow(
                        title: "Include song.link",
                        triggers: "Appends a cross-platform link to !song and !last replies",
                        isOn: $songCommandSongLinkEnabled,
                        accessibilityLabel: "Include song.link URL in song command reply",
                        accessibilityIdentifier: "songCommandSongLinkToggle"
                    )
                }

                CommandSettingRow(
                    title: "!wolfwave Command",
                    triggers: "!wolfwave  ·  what WolfWave is + where to get it",
                    isOn: $wolfwaveCommandEnabled,
                    accessibilityLabel: "Enable WolfWave info command",
                    accessibilityIdentifier: "wolfwaveCommandToggle",
                    cooldown: .init(global: $wolfwaveGlobalCooldown, user: $wolfwaveUserCooldown),
                    aliases: $wolfwaveCommandAliases,
                    aliasPlaceholder: "e.g. ww, app",
                    aliasAccessibilityIdentifier: "wolfwaveCommandAliases",
                    isLast: true,
                    onChange: { enabled in
                        Log.debug("TwitchCommandsCard: !wolfwave \(enabled ? "enabled" : "disabled")", category: "Twitch")
                    },
                    extra: { wolfwaveReply }
                )
            }
            .cardStyleUnpadded()
            .disabled(!twitchReady)

            HintRow("Cooldowns don't apply to you or your mods.")
        }
        .onAppear { probeMusicPermission() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            probeMusicPermission()
        }
    }

    // MARK: - Music Permission

    /// Refreshes ``musicPermission`` with a live Apple Events probe. The probe is
    /// the documented tens-of-millisecond call, so it runs detached to keep the
    /// main thread free; the result is applied back on the main actor.
    private func probeMusicPermission() {
        Task {
            let state = await Task.detached(priority: .userInitiated) {
                MusicPermissionChecker.currentState()
            }.value
            musicPermission = state
        }
    }

    // MARK: - WolfWave Reply

    /// The `!wolfwave` reply-style picker plus a live preview of the exact chat
    /// message. Rendered in the command row's `extra` slot when the command is
    /// on; the surrounding ``CommandSettingRow`` owns the padding and divider.
    @ViewBuilder
    private var wolfwaveReply: some View {
        VStack(alignment: .leading, spacing: DSSpace.s2) {
            HStack(spacing: DSSpace.s2) {
                Text("Reply")
                    .sectionEyebrow()
                Spacer()
                Picker("Reply style", selection: $wolfwaveReplyStyle) {
                    ForEach(WolfWaveReplyStyle.allCases) { style in
                        Text(style.label).tag(style.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(maxWidth: AppConstants.SettingsUI.inlineFieldMaxWidth)
                .accessibilityLabel("WolfWave reply style")
                .accessibilityIdentifier("wolfwaveReplyStyle")
            }

            // Live preview of exactly what viewers will see in chat. Labelled so
            // it reads as a sample, not an editable field.
            VStack(alignment: .leading, spacing: DSSpace.s1) {
                Text("Example reply")
                    .sectionEyebrow()

                Text(selectedWolfwaveMessage)
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Example reply preview")
        }
    }
}

// MARK: - Preview

#Preview("Twitch Commands") {
    let connected = TwitchViewModel()
    connected.channelConnected = true
    return TwitchCommandsCard(viewModel: connected)
        .padding()
        .frame(width: 700)
}

#Preview("Twitch Commands - Not Connected") {
    TwitchCommandsCard(viewModel: TwitchViewModel())
        .padding()
        .frame(width: 700)
}

#Preview("Twitch Commands - Sign-in Expired") {
    let expired = TwitchViewModel()
    expired.reauthNeeded = true
    return TwitchCommandsCard(viewModel: expired)
        .padding()
        .frame(width: 700)
}
