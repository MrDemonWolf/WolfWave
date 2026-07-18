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

    /// The setup gate. Until this is true the master toggle is replaced by a
    /// "Set up Song Requests" call to action that launches the guided sheet.
    @AppStorage(AppConstants.UserDefaults.songRequestSetupComplete)
    private var setupComplete = false

    /// Playlist health. Anything other than `.ok` shows the top-of-pane banner.
    @AppStorage(AppConstants.UserDefaults.songRequestPlaylistStatus)
    private var playlistStatus: PlaylistSetupStatus = .ok

    @State private var isTwitchConnected = false
    /// Mirrors the Twitch pane's reauth flag so this pane can surface the same
    /// "sign-in expired" warning instead of the calmer "connect" info note.
    @State private var twitchReauthNeeded = UserDefaults.standard.bool(
        forKey: AppConstants.UserDefaults.twitchReauthNeeded)

    /// Drives the guided setup sheet. `setupStartStep` lets the broken-playlist
    /// banner jump straight to the right step (re-share vs full redo).
    @State private var showSetupSheet = false
    @State private var setupStartStep: SongRequestSetupViewModel.Step = .intro

    private var appDelegate: AppDelegate? { AppDelegate.shared }

    // MARK: - Body

    /// One plain scrollable column, matching the Twitch/Discord/Notifications
    /// panes. The explainer + master toggle always show; the rest of the
    /// configuration unfolds below only once the feature is on. (There used to be
    /// a second in-pane side-nav rail here, which read as a confusing nested
    /// sidebar next to the main settings sidebar.)
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpace.s8) {
                // Broken-playlist banner sits above everything so a "needs setup
                // again" state is the first thing the streamer sees.
                if playlistStatus != .ok {
                    SongRequestHealthBanner(
                        status: playlistStatus,
                        onAction: { handleHealthAction(playlistStatus) }
                    )
                }

                SongRequestHeader()
                twitchNotice
                SongRequestMasterToggleCard(
                    isTwitchConnected: isTwitchConnected,
                    setupComplete: setupComplete,
                    onSetUp: { openSetup(at: .intro) }
                )

                // Vote-skip skips the live Apple Music track even with no request
                // queue, so it stays reachable whether or not song requests are on.
                VoteSkipCard()

                // The configuration cards only appear once setup is finished and
                // the feature is on. Apple Music access is handled inside the
                // setup sheet, so there's no inline auth card here anymore.
                if songRequestEnabled && setupComplete {
                    // The live queue sits up top: it's the thing you check and act
                    // on mid-stream (skip/hold/clear), so it leads. The set-once
                    // configuration cards follow below.
                    SongRequestQueueView()
                    SongRequestAccessCard()
                    SongRequestQueueConfigCard()
                    SongRequestPlaybackCard()
                    SongRequestCommandsCard(onManageLink: { openSetup(at: .shareLink) })
                    SongRequestRedemptionsCard()
                    SongRequestBlocklistCard(
                        blocklistProvider: { appDelegate?.songRequestService?.blocklist })
                }
            }
            .frame(maxWidth: AppConstants.SettingsUI.maxContentWidth, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, AppConstants.SettingsUI.contentPaddingH)
            .padding(.vertical, AppConstants.SettingsUI.contentPaddingV)
        }
        .onAppear {
            refreshTwitchState()
            refreshReauthState()
        }
        .task {
            // Verify the playlist is still present and shared when the pane opens
            // so the banner reflects reality (deleted / un-shared between visits).
            await runHealthCheck()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.twitchConnectionStateChanged)) { notification in
            if let connected = notification.isConnectedFlag {
                updateTwitchState(connected)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.twitchReauthNeededChanged)) { _ in
            refreshReauthState()
        }
        .sheet(isPresented: $showSetupSheet, onDismiss: { Task { await runHealthCheck() } }) {
            SongRequestSetupView(startAt: setupStartStep)
        }
    }

    /// Shown when Twitch isn't ready. An expired sign-in gets the orange warning
    /// (matching the Twitch pane); a never-connected state gets the calm info
    /// note. Hidden once connected (the master toggle stays disabled until then
    /// via `SongRequestMasterToggleCard`).
    private var twitchNotice: some View {
        TwitchConnectionNotice(
            isConnected: isTwitchConnected,
            reauthNeeded: twitchReauthNeeded,
            expiredMessage: "Your Twitch sign-in expired. Reconnect in Twitch settings to keep song requests working.",
            disconnectedMessage: "Connect with Twitch to enable song requests."
        )
    }

    /// Reloads the reauth flag from the shared `UserDefaults` key the Twitch view
    /// model writes, so the notice flips to the warning style the moment the
    /// token expires (or back once it's renewed).
    private func refreshReauthState() {
        twitchReauthNeeded = UserDefaults.standard.bool(
            forKey: AppConstants.UserDefaults.twitchReauthNeeded)
    }

    /// Refreshes the Twitch-connected flag from the live service so the
    /// song-request UI accurately reflects whether requests can flow in.
    private func refreshTwitchState() {
        updateTwitchState(appDelegate?.twitchService?.currentlyConnected ?? false)
    }

    /// Updates `isTwitchConnected`. Deliberately does NOT flip the persisted
    /// `songRequestEnabled` setting on disconnect: a transient drop (network
    /// blip, the service's own reconnect cycle) used to permanently turn the
    /// feature off, forcing the streamer to re-enable it by hand after every
    /// hiccup. The `twitchNotice` warning plus the master toggle's disabled
    /// state already communicate that requests can't flow while disconnected,
    /// and the feature resumes on its own once Twitch reconnects.
    ///
    /// - Parameter connected: New Twitch connection state.
    private func updateTwitchState(_ connected: Bool) {
        isTwitchConnected = connected
    }

    /// Opens the guided setup sheet at the given step.
    private func openSetup(at step: SongRequestSetupViewModel.Step) {
        setupStartStep = step
        showSetupSheet = true
    }

    /// Re-checks playlist health via the live service so the banner stays honest.
    private func runHealthCheck() async {
        await appDelegate?.songRequestService?.runSetupHealthCheck()
    }

    /// Routes the health banner's primary action to the right fix: re-grant
    /// Apple Music access inline, re-open the share step, or redo full setup.
    private func handleHealthAction(_ status: PlaylistSetupStatus) {
        switch status {
        case .ok:
            break
        case .musicAccessLost:
            Task {
                _ = await MusicAuthorization.request()
                await runHealthCheck()
            }
        case .playlistMissing:
            openSetup(at: .intro)
        case .linkUnshared:
            openSetup(at: .shareLink)
        }
    }
}

// MARK: - Health Banner

/// Top-of-pane banner shown when the requests playlist is broken. Pairs the
/// `PlaylistSetupStatus` message with a primary action button (CalloutBanner is
/// text-only), so the streamer can jump straight to the fix.
fileprivate struct SongRequestHealthBanner: View {
    let status: PlaylistSetupStatus
    let onAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s2) {
            CalloutBanner(
                status.bannerMessage ?? "",
                style: status.isError ? .error : .warning
            )
            if let label = status.actionLabel {
                Button(label) { onAction() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityIdentifier("songRequests.healthBanner.action")
            }
        }
        .accessibilityIdentifier("songRequests.healthBanner")
    }
}

// MARK: - Header

fileprivate struct SongRequestHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s1h) {
            SectionHeaderWithStatus(
                title: "Song Requests",
                subtitle: "Let your Twitch viewers request songs via chat commands.",
                statusText: "Twitch",
                statusColor: .purple
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

    // Lives here, not in the commands card, so it stays reachable when the
    // feature is off, which is exactly when it takes effect.
    @AppStorage(AppConstants.UserDefaults.songRequestDisabledReplyEnabled)
    private var disabledReplyEnabled = false

    let isTwitchConnected: Bool
    /// When false, the enable toggle is replaced by a "Set up" call to action.
    let setupComplete: Bool
    /// Launches the guided setup sheet.
    let onSetUp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            if setupComplete {
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

                Button("Re-run setup") { onSetUp() }
                    .buttonStyle(.plain)
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.secondary)
                    .pointerCursor()
                    .accessibilityIdentifier("songRequests.rerunSetup")
            } else {
                VStack(alignment: .leading, spacing: DSSpace.s3) {
                    HStack(spacing: DSSpace.s3) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: DSFont.Size.x2xl))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: DSSpace.s0) {
                            Text("Set up Song Requests")
                                .font(.system(size: DSFont.Size.base, weight: .semibold))
                            Text("A quick guided setup. About a minute.")
                                .font(.system(size: DSFont.Size.sm))
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: DSSpace.s1) {
                        setupChecklistItem("Connect Twitch")
                        setupChecklistItem("Allow Apple Music access")
                        setupChecklistItem("Create your requests playlist")
                    }

                    Button("Set Up Song Requests") { onSetUp() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(!isTwitchConnected)
                        .pointerCursor()
                        .accessibilityIdentifier("songRequests.setUp")
                }
            }

            Divider()

            ToggleSettingRow(
                title: "Reply When Off",
                subtitle: "Tell chat \u{201C}Song requests are off right now.\u{201D} when someone uses !sr while the feature is off. Default: stay silent.",
                isOn: $disabledReplyEnabled,
                accessibilityLabel: "Reply when song requests are off",
                accessibilityIdentifier: "songRequests.disabledReply"
            )
        }
        .cardStyle()
    }

    /// One "what you'll set up" bullet in the pre-setup call to action.
    @ViewBuilder
    private func setupChecklistItem(_ text: String) -> some View {
        HStack(spacing: DSSpace.s2) {
            Image(systemName: "circle.dashed")
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.secondary)
        }
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
            Text("Chat Vote-Skip").sectionHeader()

            Text("Let your Twitch chat vote to skip the current song. Skips the request queue when one is playing, otherwise it skips the current Apple Music track.")
                .fieldSubtitle()
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
                    CommandAliasField(
                        aliases: $commandAliases,
                        placeholder: "e.g. skipvote, sv",
                        accessibilityLabel: "Vote-skip command aliases",
                        accessibilityIdentifier: "voteSkip.commandAliases"
                    )
                }
            }
        }
        .cardStyle()
    }
}

// MARK: - Queue Config

fileprivate struct SongRequestQueueConfigCard: View {
    @AppStorage(AppConstants.UserDefaults.songRequestMaxQueueSize)
    private var maxQueueSize = 10

    // Per-role limits. "Everyone" reuses the original per-user-limit key so
    // existing setups keep their value.
    @AppStorage(AppConstants.UserDefaults.songRequestPerUserLimit)
    private var everyoneLimit = 2
    @AppStorage(AppConstants.UserDefaults.songRequestLimitSubscriber)
    private var subLimit = 2
    @AppStorage(AppConstants.UserDefaults.songRequestLimitVIP)
    private var vipLimit = 2
    @AppStorage(AppConstants.UserDefaults.songRequestLimitModerator)
    private var modLimit = 2

    @AppStorage(AppConstants.UserDefaults.songRequestLimitStackMode)
    private var stackMode: QueueLimitMode = .highest

    @AppStorage(AppConstants.UserDefaults.songRequestFairShare)
    private var fairShare = true

    private let limitOptions = [1, 2, 3, 5, 10, 15, 20]

    /// One labelled per-role limit stepper row.
    @ViewBuilder
    private func limitRow(_ title: String, selection: Binding<Int>, id: String) -> some View {
        HStack {
            Text(title).font(.system(size: DSFont.Size.body))
            Spacer()
            Picker("", selection: selection) {
                ForEach(limitOptions, id: \.self) { limit in
                    Text("\(limit)").tag(limit)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 80)
            .accessibilityLabel("\(title) queue limit")
            .accessibilityIdentifier("songRequests.limit.\(id)")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            Text("Queue Settings")
                .font(.system(size: DSFont.Size.base, weight: .semibold))

            ToggleSettingRow(
                title: "Fair-Share Ordering",
                subtitle: "Round-robin so everyone's first request plays before anyone's second. Off = classic first-in, first-out.",
                isOn: $fairShare,
                accessibilityLabel: "Fair-share round-robin ordering",
                accessibilityIdentifier: "songRequests.fairShare"
            )

            Divider()

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
                .accessibilityLabel("Max queue size")
            }

            Divider()

            VStack(alignment: .leading, spacing: DSSpace.s1h) {
                Text("Per-user limits")
                    .font(.system(size: DSFont.Size.body, weight: .medium))
                Text("How many songs each viewer can have queued at once, by role.")
                    .font(.system(size: DSFont.Size.xs))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            limitRow("Everyone", selection: $everyoneLimit, id: "everyone")
            limitRow("Subscribers", selection: $subLimit, id: "subscriber")
            limitRow("VIPs", selection: $vipLimit, id: "vip")
            limitRow("Moderators", selection: $modLimit, id: "moderator")

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: DSSpace.s0) {
                    Text("When a viewer has more than one role")
                        .font(.system(size: DSFont.Size.body))
                    Text(stackMode.summary)
                        .font(.system(size: DSFont.Size.xs))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Picker("", selection: $stackMode) {
                    ForEach(QueueLimitMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)
                .accessibilityLabel("How role limits combine")
                .accessibilityIdentifier("songRequests.limitStackMode")
            }
        }
        .cardStyle()
    }
}

// MARK: - Access (Who Can Request)

fileprivate struct SongRequestAccessCard: View {
    @AppStorage(AppConstants.UserDefaults.songRequestChatAudience)
    private var audience: RequestAudience = .everyone

    // The active chip is stored explicitly, so observing the mode key is enough
    // to refresh the highlight (and to show/hide the audience dropdown).
    @AppStorage(AppConstants.UserDefaults.songRequestPolicyMode)
    private var policyMode: SongRequestPreset = .open

    // Redemption toggles, surfaced inline under Open / Custom. These bind to the
    // same keys as the Channel Points & Bits card, so the two stay in sync; that
    // card keeps the detailed settings (cost, minimum bits, reward ID).
    @AppStorage(AppConstants.UserDefaults.songRequestChannelPointsEnabled)
    private var channelPointsEnabled = false
    @AppStorage(AppConstants.UserDefaults.songRequestBitsEnabled)
    private var bitsEnabled = false
    @AppStorage(AppConstants.UserDefaults.songRequestBitsBoostEnabled)
    private var bitsBoostEnabled = false

    /// Screening: hold every request for approval before it queues.
    @AppStorage(AppConstants.UserDefaults.songRequestApprovalRequired)
    private var approvalRequired = false

    private var activePreset: SongRequestPreset { SongRequestPreset.current() }

    /// Applies a preset and re-evaluates redemption subscriptions (presets flip
    /// the channel-point / bit toggles, so the managed reward must be reconciled).
    private func apply(_ preset: SongRequestPreset) {
        preset.apply()
        refreshRedemptions()
    }

    /// Reconciles the managed Twitch reward / EventSub subscriptions after a
    /// channel-point or bit toggle changes.
    private func refreshRedemptions() {
        if let service = AppDelegate.shared?.twitchService {
            Task { await service.refreshRedemptionSubscriptions() }
        }
    }

    /// One preset chip. Filled when it's the active policy, outlined otherwise.
    @ViewBuilder
    private func presetButton(_ preset: SongRequestPreset) -> some View {
        let isActive = activePreset == preset
        let label = Text(preset.displayName)
            .font(.system(size: DSFont.Size.sm, weight: isActive ? .semibold : .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)

        Group {
            if isActive {
                Button { apply(preset) } label: { label }
                    .buttonStyle(.borderedProminent)
            } else {
                Button { apply(preset) } label: { label }
                    .buttonStyle(.bordered)
            }
        }
        .controlSize(.small)
        .accessibilityIdentifier("songRequests.preset.\(preset.rawValue)")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            Text("Who Can Request")
                .font(.system(size: DSFont.Size.base, weight: .semibold))

            Text("Pick a preset, or choose Custom to fine-tune who can use the !sr command.")
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.secondary)

            // Preset chips. The active one is filled (borderedProminent) so the
            // current request policy reads at a glance; the rest stay outlined.
            HStack(spacing: DSSpace.s1h) {
                ForEach(SongRequestPreset.allCases) { preset in
                    presetButton(preset)
                }
            }

            HStack(alignment: .top, spacing: DSSpace.s1h) {
                Image(systemName: activePreset == .custom ? "slider.horizontal.3" : "checkmark.circle.fill")
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(activePreset == .custom ? Color.secondary : DSColor.success)
                // Markdown bolds the active preset name (a plain string literal is
                // a LocalizedStringKey, so ** renders).
                Text("**\(activePreset.displayName):** \(activePreset.summary)")
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Screening applies to every request path (chat, points, bits), so it
            // sits above the per-preset controls and shows for all presets.
            Divider()

            ToggleSettingRow(
                title: "Require My Approval",
                subtitle: "Requests wait in the Queue tab until you approve or decline them.",
                isOn: $approvalRequired,
                accessibilityLabel: "Require approval before requests queue",
                accessibilityIdentifier: "songRequests.access.requireApproval"
            )

            // Open and Custom expose the request-path options inline. Sub Only and
            // Channel Point Only are fixed policies, so they show no extra controls.
            if activePreset == .open || activePreset == .custom {
                Divider()

                // The audience dropdown is the fine-tune control, so it only
                // appears under Custom. Open is always "everyone".
                if activePreset == .custom {
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

                    Divider()
                }

                ToggleSettingRow(
                    title: "Channel Point Requests",
                    subtitle: "Viewers redeem the \u{201C}Request a Song\u{201D} reward",
                    isOn: $channelPointsEnabled,
                    accessibilityLabel: "Enable channel point song requests",
                    accessibilityIdentifier: "songRequests.access.channelPoints",
                    onChange: { _ in refreshRedemptions() }
                )

                ToggleSettingRow(
                    title: "Bit Requests",
                    subtitle: "Viewers cheer with a song name to request it",
                    isOn: $bitsEnabled,
                    accessibilityLabel: "Enable bit song requests",
                    accessibilityIdentifier: "songRequests.access.bits",
                    onChange: { _ in refreshRedemptions() }
                )

                if bitsEnabled {
                    ToggleSettingRow(
                        title: "Boost With Bits",
                        subtitle: "A cheer bumps the cheerer's queued song to the front instead of adding a new one",
                        isOn: $bitsBoostEnabled,
                        accessibilityLabel: "Boost queued song with bits",
                        accessibilityIdentifier: "songRequests.access.bitsBoost"
                    )
                }

                if channelPointsEnabled || bitsEnabled {
                    Text("Set the reward cost and minimum bits in Channel Points & Bits below.")
                        .font(.system(size: DSFont.Size.xs))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                            : StreamerMode.mask(rewardID, style: .channel, isOn: streamerMode))
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

    @AppStorage(AppConstants.UserDefaults.songListCommandEnabled) private var songListCommandEnabled = false
    @AppStorage(AppConstants.UserDefaults.songListCommandAliases) private var songListAliases = ""
    @AppStorage(AppConstants.UserDefaults.songRequestSongListURL) private var songListURL = ""

    /// Opens the setup sheet's share step so the streamer can (re)configure the
    /// public !playlist link without leaving the pane.
    let onManageLink: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            VStack(alignment: .leading, spacing: DSSpace.s1h) {
                Text("Song Request Commands").sectionHeader()

                Text("Toggle commands on/off and add custom aliases (comma-separated, without !).")
                    .fieldSubtitle()
            }

            VStack(spacing: 1) {
                CommandSettingRow(
                    title: "!sr Command",
                    triggers: "!sr  ·  !request  ·  !songrequest",
                    isOn: $srCommandEnabled,
                    accessibilityLabel: "Enable song request command",
                    accessibilityIdentifier: "srCommandToggle",
                    cooldown: .init(global: $globalCooldown, user: $userCooldown),
                    aliases: $srAliases,
                    aliasPlaceholder: "e.g. play, add",
                    aliasAccessibilityIdentifier: "srCommandAliases"
                )

                CommandSettingRow(
                    title: "!queue Command",
                    triggers: "!queue  ·  !songlist  ·  !requests",
                    isOn: $queueCommandEnabled,
                    accessibilityLabel: "Enable queue command",
                    accessibilityIdentifier: "queueCommandToggle",
                    aliases: $queueAliases,
                    aliasPlaceholder: "e.g. play, add",
                    aliasAccessibilityIdentifier: "queueCommandAliases"
                )

                CommandSettingRow(
                    title: "!myqueue Command",
                    triggers: "!myqueue  ·  !mysongs",
                    isOn: $myQueueCommandEnabled,
                    accessibilityLabel: "Enable my queue command",
                    accessibilityIdentifier: "myQueueCommandToggle",
                    aliases: $myQueueAliases,
                    aliasPlaceholder: "e.g. play, add",
                    aliasAccessibilityIdentifier: "myQueueCommandAliases"
                )

                CommandSettingRow(
                    title: "!skip Command",
                    triggers: "!skip  ·  !next  (mod only)",
                    isOn: $skipCommandEnabled,
                    accessibilityLabel: "Enable skip command",
                    accessibilityIdentifier: "skipCommandToggle",
                    aliases: $skipAliases,
                    aliasPlaceholder: "e.g. play, add",
                    aliasAccessibilityIdentifier: "skipCommandAliases"
                )

                CommandSettingRow(
                    title: "!clearqueue Command",
                    triggers: "!clearqueue  ·  !cq  (mod only)",
                    isOn: $clearQueueCommandEnabled,
                    accessibilityLabel: "Enable clear queue command",
                    accessibilityIdentifier: "clearQueueCommandToggle",
                    aliases: $clearQueueAliases,
                    aliasPlaceholder: "e.g. play, add"
                )

                CommandSettingRow(
                    title: "!playlist Command",
                    triggers: "!playlist  ·  links your request playlist",
                    isOn: $songListCommandEnabled,
                    accessibilityLabel: "Enable playlist link command",
                    accessibilityIdentifier: "songListCommandToggle",
                    aliases: $songListAliases,
                    aliasPlaceholder: "e.g. list, amplaylist",
                    aliasAccessibilityIdentifier: "songListCommandAliases",
                    isLast: true
                )
            }
            .cardStyleUnpadded()

            // Slim song-list link status. The full guided flow (open in Music,
            // share, fetch the link) now lives in the setup sheet; this row just
            // shows whether a link is set and offers a way back into that step.
            VStack(alignment: .leading, spacing: DSSpace.s2) {
                HStack {
                    Text("Song list link")
                        .font(.system(size: DSFont.Size.body, weight: .medium))
                    Spacer()
                    StatusChip(
                        text: songListURL.isEmpty ? "Needs setup" : "Ready",
                        color: songListURL.isEmpty ? Color.secondary : .green,
                        systemImage: songListURL.isEmpty
                            ? StatusChip.StateGlyph.off
                            : StatusChip.StateGlyph.on
                    )
                    Button("Manage") { onManageLink() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("songRequests.manageSongList")
                }

                Text("!playlist drops a link to your requests playlist in chat. Set it up in the guided steps.")
                    .font(.system(size: DSFont.Size.xs))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
                .accessibilityLabel("Blocklist entry type")
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

// MARK: - Preview

#Preview("Song Request Settings") {
    SongRequestSettingsView()
        .padding()
        .frame(width: 700)
}
