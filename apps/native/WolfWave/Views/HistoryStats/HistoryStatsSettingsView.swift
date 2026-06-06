//
//  HistoryStatsSettingsView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI
import AppKit

/// Settings pane for the opt-in Listening History & Stats feature.
///
/// Two interlocked toggles: *Listening History* records plays to disk; *Stats &
/// Charts* visualizes them and unlocks the `!stats` command. Stats can't be
/// enabled until History is on, and turning History off cascades Stats off.
struct HistoryStatsSettingsView: View {

    // MARK: - User Settings

    @AppStorage(AppConstants.UserDefaults.listeningHistoryEnabled)
    private var historyEnabled = false

    @AppStorage(AppConstants.UserDefaults.statsEnabled)
    private var statsEnabled = false

    @AppStorage(AppConstants.UserDefaults.statsCommandEnabled)
    private var statsCommandEnabled = false

    @AppStorage(AppConstants.UserDefaults.statsCommandGlobalCooldown)
    private var statsGlobalCooldown: Double = 15

    @AppStorage(AppConstants.UserDefaults.statsCommandUserCooldown)
    private var statsUserCooldown: Double = 15

    @AppStorage(AppConstants.UserDefaults.statsCommandAliases)
    private var statsCommandAliases = ""

    @AppStorage(AppConstants.UserDefaults.historyRetentionDays)
    private var historyRetentionDays = 0

    // MARK: - State

    @State private var showWrapSheet = false
    @State private var showClearAlert = false
    @State private var musicPermission: MusicPermissionState = MusicPermissionCache.read() ?? .unknown
    @State private var visibleRecentCount: Int = AppConstants.History.recentDisplayCount

    /// Which leaderboard the "Top" card is showing. Lets one card surface
    /// artists, tracks, and albums in the footprint that previously showed
    /// only artists.
    @State private var topListKind: TopListKind = .artists

    /// Source list for the segmented "Top" card.
    private enum TopListKind: String, CaseIterable, Identifiable {
        case artists, tracks, albums
        var id: String { rawValue }
        var label: String {
            switch self {
            case .artists: return "Artists"
            case .tracks: return "Tracks"
            case .albums: return "Albums"
            }
        }
    }

    /// The shared history service. Accessed as a computed property so the
    /// Observation framework tracks property reads each time `body` runs.
    private var service: ListeningHistoryService? {
        AppDelegate.shared?.historyService
    }

    private var snapshot: StatsSnapshot {
        service?.snapshot ?? .empty
    }

    /// True until `ListeningHistoryService` finishes loading from disk. Drives
    /// the `.skeleton` placeholder on derived content cards.
    private var isLoadingHistory: Bool {
        guard historyEnabled, statsEnabled else { return false }
        return service?.isLoaded == false
    }

    // MARK: - Body

    var body: some View {
        unifiedLayout
        .onAppear {
            musicPermission = MusicPermissionChecker.currentState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            musicPermission = MusicPermissionChecker.currentState()
        }
        .sheet(isPresented: $showWrapSheet) {
            if let service {
                MonthlyWrapView(service: service)
            }
        }
        .alert("Clear listening history?", isPresented: $showClearAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                service?.clearHistory()
            }
            .accessibilityIdentifier("clearHistoryConfirmButton")
        } message: {
            Text("This permanently deletes every recorded play. Can't be undone.")
        }
    }

    // MARK: - Layout

    /// One centered, width-clamped scroll column for every state. Mirrors the
    /// shell's `standardDetailScroll` geometry (the pane bypasses it to own the
    /// full detail width). The dashboard band (summary / charts / top), the
    /// `!stats` command, and the Monthly Wrap action surface inline once both
    /// features are on, so the pane reads top-to-bottom without a jump-nav rail.
    private var unifiedLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppConstants.SettingsUI.sectionSpacing) {
                intro
                permissionBanner
                togglesCard

                if !historyEnabled {
                    firstRunExplainer
                }

                // Dashboard band: lead with the insights, two columns when the
                // settings window is wide enough (collapses to a stack when not).
                // Render while the service is still loading too, so the skeleton
                // placeholders hold the band's footprint instead of popping in and
                // resizing the pane the moment disk load finishes (#281).
                if historyEnabled, statsEnabled, snapshot.hasData || isLoadingHistory {
                    ResponsiveRow {
                        summaryCard
                    } right: {
                        todaysTopTrackCard
                    }
                    .skeleton(isLoadingHistory)

                    ResponsiveRow {
                        WeekChartCard(snapshot: snapshot)
                    } right: {
                        HourChartCard(snapshot: snapshot)
                    }
                    .skeleton(isLoadingHistory)

                    topListCard
                        .skeleton(isLoadingHistory)
                }

                unifiedRecentCard
                    .skeleton(isLoadingHistory)

                if historyEnabled, statsEnabled {
                    statsCommandCard
                }

                if historyEnabled {
                    manageBlock
                    dangerCard
                }
            }
            .frame(maxWidth: AppConstants.SettingsUI.maxContentWidth, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, AppConstants.SettingsUI.contentPaddingH)
            .padding(.vertical, AppConstants.SettingsUI.contentPaddingV)
        }
    }

    /// Retention card, plus the Monthly Wrap action when Stats is on. Retention
    /// stands alone (single column) when only History is on; the actions column
    /// joins once Stats unlocks the wrap.
    @ViewBuilder
    private var manageBlock: some View {
        if statsEnabled {
            ResponsiveRow {
                retentionCard
            } right: {
                actionsCard
            }
        } else {
            retentionCard
        }
    }

    /// Apple Music automation-denied banner, shown above the toggles in both
    /// layouts when access is blocked.
    @ViewBuilder
    private var permissionBanner: some View {
        if musicPermission == .denied {
            MusicPermissionBanner(
                message: "WolfWave needs Apple Music automation access to record what you play. Enable it in System Settings → Privacy & Security → Automation."
            )
        }
    }

    // MARK: - Intro

    private var intro: some View {
        Text("WolfWave can remember what you play, kept on this Mac, never uploaded.")
            .font(.system(size: DSFont.Size.body))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Toggles

    private var togglesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ToggleSettingRow(
                title: "Listening History",
                subtitle: musicPermission == .denied
                    ? "Apple Music access required. See banner above."
                    : "Keep a private log of the tracks you play.",
                isOn: $historyEnabled,
                isDisabled: musicPermission == .denied,
                accessibilityLabel: "Toggle Listening History",
                accessibilityIdentifier: "listeningHistoryToggle",
                onChange: { handleHistoryChange($0) }
            )
            .padding(AppConstants.SettingsUI.cardPadding)

            Divider().padding(.horizontal, AppConstants.SettingsUI.cardPadding)

            ToggleSettingRow(
                title: "Stats & Charts",
                subtitle: historyEnabled
                    ? "Top artists, listening time, charts, and a monthly wrap."
                    : "Turn on Listening History first.",
                isOn: $statsEnabled,
                isDisabled: !historyEnabled || musicPermission == .denied,
                accessibilityLabel: "Toggle Stats and Charts",
                accessibilityIdentifier: "statsEnabledToggle",
                onChange: { handleStatsChange($0) }
            )
            .padding(AppConstants.SettingsUI.cardPadding)
        }
        .cardStyleUnpadded()
    }

    // MARK: - Summary

    private var summaryCard: some View {
        HStack(spacing: 0) {
            StatTile(
                value: "\(snapshot.playsThisWeek)",
                secondary: HistoryFormat.listeningTime(snapshot.listeningSecondsThisWeek),
                caption: "This week"
            )
            Divider().frame(height: 40)
            StatTile(
                value: "\(snapshot.playsToday)",
                secondary: HistoryFormat.listeningTime(snapshot.listeningSecondsToday),
                caption: "Today"
            )
            Divider().frame(height: 40)
            StatTile(
                value: "\(snapshot.totalPlays)",
                secondary: HistoryFormat.listeningTime(snapshot.totalListeningSeconds),
                caption: "All time"
            )
        }
        .frame(maxWidth: .infinity)
        .padding(AppConstants.SettingsUI.cardPadding)
        .cardStyleUnpadded()
    }

    // MARK: - Today's Top Track

    /// Highlights the single most-played track recorded today. Surfaces
    /// `snapshot.topTrackToday`, which the pane previously computed but never
    /// showed. Pairs beside the summary tiles in the dashboard band.
    private var todaysTopTrackCard: some View {
        VStack(alignment: .leading, spacing: DSSpace.s3) {
            CardEyebrowHeader("Today's top track", systemImage: "star")

            // Reserve a steady height so the card doesn't grow/shrink when the
            // single-line "nothing yet" copy is replaced by the two-line track
            // row (matters in the stacked single-column layout).
            Group {
                if let top = snapshot.topTrackToday {
                    HStack(spacing: DSSpace.s3) {
                        Image(systemName: "music.note")
                            .font(.system(size: DSFont.Size.lg))
                            .foregroundStyle(.secondary)
                            .frame(width: DSFont.Size.x2xl)
                        VStack(alignment: .leading, spacing: DSSpace.s0) {
                            Text(top.name)
                                .font(.system(size: DSFont.Size.base, weight: .medium))
                                .lineLimit(1)
                            if let detail = top.detail {
                                Text(detail)
                                    .font(.system(size: DSFont.Size.sm))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(HistoryFormat.playCount(top.count))
                            .font(.system(size: DSFont.Size.sm))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Nothing played yet today.")
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: DSDimension.HistoryStats.topTrackMinHeight,
                alignment: .leading
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppConstants.SettingsUI.cardPadding)
        .cardStyleUnpadded()
    }

    // MARK: - Top Leaderboard

    /// One card whose segmented header switches between top artists, tracks,
    /// and albums. Replaces the old artists-only card and surfaces the
    /// `topTracks` / `topAlbums` lists that were computed but never displayed.
    private var topListItems: [CountedItem] {
        switch topListKind {
        case .artists: return snapshot.topArtists
        case .tracks: return snapshot.topTracks
        case .albums: return snapshot.topAlbums
        }
    }

    private var topListCard: some View {
        VStack(alignment: .leading, spacing: DSSpace.s3) {
            HStack(spacing: DSSpace.s3) {
                CardEyebrowHeader("Top", systemImage: "trophy")
                Spacer()
                Picker("Top list", selection: $topListKind) {
                    ForEach(TopListKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("topListPicker")
            }

            // Reserve a full five-row height so flipping the segmented control
            // between Artists / Tracks / Albums (each a different length) or
            // filling in after load never resizes the card.
            topListContent
                .frame(
                    maxWidth: .infinity,
                    minHeight: DSDimension.HistoryStats.topListMinHeight,
                    alignment: .top
                )
        }
        .padding(AppConstants.SettingsUI.cardPadding)
        .cardStyleUnpadded()
    }

    @ViewBuilder
    private var topListContent: some View {
        let items = topListItems
        if items.isEmpty {
            Text("Not enough plays yet.")
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: DSSpace.s3) {
                ForEach(Array(items.prefix(5).enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: DSSpace.s3) {
                        Text("\(index + 1)")
                            .font(.system(size: DSFont.Size.body, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, alignment: .leading)
                        VStack(alignment: .leading, spacing: DSSpace.s0) {
                            Text(item.name)
                                .font(.system(size: DSFont.Size.base))
                                .lineLimit(1)
                            if let detail = item.detail {
                                Text(detail)
                                    .font(.system(size: DSFont.Size.sm))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(HistoryFormat.playCount(item.count))
                            .font(.system(size: DSFont.Size.body))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Recent

    /// Single recently-played card whose outer frame stays a consistent size
    /// across off / empty / populated states. Prevents the settings window
    /// from resizing when the user flips Listening History on or off.
    private var unifiedRecentCard: some View {
        VStack(alignment: .leading, spacing: DSSpace.s3) {
            CardEyebrowHeader("Recently played", systemImage: "clock.arrow.circlepath")

            Group {
                if !historyEnabled {
                    emptyStateContent(
                        title: "Nothing is being recorded",
                        subtitle: "Turn on Listening History to start tracking your plays."
                    )
                } else if recentPlaysSorted.isEmpty {
                    emptyStateContent(
                        title: "Nothing recorded yet",
                        subtitle: "Play something in Apple Music and it'll show up here."
                    )
                } else {
                    recentPlaysList
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: DSDimension.HistoryStats.recentCardMinHeight,
                alignment: .top
            )
        }
        .padding(AppConstants.SettingsUI.cardPadding)
        .cardStyleUnpadded()
    }

    @ViewBuilder
    private func emptyStateContent(title: String, subtitle: String) -> some View {
        VStack(spacing: DSSpace.s2) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: DSFont.Size.xl, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: DSFont.Size.base, weight: .medium))
            Text(subtitle)
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// All recorded plays, newest first. Sorted lazily off the service's
    /// `records` so we don't depend on the snapshot's limited `recent` slice.
    private var recentPlaysSorted: [PlayRecord] {
        guard let service else { return [] }
        return service.records.sorted { $0.timestamp > $1.timestamp }
    }

    private var recentPlaysList: some View {
        let all = recentPlaysSorted
        let visible = Array(all.prefix(visibleRecentCount))
        let hasMore = visible.count < all.count
        return VStack(alignment: .leading, spacing: DSSpace.s3) {
            ForEach(visible, id: \.self) { play in
                HStack(spacing: DSSpace.s3) {
                    Image(systemName: "music.note")
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(.secondary)
                        .frame(width: DSSpace.s6)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(play.track)
                            .font(.system(size: DSFont.Size.base))
                            .lineLimit(1)
                        Text(play.artist)
                            .font(.system(size: DSFont.Size.sm))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(HistoryFormat.relative(play.timestamp))
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(.tertiary)
                }
            }
            if hasMore {
                Button {
                    visibleRecentCount += AppConstants.History.recentPageStep
                } label: {
                    Label("Load \(AppConstants.History.recentPageStep) more", systemImage: "arrow.down.circle")
                        .font(.system(size: DSFont.Size.sm))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Load \(AppConstants.History.recentPageStep) more plays")
                .accessibilityIdentifier("loadMoreHistoryButton")
                .padding(.top, DSSpace.s1)
            }
        }
    }

    // MARK: - !stats Command

    private var statsCommandCard: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            HStack(spacing: DSSpace.s3) {
                CardEyebrowHeader("Chat command", systemImage: "text.bubble")
                Spacer()
                StatusChip(text: "Twitch", color: .purple)
            }

            ToggleSettingRow(
                title: "!stats command",
                subtitle: "Lets chat pull up today's top track. Set live-only for all commands in Twitch settings.",
                isOn: $statsCommandEnabled,
                accessibilityLabel: "Toggle the stats Twitch command",
                accessibilityIdentifier: "statsCommandToggle"
            )

            if statsCommandEnabled {
                Divider()
                cooldownRow(title: "Global cooldown", value: $statsGlobalCooldown)
                cooldownRow(title: "Per-user cooldown", value: $statsUserCooldown)

                CommandAliasField(
                    aliases: $statsCommandAliases,
                    placeholder: "e.g. nowstats, mystats",
                    accessibilityLabel: "Stats command aliases",
                    accessibilityIdentifier: "statsCommandAliases"
                )
            }
        }
        .padding(AppConstants.SettingsUI.cardPadding)
        .cardStyleUnpadded()
    }

    // MARK: - Retention

    /// Picker for how many days of listening history `ListeningHistoryService`
    /// keeps on disk before pruning. `0` means keep forever.
    private var retentionCard: some View {
        VStack(alignment: .leading, spacing: DSSpace.s3) {
            CardEyebrowHeader("History retention", systemImage: "calendar")

            HStack {
                Text("Keep history for")
                    .font(.system(size: DSFont.Size.body))
                Spacer()
                Picker("Keep history for", selection: $historyRetentionDays) {
                    Text("Forever").tag(0)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("180 days").tag(180)
                    Text("365 days").tag(365)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 120)
                .accessibilityIdentifier("historyRetentionDays")
            }

            Text("Older entries are pruned the next time the app launches.")
                .font(.system(size: DSFont.Size.xs))
                .foregroundStyle(.tertiary)
        }
        .padding(AppConstants.SettingsUI.cardPadding)
        .cardStyleUnpadded()
    }

    @ViewBuilder
    private func cooldownRow(title: String, value: Binding<Double>) -> some View {
        LabeledSlider(
            label: title,
            value: value,
            range: 0...60,
            step: 5,
            format: { "\(Int($0))s" },
            accessibilityIdentifier: "cooldown.\(title)"
        )
    }

    // MARK: - Actions

    /// Monthly Wrap action card. Sits beside the retention card in the
    /// two-column tail when Stats is on. The destructive Clear History action
    /// lives in the danger zone below, not here.
    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: DSSpace.s3) {
            CardEyebrowHeader("Manage", systemImage: "slider.horizontal.3")

            Button {
                showWrapSheet = true
            } label: {
                Label("Monthly Wrap", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .pointerCursor()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppConstants.SettingsUI.cardPadding)
        .cardStyleUnpadded()
    }

    /// First-run explainer shown when Listening History is off, so the default
    /// state teaches what the feature does and offers a one-tap enable instead
    /// of looking blank.
    private var firstRunExplainer: some View {
        VStack(alignment: .leading, spacing: DSSpace.s3) {
            CardEyebrowHeader("What you'll get", systemImage: "sparkles")

            Text("Stats & Charts add a weekly view, your top artists, listening by hour, and a monthly wrap. Everything is computed on this Mac.")
                .font(.system(size: DSFont.Size.body))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                guard musicPermission != .denied else { return }
                historyEnabled = true
                handleHistoryChange(true)
            } label: {
                Label("Turn on history", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .pointerCursor()
            .disabled(musicPermission == .denied)
            .accessibilityIdentifier("turnOnHistoryButton")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppConstants.SettingsUI.cardPadding)
        .cardStyleUnpadded()
    }

    /// Red danger zone holding the irreversible Clear History action, matching
    /// the Advanced pane's danger-zone treatment so destructive actions read
    /// the same everywhere.
    private var dangerCard: some View {
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

                Text("Permanently deletes every recorded play. Can't be undone.")
                    .font(.system(size: DSFont.Size.body))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DestructiveButton(
                title: "Clear History",
                systemImage: "trash",
                accessibilityIdentifier: "clearHistoryButton",
                action: { showClearAlert = true }
            )
            .disabled(snapshot.totalPlays == 0)
            .accessibilityHint("Permanently deletes every recorded play")
        }
        .cardStyle()
    }

    // MARK: - Helpers

    /// Cascades Stats off when History is turned off, then notifies the app
    /// delegate so recording starts or stops.
    private func handleHistoryChange(_ enabled: Bool) {
        if enabled, musicPermission == .denied {
            historyEnabled = false
            return
        }
        if !enabled {
            statsEnabled = false
            statsCommandEnabled = false
            visibleRecentCount = AppConstants.History.recentDisplayCount
        }
        NotificationCenter.default.postEnabled(.listeningHistorySettingChanged, enabled: enabled)
    }

    /// Cascades the `!stats` command off when Stats is turned off.
    private func handleStatsChange(_ enabled: Bool) {
        if !enabled {
            statsCommandEnabled = false
        }
    }
}

// MARK: - Preview

#Preview {
    HistoryStatsSettingsView()
        .padding()
        .frame(width: 720, height: 600)
}
