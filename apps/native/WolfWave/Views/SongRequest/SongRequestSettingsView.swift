//
//  SongRequestSettingsView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import MusicKit
import SwiftUI

/// Settings view for the song request system.
///
/// Decomposed into per-card subviews so each `@AppStorage` change only re-renders one card
/// instead of the whole screen.
struct SongRequestSettingsView: View {
    @AppStorage(AppConstants.UserDefaults.songRequestEnabled)
    private var songRequestEnabled = false

    @State private var isTwitchConnected = false
    @State private var musicAuthStatus: MusicAuthorization.Status = MusicAuthorization.currentStatus
    @State private var isRequestingMusicAuth = false

    @State private var selectedTab: RequestTab = .overview

    /// In-pane sections, surfaced as a segmented control so the long
    /// configuration splits into focused groups instead of one long scroll.
    private enum RequestTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case access = "Access"
        case queue = "Queue"
        case commands = "Commands"
        case points = "Points"
        var id: String { rawValue }
    }

    private var appDelegate: AppDelegate? { AppDelegate.shared }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s8) {
            SongRequestHeader()

            if !isTwitchConnected {
                CalloutBanner(
                    "Connect with Twitch to enable song requests.",
                    style: .info,
                    systemImage: "lock.fill"
                )
            }

            SongRequestMasterToggleCard(isTwitchConnected: isTwitchConnected)

            if songRequestEnabled {
                Picker("Section", selection: $selectedTab) {
                    ForEach(RequestTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("songRequestTabPicker")

                tabContent
            }
        }
        .onAppear {
            musicAuthStatus = MusicAuthorization.currentStatus
            refreshTwitchState()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.twitchConnectionStateChanged)) { notification in
            if let connected = notification.isConnectedFlag {
                updateTwitchState(connected)
            }
        }
    }

    /// The card stack for the selected tab. Each card is the same component the
    /// page used before; only their grouping into tabs is new.
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            if musicAuthStatus != .authorized {
                SongRequestMusicAuthCard(
                    musicAuthStatus: $musicAuthStatus,
                    isRequestingMusicAuth: $isRequestingMusicAuth
                )
            }
            SongRequestQueueView()
        case .access:
            SongRequestAccessCard()
            VoteSkipCard()
        case .queue:
            SongRequestQueueConfigCard()
            SongRequestPlaybackCard()
            SongRequestBlocklistCard(blocklistProvider: { appDelegate?.songRequestService?.blocklist })
        case .commands:
            SongRequestCommandsCard()
        case .points:
            SongRequestRedemptionsCard()
        }
    }

    /// Refreshes the Twitch-connected flag from the live service so the
    /// song-request UI accurately reflects whether requests can flow in.
    private func refreshTwitchState() {
        updateTwitchState(appDelegate?.twitchService?.isConnectedSnapshot.value ?? false)
    }

    /// Updates `isTwitchConnected` and, if Twitch just disconnected while
    /// requests are still enabled, switches the feature off and notifies
    /// listeners. Keeps the UI from showing "Requests enabled" without a
    /// chat connection that can deliver them.
    ///
    /// - Parameter connected: New Twitch connection state.
    private func updateTwitchState(_ connected: Bool) {
        isTwitchConnected = connected
        if !connected && songRequestEnabled {
            songRequestEnabled = false
            NotificationCenter.default.postEnabled(.songRequestSettingChanged, enabled: false)
        }
    }
}

// MARK: - Header

fileprivate struct SongRequestHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s1h) {
            SectionHeaderWithStatus(
                title: "Song Requests",
                subtitle: "Let your Twitch viewers request songs via chat commands."
            )

            CalloutBanner(
                "Viewers type **!sr song name** in your Twitch chat. WolfWave finds the song on Apple Music and adds it to the queue. Songs play one by one in your Music.app. No window pops up, it just plays quietly in the background. You stay in control: use **!skip** to jump to the next song, or **!clearqueue** to wipe the queue. Only you and your mods can skip or clear.",
                title: "How it works",
                style: .info
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Song Requests settings. Let your Twitch viewers request songs via chat commands.")
        .accessibilityIdentifier("songRequests.header")
    }
}

// MARK: - Master Toggle

fileprivate struct SongRequestMasterToggleCard: View {
    @AppStorage(AppConstants.UserDefaults.songRequestEnabled)
    private var songRequestEnabled = false

    let isTwitchConnected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            ToggleSettingRow(
                title: "Enable Song Requests",
                subtitle: "Viewers can request songs with !sr in Twitch chat",
                isOn: $songRequestEnabled,
                isDisabled: !isTwitchConnected,
                accessibilityLabel: "Enable song requests",
                accessibilityIdentifier: "songRequests.enableToggle",
                onChange: { enabled in
                    NotificationCenter.default.postEnabled(.songRequestSettingChanged, enabled: enabled)
                }
            )
        }
        .cardStyle()
    }
}

// MARK: - Chat Vote-Skip

fileprivate struct VoteSkipCard: View {
    @AppStorage(AppConstants.UserDefaults.voteSkipEnabled)
    private var voteSkipEnabled = false

    @AppStorage(AppConstants.UserDefaults.voteSkipMinVotes)
    private var minVotes = 3

    @AppStorage(AppConstants.UserDefaults.voteSkipWindowSeconds)
    private var windowSeconds = 60

    @AppStorage(AppConstants.UserDefaults.voteSkipSessionCooldown)
    private var sessionCooldown: Double = 30

    @AppStorage(AppConstants.UserDefaults.voteSkipSubscriberOnly)
    private var subscriberOnly = false

    @AppStorage(AppConstants.UserDefaults.voteSkipUsePolls)
    private var usePolls = false

    @AppStorage(AppConstants.UserDefaults.voteSkipPollDuration)
    private var pollDuration = 60

    @AppStorage(AppConstants.UserDefaults.voteSkipCommandEnabled)
    private var commandEnabled = true

    @AppStorage(AppConstants.UserDefaults.voteSkipCommandAliases)
    private var commandAliases = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            voteSkipHeader
            voteSkipCard
        }
    }

    private var voteSkipHeader: some View {
        VStack(alignment: .leading, spacing: DSSpace.s1h) {
            Text("Chat Vote-Skip").sectionSubHeader()

            Text("Let your Twitch chat vote to skip the current song. Skips the request queue when one is playing, otherwise it skips the current Apple Music track.")
                .font(.system(size: DSFont.Size.base))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var voteSkipCard: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            ToggleSettingRow(
                title: "Enable Vote-Skip",
                subtitle: "Viewers vote with !voteskip in Twitch chat",
                isOn: $voteSkipEnabled,
                accessibilityLabel: "Enable vote-skip",
                accessibilityIdentifier: "voteSkip.enableToggle"
            )

            if voteSkipEnabled {
                Divider()

                HStack {
                    Text("Minimum votes to skip").font(.system(size: DSFont.Size.body))
                    Spacer()
                    Picker("", selection: $minVotes) {
                        ForEach([2, 3, 5, 7, 10], id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 80)
                    .accessibilityLabel("Minimum votes to skip")
                }

                ToggleSettingRow(
                    title: "Subscriber-Only Voting",
                    subtitle: "Only subscribers can cast skip votes",
                    isOn: $subscriberOnly,
                    accessibilityLabel: "Subscriber-only voting",
                    accessibilityIdentifier: "voteSkip.subscriberOnly"
                )

                ToggleSettingRow(
                    title: "Use Twitch Polls",
                    subtitle: "Affiliate/Partner only. Shows a native poll on stream instead of a chat tally",
                    isOn: $usePolls,
                    accessibilityLabel: "Use Twitch polls for vote-skip",
                    accessibilityIdentifier: "voteSkip.usePolls"
                )

                if usePolls {
                    HStack {
                        Text("Poll duration").font(.system(size: DSFont.Size.body))
                        Spacer()
                        Picker("", selection: $pollDuration) {
                            ForEach([30, 60, 90, 120, 180, 300], id: \.self) { seconds in
                                Text("\(seconds)s").tag(seconds)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 80)
                        .accessibilityLabel("Poll duration")
                    }

                    HintRow("Turning this on may ask you to sign in to Twitch again to grant poll permission.")
                } else {
                    Divider()

                    VStack(alignment: .leading, spacing: DSSpace.s0) {
                        Text("Vote window: \(windowSeconds)s")
                            .font(.system(size: DSFont.Size.sm))
                            .foregroundStyle(.secondary)
                        Picker("", selection: $windowSeconds) {
                            ForEach([30, 60, 90, 120], id: \.self) { seconds in
                                Text("\(seconds)s").tag(seconds)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Vote window in seconds")
                    }

                    VStack(alignment: .leading, spacing: DSSpace.s0) {
                        Text("Cooldown between votes: \(Int(sessionCooldown))s")
                            .font(.system(size: DSFont.Size.sm))
                            .foregroundStyle(.secondary)
                        Slider(value: $sessionCooldown, in: 0...120, step: 15)
                            .controlSize(.small)
                            .accessibilityLabel("Cooldown between votes")
                            .accessibilityValue("\(Int(sessionCooldown)) seconds")
                    }
                }

                Divider()

                ToggleSettingRow(
                    title: "!voteskip Command",
                    subtitle: "!voteskip  ·  !vs",
                    isOn: $commandEnabled,
                    accessibilityLabel: "Enable vote-skip command",
                    accessibilityIdentifier: "voteSkip.commandToggle"
                )

                if commandEnabled {
                    HStack(spacing: DSSpace.s2) {
                        Text("Custom aliases:")
                            .font(.system(size: DSFont.Size.sm))
                            .foregroundStyle(.tertiary)
                        TextField("e.g. skipvote, sv", text: $commandAliases)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: DSFont.Size.sm))
                            .frame(maxWidth: 200)
                            .accessibilityLabel("Vote-skip command aliases")
                    }
                }
            }
        }
        .cardStyle()
    }
}

// MARK: - Music Auth

fileprivate struct SongRequestMusicAuthCard: View {
    @Binding var musicAuthStatus: MusicAuthorization.Status
    @Binding var isRequestingMusicAuth: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            CalloutBanner(musicAuthStatus == .denied
                ? "Apple Music access was denied. Enable it in System Settings → Privacy & Security → Media & Apple Music."
                : "WolfWave needs Apple Music access to search and play requested songs.")

            if musicAuthStatus != .denied {
                Button {
                    isRequestingMusicAuth = true
                    Task {
                        _ = await MusicAuthorization.request()
                        musicAuthStatus = MusicAuthorization.currentStatus
                        isRequestingMusicAuth = false
                    }
                } label: {
                    HStack(spacing: DSSpace.s1h) {
                        if isRequestingMusicAuth {
                            ProgressView().controlSize(.small)
                        }
                        Text("Grant Apple Music Access")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.pink)
                .disabled(isRequestingMusicAuth)
            }
        }
        .cardStyle()
    }
}

// MARK: - Queue Config

fileprivate struct SongRequestQueueConfigCard: View {
    @AppStorage(AppConstants.UserDefaults.songRequestMaxQueueSize)
    private var maxQueueSize = 10

    @AppStorage(AppConstants.UserDefaults.songRequestPerUserLimit)
    private var perUserLimit = 2

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            Text("Queue Settings")
                .font(.system(size: DSFont.Size.base, weight: .semibold))

            HStack {
                Text("Max queue size").font(.system(size: DSFont.Size.body))
                Spacer()
                Picker("", selection: $maxQueueSize) {
                    ForEach([5, 10, 15, 20, 25, 50], id: \.self) { size in
                        Text("\(size)").tag(size)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 80)
            }

            HStack {
                Text("Per-user limit").font(.system(size: DSFont.Size.body))
                Spacer()
                Picker("", selection: $perUserLimit) {
                    ForEach([1, 2, 3, 5, 10], id: \.self) { limit in
                        Text("\(limit)").tag(limit)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 80)
            }
        }
        .cardStyle()
    }
}

// MARK: - Access (Who Can Request)

fileprivate struct SongRequestAccessCard: View {
    @AppStorage(AppConstants.UserDefaults.songRequestChatAudience)
    private var audience: RequestAudience = .everyone

    // Observed so the active-preset highlight refreshes when any of these change.
    @AppStorage(AppConstants.UserDefaults.srCommandEnabled) private var srEnabled = true
    @AppStorage(AppConstants.UserDefaults.songRequestChannelPointsEnabled)
    private var channelPointsEnabled = false
    @AppStorage(AppConstants.UserDefaults.songRequestBitsEnabled) private var bitsEnabled = false

    private var activePreset: SongRequestPreset? { SongRequestPreset.current() }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            Text("Who Can Request")
                .font(.system(size: DSFont.Size.base, weight: .semibold))

            Text("Pick a preset, or fine-tune who can use the !sr command below.")
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.secondary)

            // Preset buttons
            HStack(spacing: DSSpace.s1h) {
                ForEach(SongRequestPreset.allCases) { preset in
                    Button {
                        preset.apply()
                        if let service = AppDelegate.shared?.twitchService {
                            Task { await service.refreshRedemptionSubscriptions() }
                        }
                    } label: {
                        Text(preset.displayName)
                            .font(.system(size: DSFont.Size.sm, weight: .medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(activePreset == preset ? Color(nsColor: .controlAccentColor) : nil)
                    .accessibilityIdentifier("songRequests.preset.\(preset.rawValue)")
                }
            }

            HStack(alignment: .top, spacing: DSSpace.s1h) {
                Image(systemName: activePreset == nil ? "slider.horizontal.3" : "checkmark.circle.fill")
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(activePreset == nil ? Color.secondary : DSColor.success)
                Text(activePreset?.summary ?? "Custom configuration.")
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: DSSpace.s0) {
                    Text("!sr command audience").font(.system(size: DSFont.Size.body))
                    Text("Mods and you can always request.")
                        .font(.system(size: DSFont.Size.xs))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Picker("", selection: $audience) {
                    ForEach(RequestAudience.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 170)
                .accessibilityIdentifier("songRequests.audience")
            }
        }
        .cardStyle()
    }
}

// MARK: - Redemptions (Channel Points & Bits)

fileprivate struct SongRequestRedemptionsCard: View {
    @AppStorage(AppConstants.UserDefaults.songRequestRedemptionStatus)
    private var redemptionStatus: RedemptionStatus = .ok

    @AppStorage(AppConstants.UserDefaults.songRequestChannelPointsEnabled)
    private var channelPointsEnabled = false
    @AppStorage(AppConstants.UserDefaults.songRequestChannelPointsCost)
    private var channelPointsCost = 500
    @AppStorage(AppConstants.UserDefaults.songRequestChannelPointsRewardID)
    private var rewardID = ""

    @AppStorage(AppConstants.UserDefaults.songRequestBitsEnabled)
    private var bitsEnabled = false
    @AppStorage(AppConstants.UserDefaults.songRequestBitsMinimum)
    private var bitsMinimum = 100
    @AppStorage(AppConstants.UserDefaults.songRequestBitsBoostEnabled)
    private var bitsBoostEnabled = false

    @AppStorage(AppConstants.UserDefaults.streamerModeEnabled)
    private var streamerMode = false

    @State private var showRecreateAlert = false

    private func refresh() {
        if let service = AppDelegate.shared?.twitchService {
            Task { await service.refreshRedemptionSubscriptions() }
        }
    }

    private func recreateReward() {
        Foundation.UserDefaults.standard.removeObject(
            forKey: AppConstants.UserDefaults.songRequestChannelPointsRewardID)
        refresh()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            Text("Channel Points & Bits")
                .font(.system(size: DSFont.Size.base, weight: .semibold))

            Text("Let viewers redeem a song with channel points or a bit cheer.")
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.secondary)

            if let banner = redemptionStatus.bannerMessage {
                CalloutBanner(banner)
                    .accessibilityIdentifier("songRequests.redemptionBanner")
            }

            // Channel Points
            ToggleSettingRow(
                title: "Channel Point Requests",
                subtitle: "WolfWave adds a \u{201C}Request a Song\u{201D} reward to your channel",
                isOn: $channelPointsEnabled,
                accessibilityLabel: "Enable channel point song requests",
                accessibilityIdentifier: "songRequests.channelPointsEnabled",
                onChange: { _ in refresh() }
            )

            if channelPointsEnabled {
                HStack {
                    Text("Reward cost").font(.system(size: DSFont.Size.body))
                    Spacer()
                    Picker("", selection: $channelPointsCost) {
                        ForEach([100, 250, 500, 1000, 2500, 5000], id: \.self) { cost in
                            Text("\(cost)").tag(cost)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 90)
                    .accessibilityIdentifier("songRequests.channelPointsCost")
                }
                .onChange(of: channelPointsCost) { _, _ in refresh() }

                Text("Failed requests (song not found, blocked, queue full) refund the points automatically.")
                    .font(.system(size: DSFont.Size.xs))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: DSSpace.s2) {
                    VStack(alignment: .leading, spacing: DSSpace.s0) {
                        Text("Managed reward ID")
                            .font(.system(size: DSFont.Size.xs))
                            .foregroundStyle(.tertiary)
                        Text(rewardID.isEmpty
                            ? "Not created yet"
                            : (streamerMode ? "\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}" : rewardID))
                            .font(.system(size: DSFont.Size.xs, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button {
                        showRecreateAlert = true
                    } label: {
                        Label("Recreate Reward", systemImage: "arrow.clockwise")
                            .font(.system(size: DSFont.Size.sm))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("songRequests.recreateReward")
                }
            }

            Divider()

            // Bits
            ToggleSettingRow(
                title: "Bit Requests",
                subtitle: "Viewers cheer with a song name to request it",
                isOn: $bitsEnabled,
                accessibilityLabel: "Enable bit song requests",
                accessibilityIdentifier: "songRequests.bitsEnabled",
                onChange: { _ in refresh() }
            )

            if bitsEnabled {
                HStack {
                    Text("Minimum bits").font(.system(size: DSFont.Size.body))
                    Spacer()
                    Picker("", selection: $bitsMinimum) {
                        ForEach([1, 50, 100, 200, 500, 1000], id: \.self) { amount in
                            Text("\(amount)").tag(amount)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 90)
                    .accessibilityIdentifier("songRequests.bitsMinimum")
                }

                ToggleSettingRow(
                    title: "Boost With Bits",
                    subtitle: "A cheer bumps the cheerer's queued song to the front instead of adding a new one",
                    isOn: $bitsBoostEnabled,
                    accessibilityLabel: "Boost queued song with bits",
                    accessibilityIdentifier: "songRequests.bitsBoost"
                )
            }
        }
        .cardStyle()
        .alert("Recreate Channel Point reward?", isPresented: $showRecreateAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Recreate", role: .destructive) { recreateReward() }
        } message: {
            Text("Clears the stored reward ID so WolfWave will create a fresh \u{201C}Request a Song\u{201D} reward on Twitch. Use this if you deleted the reward manually.")
        }
    }
}

// MARK: - Playback

fileprivate struct SongRequestPlaybackCard: View {
    @AppStorage(AppConstants.UserDefaults.songRequestAutoAdvance)
    private var autoAdvance = true

    @AppStorage(AppConstants.UserDefaults.songRequestAutoplayWhenEmpty)
    private var autoplayWhenEmpty = true

    @AppStorage(AppConstants.UserDefaults.songRequestFallbackPlaylist)
    private var fallbackPlaylist = ""

    @AppStorage(AppConstants.UserDefaults.songRequestHoldEnabled)
    private var holdEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            Text("Playback")
                .font(.system(size: DSFont.Size.base, weight: .semibold))

            ToggleSettingRow(
                title: "Hold Queue",
                subtitle: "Requests still queue, but nothing plays until you resume",
                isOn: $holdEnabled,
                accessibilityLabel: "Hold the request queue",
                accessibilityIdentifier: "songRequests.holdEnabled",
                onChange: { enabled in
                    if let service = AppDelegate.shared?.songRequestService {
                        Task { await service.setHold(enabled) }
                    }
                }
            )

            ToggleSettingRow(
                title: "Auto-Advance Queue",
                subtitle: "Automatically play the next request when a song ends",
                isOn: $autoAdvance,
                accessibilityLabel: "Auto-advance queue",
                accessibilityIdentifier: "songRequests.autoAdvance"
            )

            ToggleSettingRow(
                title: "Resume Autoplay When Empty",
                subtitle: "Let Apple Music's autoplay take over when the queue is empty",
                isOn: $autoplayWhenEmpty,
                accessibilityLabel: "Resume autoplay when queue is empty",
                accessibilityIdentifier: "songRequests.autoplayWhenEmpty"
            )

            Divider()

            VStack(alignment: .leading, spacing: DSSpace.s1h) {
                Text("Fallback playlist")
                    .font(.system(size: DSFont.Size.body, weight: .medium))
                TextField("e.g. Gaming Vibes", text: $fallbackPlaylist)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: DSFont.Size.body))
                VStack(alignment: .leading, spacing: DSSpace.s0) {
                    Text("Plays an Apple Music playlist when the queue is empty.")
                    Text("Type the playlist name exactly as it appears in Music.")
                    Text("Leave blank for silence.")
                }
                .font(.system(size: DSFont.Size.xs))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
    }
}

// MARK: - Commands

fileprivate struct SongRequestCommandsCard: View {
    @AppStorage(AppConstants.UserDefaults.srCommandEnabled) private var srCommandEnabled = true
    @AppStorage(AppConstants.UserDefaults.queueCommandEnabled) private var queueCommandEnabled = true
    @AppStorage(AppConstants.UserDefaults.myQueueCommandEnabled) private var myQueueCommandEnabled = true
    @AppStorage(AppConstants.UserDefaults.skipCommandEnabled) private var skipCommandEnabled = true
    @AppStorage(AppConstants.UserDefaults.clearQueueCommandEnabled) private var clearQueueCommandEnabled = true

    @AppStorage(AppConstants.UserDefaults.srCommandAliases) private var srAliases = ""
    @AppStorage(AppConstants.UserDefaults.queueCommandAliases) private var queueAliases = ""
    @AppStorage(AppConstants.UserDefaults.myQueueCommandAliases) private var myQueueAliases = ""
    @AppStorage(AppConstants.UserDefaults.skipCommandAliases) private var skipAliases = ""
    @AppStorage(AppConstants.UserDefaults.clearQueueCommandAliases) private var clearQueueAliases = ""

    @AppStorage(AppConstants.UserDefaults.songRequestGlobalCooldown) private var globalCooldown: Double = 5.0
    @AppStorage(AppConstants.UserDefaults.songRequestUserCooldown) private var userCooldown: Double = 30.0

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            VStack(alignment: .leading, spacing: DSSpace.s1h) {
                Text("Song Request Commands").sectionSubHeader()

                Text("Toggle commands on/off and add custom aliases (comma-separated, without !).")
                    .font(.system(size: DSFont.Size.base))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 1) {
                CommandToggleRow(
                    title: "!sr Command",
                    subtitle: "!sr  ·  !request  ·  !songrequest",
                    isOn: $srCommandEnabled,
                    accessibilityLabel: "Enable song request command",
                    accessibilityIdentifier: "srCommandToggle",
                    isFirst: true
                )

                if srCommandEnabled {
                    CooldownRow(
                        label: "!sr cooldowns",
                        globalCooldown: $globalCooldown,
                        userCooldown: $userCooldown
                    )
                    AliasRow(aliases: $srAliases)
                }

                CommandToggleRow(
                    title: "!queue Command",
                    subtitle: "!queue  ·  !songlist  ·  !requests",
                    isOn: $queueCommandEnabled,
                    accessibilityLabel: "Enable queue command",
                    accessibilityIdentifier: "queueCommandToggle"
                )

                if queueCommandEnabled {
                    AliasRow(aliases: $queueAliases)
                }

                CommandToggleRow(
                    title: "!myqueue Command",
                    subtitle: "!myqueue  ·  !mysongs",
                    isOn: $myQueueCommandEnabled,
                    accessibilityLabel: "Enable my queue command",
                    accessibilityIdentifier: "myQueueCommandToggle"
                )

                if myQueueCommandEnabled {
                    AliasRow(aliases: $myQueueAliases)
                }

                CommandToggleRow(
                    title: "!skip Command",
                    subtitle: "!skip  ·  !next  (mod only)",
                    isOn: $skipCommandEnabled,
                    accessibilityLabel: "Enable skip command",
                    accessibilityIdentifier: "skipCommandToggle"
                )

                if skipCommandEnabled {
                    AliasRow(aliases: $skipAliases)
                }

                CommandToggleRow(
                    title: "!clearqueue Command",
                    subtitle: "!clearqueue  ·  !cq  (mod only)",
                    isOn: $clearQueueCommandEnabled,
                    accessibilityLabel: "Enable clear queue command",
                    accessibilityIdentifier: "clearQueueCommandToggle",
                    isLast: true
                )

                if clearQueueCommandEnabled {
                    AliasRow(aliases: $clearQueueAliases, isLast: true)
                }
            }
            .cardStyleUnpadded()

            HintRow("Cooldowns don't apply to you or your mods.")
        }
    }
}

// MARK: - Blocklist

fileprivate struct SongRequestBlocklistCard: View {
    let blocklistProvider: () -> SongBlocklist?

    @State private var blocklistText = ""
    @State private var blocklistType: BlocklistItem.BlockType = .song
    @State private var blocklist: [BlocklistItem] = []
    @State private var showClearAllAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            HStack {
                Text("Blocklist")
                    .font(.system(size: DSFont.Size.base, weight: .semibold))

                Spacer()

                Button(role: .destructive) {
                    showClearAllAlert = true
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(blocklist.isEmpty)
                .accessibilityIdentifier("blocklist.clearAll")
            }

            Text("Block specific songs or artists from being requested.")
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.tertiary)

            HStack(spacing: DSSpace.s2) {
                Picker("", selection: $blocklistType) {
                    Text("Song").tag(BlocklistItem.BlockType.song)
                    Text("Artist").tag(BlocklistItem.BlockType.artist)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

                TextField(blocklistType == .song ? "Song title..." : "Artist name...", text: $blocklistText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: DSFont.Size.body))

                Button("Add") {
                    let trimmed = blocklistText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let item = BlocklistItem(value: trimmed, type: blocklistType)
                    let provider = blocklistProvider()
                    blocklistText = ""
                    Task {
                        await provider?.add(item)
                        blocklist = await provider?.allEntries ?? []
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(blocklistText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !blocklist.isEmpty {
                VStack(alignment: .leading, spacing: DSSpace.s1) {
                    ForEach(blocklist) { item in
                        HStack {
                            Image(systemName: item.type == .song ? "music.note" : "person.fill")
                                .font(.system(size: DSFont.Size.xs))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)

                            Text(item.value).font(.system(size: DSFont.Size.body))

                            Text(item.type == .song ? "Song" : "Artist")
                                .font(.system(size: DSFont.Size.xs))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, DSSpace.s2)
                                .padding(.vertical, DSSpace.s0)
                                .background(.quaternary)
                                .clipShape(Capsule())

                            Spacer()

                            Button {
                                let provider = blocklistProvider()
                                Task {
                                    await provider?.remove(id: item.id)
                                    blocklist = await provider?.allEntries ?? []
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: DSFont.Size.body))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove from blocklist")
                            .accessibilityHint(item.value)
                        }
                        .padding(.vertical, DSSpace.s0)
                    }
                }
                .padding(.top, DSSpace.s1)
            }
        }
        .cardStyle()
        .task {
            blocklist = await blocklistProvider()?.allEntries ?? []
        }
        .alert("Clear blocklist?", isPresented: $showClearAllAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                let provider = blocklistProvider()
                Task {
                    await provider?.clearAll()
                    blocklist = await provider?.allEntries ?? []
                }
            }
        } message: {
            Text("This removes every entry from your song-request blocklist. This cannot be undone.")
        }
    }
}

// MARK: - Reusable rows

fileprivate struct CommandToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    var isFirst: Bool = false
    var isLast: Bool = false

    var body: some View {
        ToggleSettingRow(
            title: title,
            subtitle: subtitle,
            isOn: $isOn,
            accessibilityLabel: accessibilityLabel,
            accessibilityIdentifier: accessibilityIdentifier
        )
        .padding(.horizontal, AppConstants.SettingsUI.cardPadding)
        .padding(.vertical, DSSpace.s4)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider().padding(.leading, AppConstants.SettingsUI.cardPadding)
            }
        }
    }
}

fileprivate struct CooldownRow: View {
    let label: String
    @Binding var globalCooldown: Double
    @Binding var userCooldown: Double
    var isLast: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s2) {
            Text(label)
                .sectionEyebrow()

            HStack(spacing: DSSpace.s4) {
                VStack(alignment: .leading, spacing: DSSpace.s0) {
                    Text("Everyone: \(Int(globalCooldown))s")
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(.secondary)
                    Slider(value: $globalCooldown, in: 0...30, step: 5)
                        .controlSize(.small)
                        .accessibilityLabel("\(label) global cooldown")
                        .accessibilityValue("\(Int(globalCooldown)) seconds")
                        .accessibilityHint("Adjusts the global cooldown between 0 and 30 seconds")
                }

                VStack(alignment: .leading, spacing: DSSpace.s0) {
                    Text("Per person: \(Int(userCooldown))s")
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(.secondary)
                    Slider(value: $userCooldown, in: 0...60, step: 5)
                        .controlSize(.small)
                        .accessibilityLabel("\(label) per-user cooldown")
                        .accessibilityValue("\(Int(userCooldown)) seconds")
                        .accessibilityHint("Adjusts the per-user cooldown between 0 and 60 seconds")
                }
            }
        }
        .padding(.horizontal, AppConstants.SettingsUI.cardPadding)
        .padding(.vertical, DSSpace.s2)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider().padding(.leading, AppConstants.SettingsUI.cardPadding)
            }
        }
    }
}

fileprivate struct AliasRow: View {
    @Binding var aliases: String
    var isLast: Bool = false

    var body: some View {
        HStack(spacing: DSSpace.s2) {
            Text("Custom aliases:")
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.tertiary)
            TextField("e.g. play, add", text: $aliases)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: DSFont.Size.sm))
                .frame(maxWidth: 200)
        }
        .padding(.horizontal, AppConstants.SettingsUI.cardPadding)
        .padding(.vertical, DSSpace.s2)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider().padding(.leading, AppConstants.SettingsUI.cardPadding)
            }
        }
    }
}

// MARK: - Preview

#Preview("Song Request Settings") {
    SongRequestSettingsView()
        .padding()
        .frame(width: 700)
}
