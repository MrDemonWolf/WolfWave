//
//  SongRequestSettingsView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 4/8/26.
//

import MusicKit
import SwiftUI

/// Settings view for the song request system.
///
/// Provides controls for:
/// - Master enable/disable toggle
/// - MusicKit authorization status
/// - Queue configuration (max size, per-user limit)
/// - Subscriber-only mode
/// - Auto-advance and autoplay settings
/// - Per-command enable/disable toggles with custom aliases
/// - Song/artist blocklist management
struct SongRequestSettingsView: View {
    // MARK: - User Settings

    @AppStorage(AppConstants.UserDefaults.songRequestEnabled)
    private var songRequestEnabled = false

    @AppStorage(AppConstants.UserDefaults.songRequestMaxQueueSize)
    private var maxQueueSize = 10

    @AppStorage(AppConstants.UserDefaults.songRequestPerUserLimit)
    private var perUserLimit = 2

    @AppStorage(AppConstants.UserDefaults.songRequestSubscriberOnly)
    private var subscriberOnly = false

    @AppStorage(AppConstants.UserDefaults.songRequestAutoAdvance)
    private var autoAdvance = true

    @AppStorage(AppConstants.UserDefaults.songRequestAutoplayWhenEmpty)
    private var autoplayWhenEmpty = true

    @AppStorage(AppConstants.UserDefaults.songRequestFallbackPlaylist)
    private var fallbackPlaylist = ""

    // Per-command toggles
    @AppStorage(AppConstants.UserDefaults.srCommandEnabled)
    private var srCommandEnabled = true

    @AppStorage(AppConstants.UserDefaults.queueCommandEnabled)
    private var queueCommandEnabled = true

    @AppStorage(AppConstants.UserDefaults.myQueueCommandEnabled)
    private var myQueueCommandEnabled = true

    @AppStorage(AppConstants.UserDefaults.skipCommandEnabled)
    private var skipCommandEnabled = true

    @AppStorage(AppConstants.UserDefaults.clearQueueCommandEnabled)
    private var clearQueueCommandEnabled = true

    // Per-command aliases
    @AppStorage(AppConstants.UserDefaults.srCommandAliases)
    private var srAliases = ""

    @AppStorage(AppConstants.UserDefaults.queueCommandAliases)
    private var queueAliases = ""

    @AppStorage(AppConstants.UserDefaults.myQueueCommandAliases)
    private var myQueueAliases = ""

    @AppStorage(AppConstants.UserDefaults.skipCommandAliases)
    private var skipAliases = ""

    @AppStorage(AppConstants.UserDefaults.clearQueueCommandAliases)
    private var clearQueueAliases = ""

    // Cooldowns
    @AppStorage(AppConstants.UserDefaults.songRequestGlobalCooldown)
    private var globalCooldown: Double = 5.0

    @AppStorage(AppConstants.UserDefaults.songRequestUserCooldown)
    private var userCooldown: Double = 30.0

    // MARK: - State

    @State private var blocklistText = ""
    @State private var blocklistType: BlocklistItem.BlockType = .song
    @State private var blocklist: [BlocklistItem] = []
    @State private var isTwitchConnected = false
    @State private var musicAuthStatus: MusicAuthorization.Status = MusicAuthorization.currentStatus
    @State private var isRequestingMusicAuth = false

    private var appDelegate: AppDelegate? {
        AppDelegate.shared
    }

    private var songBlocklist: SongBlocklist? {
        appDelegate?.songRequestService?.blocklist
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text("Song Requests")
                    .sectionHeader()

                Text("Let your Twitch viewers request songs via chat commands.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.blue)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text("How it works")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Viewers type **!sr song name** in your Twitch chat. WolfWave finds the song on Apple Music and adds it to the queue. Songs play one by one in your Music.app — no window will pop up, it just plays quietly in the background. You stay in control: use **!skip** to jump to the next song, or **!clearqueue** to wipe the queue. Only you and your mods can skip or clear.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .background(.blue.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Song Requests settings. Let your Twitch viewers request songs via chat commands.")
            .accessibilityIdentifier("songRequests.header")

            // Twitch connection requirement
            if !isTwitchConnected {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("Connect to Twitch to enable song requests.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            // Master Toggle
            masterToggleCard

            if songRequestEnabled {
                // MusicKit auth prompt (if not authorized)
                if musicAuthStatus != .authorized {
                    musicAuthCard
                }

                // Queue View
                SongRequestQueueView()

                Divider().padding(.vertical, 4)

                // Queue Configuration
                queueConfigCard

                Divider().padding(.vertical, 4)

                // Playback Settings
                playbackCard

                Divider().padding(.vertical, 4)

                // Commands & Cooldowns
                commandsCard

                Divider().padding(.vertical, 4)

                // Blocklist
                blocklistCard
            }
        }
        .onAppear {
            blocklist = songBlocklist?.allEntries ?? []
            musicAuthStatus = MusicAuthorization.currentStatus
            refreshTwitchState()
            // Delayed re-check to catch late connections
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                refreshTwitchState()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name(AppConstants.Notifications.twitchConnectionStateChanged))) { notification in
            if let connected = notification.userInfo?["isConnected"] as? Bool {
                updateTwitchState(connected)
            }
        }
    }

    // MARK: - Master Toggle Card

    private var masterToggleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ToggleSettingRow(
                title: "Enable Song Requests",
                subtitle: "Viewers can request songs with !sr in Twitch chat",
                isOn: $songRequestEnabled,
                isDisabled: !isTwitchConnected,
                accessibilityLabel: "Enable song requests",
                accessibilityIdentifier: "songRequests.enableToggle",
                onChange: { enabled in
                    NotificationCenter.default.post(
                        name: NSNotification.Name(AppConstants.Notifications.songRequestSettingChanged),
                        object: nil,
                        userInfo: ["enabled": enabled]
                    )
                }
            )
        }
        .padding(AppConstants.SettingsUI.cardPadding)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))
    }

    // MARK: - MusicKit Auth Card

    private var musicAuthCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(musicAuthStatus == .denied
                     ? "Apple Music access was denied. Enable it in System Settings → Privacy & Security → Media & Apple Music."
                     : "WolfWave needs Apple Music access to search and play requested songs.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if musicAuthStatus != .denied {
                Button {
                    isRequestingMusicAuth = true
                    Task {
                        _ = await MusicAuthorization.request()
                        musicAuthStatus = MusicAuthorization.currentStatus
                        isRequestingMusicAuth = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isRequestingMusicAuth {
                            ProgressView()
                                .controlSize(.small)
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
        .padding(AppConstants.SettingsUI.cardPadding)
        .background(.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))
    }

    // MARK: - Queue Configuration Card

    private var queueConfigCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Queue Settings")
                .font(.system(size: 13, weight: .semibold))

            HStack {
                Text("Max queue size")
                    .font(.system(size: 12))
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
                Text("Per-user limit")
                    .font(.system(size: 12))
                Spacer()
                Picker("", selection: $perUserLimit) {
                    ForEach([1, 2, 3, 5, 10], id: \.self) { limit in
                        Text("\(limit)").tag(limit)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 80)
            }

            ToggleSettingRow(
                title: "Subscriber-Only Mode",
                subtitle: "Only subscribers can request songs",
                isOn: $subscriberOnly,
                accessibilityLabel: "Subscriber-only mode",
                accessibilityIdentifier: "songRequests.subscriberOnly"
            )
        }
        .padding(AppConstants.SettingsUI.cardPadding)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))
    }

    // MARK: - Playback Card

    private var playbackCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Playback")
                .font(.system(size: 13, weight: .semibold))

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

            VStack(alignment: .leading, spacing: 6) {
                Text("Fallback playlist")
                    .font(.system(size: 12, weight: .medium))
                TextField("e.g. Gaming Vibes", text: $fallbackPlaylist)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                Text("When the request queue runs out, WolfWave will start playing this Apple Music playlist so your stream isn't left in silence. Just type the exact playlist name as it appears in your Music.app library. Leave this blank if you'd rather let it be quiet.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppConstants.SettingsUI.cardPadding)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))
    }

    // MARK: - Commands Card

    private var commandsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(nsColor: .controlAccentColor))
                    Text("Song Request Commands")
                        .sectionSubHeader()
                }

                Text("Toggle commands on/off and add custom aliases (comma-separated, without !).")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 1) {
                commandToggleRow(
                    title: "!sr Command",
                    subtitle: "!sr  ·  !request  ·  !songrequest",
                    isOn: $srCommandEnabled,
                    accessibilityLabel: "Enable song request command",
                    accessibilityIdentifier: "srCommandToggle",
                    isFirst: true
                )

                if srCommandEnabled {
                    cooldownRow(
                        label: "!sr cooldowns",
                        globalCooldown: $globalCooldown,
                        userCooldown: $userCooldown
                    )

                    aliasRow(aliases: $srAliases)
                }

                commandToggleRow(
                    title: "!queue Command",
                    subtitle: "!queue  ·  !songlist  ·  !requests",
                    isOn: $queueCommandEnabled,
                    accessibilityLabel: "Enable queue command",
                    accessibilityIdentifier: "queueCommandToggle"
                )

                if queueCommandEnabled {
                    aliasRow(aliases: $queueAliases)
                }

                commandToggleRow(
                    title: "!myqueue Command",
                    subtitle: "!myqueue  ·  !mysongs",
                    isOn: $myQueueCommandEnabled,
                    accessibilityLabel: "Enable my queue command",
                    accessibilityIdentifier: "myQueueCommandToggle"
                )

                if myQueueCommandEnabled {
                    aliasRow(aliases: $myQueueAliases)
                }

                commandToggleRow(
                    title: "!skip Command",
                    subtitle: "!skip  ·  !next  (mod only)",
                    isOn: $skipCommandEnabled,
                    accessibilityLabel: "Enable skip command",
                    accessibilityIdentifier: "skipCommandToggle"
                )

                if skipCommandEnabled {
                    aliasRow(aliases: $skipAliases)
                }

                commandToggleRow(
                    title: "!clearqueue Command",
                    subtitle: "!clearqueue  ·  !cq  (mod only)",
                    isOn: $clearQueueCommandEnabled,
                    accessibilityLabel: "Enable clear queue command",
                    accessibilityIdentifier: "clearQueueCommandToggle",
                    isLast: true
                )

                if clearQueueCommandEnabled {
                    aliasRow(aliases: $clearQueueAliases, isLast: true)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))

            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("Cooldowns don't apply to you or your mods.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Blocklist Card

    private var blocklistCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Blocklist")
                .font(.system(size: 13, weight: .semibold))

            Text("Block specific songs or artists from being requested.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            HStack(spacing: 8) {
                Picker("", selection: $blocklistType) {
                    Text("Song").tag(BlocklistItem.BlockType.song)
                    Text("Artist").tag(BlocklistItem.BlockType.artist)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

                TextField(blocklistType == .song ? "Song title..." : "Artist name...", text: $blocklistText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))

                Button("Add") {
                    let trimmed = blocklistText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let item = BlocklistItem(value: trimmed, type: blocklistType)
                    songBlocklist?.add(item)
                    blocklist = songBlocklist?.allEntries ?? []
                    blocklistText = ""
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(blocklistText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !blocklist.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(blocklist) { item in
                        HStack {
                            Image(systemName: item.type == .song ? "music.note" : "person.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)

                            Text(item.value)
                                .font(.system(size: 12))

                            Text(item.type == .song ? "Song" : "Artist")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary)
                                .clipShape(Capsule())

                            Spacer()

                            Button {
                                songBlocklist?.remove(id: item.id)
                                blocklist = songBlocklist?.allEntries ?? []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(AppConstants.SettingsUI.cardPadding)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))
    }

    // MARK: - Reusable Row Helpers

    /// A toggle row for enabling/disabling a single bot command (matches SettingsView pattern).
    @ViewBuilder
    private func commandToggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        isFirst: Bool = false,
        isLast: Bool = false
    ) -> some View {
        ToggleSettingRow(
            title: title,
            subtitle: subtitle,
            isOn: isOn,
            accessibilityLabel: accessibilityLabel,
            accessibilityIdentifier: accessibilityIdentifier
        )
        .padding(.horizontal, AppConstants.SettingsUI.cardPadding)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
                    .padding(.leading, AppConstants.SettingsUI.cardPadding)
            }
        }
    }

    /// A row with global and per-user cooldown sliders (matches SettingsView pattern).
    @ViewBuilder
    private func cooldownRow(
        label: String,
        globalCooldown: Binding<Double>,
        userCooldown: Binding<Double>,
        isLast: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Everyone: \(Int(globalCooldown.wrappedValue))s")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Slider(value: globalCooldown, in: 0...30, step: 5)
                        .controlSize(.small)
                        .accessibilityLabel("\(label) global cooldown")
                        .accessibilityValue("\(Int(globalCooldown.wrappedValue)) seconds")
                        .accessibilityHint("Adjusts the global cooldown between 0 and 30 seconds")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Per person: \(Int(userCooldown.wrappedValue))s")
                        .font(.system(size: 11))
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
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
                    .padding(.leading, AppConstants.SettingsUI.cardPadding)
            }
        }
    }

    /// A row for custom command aliases.
    @ViewBuilder
    private func aliasRow(aliases: Binding<String>, isLast: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text("Custom aliases:")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            TextField("e.g. play, add", text: aliases)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .frame(maxWidth: 200)
        }
        .padding(.horizontal, AppConstants.SettingsUI.cardPadding)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
                    .padding(.leading, AppConstants.SettingsUI.cardPadding)
            }
        }
    }

    // MARK: - Twitch State Helpers

    private func refreshTwitchState() {
        let connected = appDelegate?.twitchService?.isConnected ?? false
        updateTwitchState(connected)
    }

    private func updateTwitchState(_ connected: Bool) {
        isTwitchConnected = connected
        if !connected && songRequestEnabled {
            songRequestEnabled = false
            NotificationCenter.default.post(
                name: NSNotification.Name(AppConstants.Notifications.songRequestSettingChanged),
                object: nil,
                userInfo: ["enabled": false]
            )
        }
    }
}

// MARK: - Preview

#Preview("Song Request Settings") {
    SongRequestSettingsView()
        .padding()
        .frame(width: 700)
}
