//
//  HistoryStatsSettingsView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 5/22/26.
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

    // MARK: - State

    @State private var showWrapSheet = false
    @State private var showClearAlert = false
    @State private var musicPermission: MusicPermissionState = MusicPermissionCache.read() ?? .unknown
    @State private var visibleRecentCount: Int = AppConstants.History.recentDisplayCount

    /// The shared history service. Accessed as a computed property so the
    /// Observation framework tracks property reads each time `body` runs.
    private var service: ListeningHistoryService? {
        AppDelegate.shared?.historyService
    }

    private var snapshot: StatsSnapshot {
        service?.snapshot ?? .empty
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.SettingsUI.sectionSpacing) {
            intro
            if musicPermission == .denied {
                MusicPermissionBanner(
                    message: "WolfWave needs Apple Music automation access to record what you play. Enable it in System Settings → Privacy & Security → Automation."
                )
            }
            togglesCard
            unifiedRecentCard
            if historyEnabled, statsEnabled, snapshot.hasData {
                summaryCard
                StatsChartsView(snapshot: snapshot)
                topArtistsCard
            }
            if historyEnabled, statsEnabled {
                statsCommandCard
            }
            if historyEnabled {
                actionsRow
            }
        }
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

    // MARK: - Intro

    private var intro: some View {
        Text("WolfWave can remember what you play — kept on this Mac, never uploaded.")
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
                    ? "Apple Music access required — see banner above."
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
            summaryStat(
                value: "\(snapshot.playsThisWeek)",
                unit: HistoryFormat.listeningTime(snapshot.listeningSecondsThisWeek),
                label: "This week"
            )
            Divider().frame(height: 40)
            summaryStat(
                value: "\(snapshot.playsToday)",
                unit: HistoryFormat.listeningTime(snapshot.listeningSecondsToday),
                label: "Today"
            )
            Divider().frame(height: 40)
            summaryStat(
                value: "\(snapshot.totalPlays)",
                unit: HistoryFormat.listeningTime(snapshot.totalListeningSeconds),
                label: "All time"
            )
        }
        .frame(maxWidth: .infinity)
        .padding(AppConstants.SettingsUI.cardPadding)
        .cardStyleUnpadded()
    }

    @ViewBuilder
    private func summaryStat(value: String, unit: String, label: String) -> some View {
        VStack(spacing: DSSpace.s0) {
            Text(value)
                .font(.system(size: DSFont.Size.x2xl, weight: .bold))
            Text(unit)
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(size: DSFont.Size.xs, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Top Artists

    private var topArtistsCard: some View {
        VStack(alignment: .leading, spacing: DSSpace.s3) {
            cardHeader("Top artists", systemImage: "music.mic")

            ForEach(Array(snapshot.topArtists.prefix(5).enumerated()), id: \.element.id) { index, artist in
                HStack(spacing: DSSpace.s3) {
                    Text("\(index + 1)")
                        .font(.system(size: DSFont.Size.body, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, alignment: .leading)
                    Text(artist.name)
                        .font(.system(size: DSFont.Size.base))
                        .lineLimit(1)
                    Spacer()
                    Text(HistoryFormat.playCount(artist.count))
                        .font(.system(size: DSFont.Size.body))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(AppConstants.SettingsUI.cardPadding)
        .cardStyleUnpadded()
    }

    // MARK: - Recent

    /// Single recently-played card whose outer frame stays a consistent size
    /// across off / empty / populated states. Prevents the settings window
    /// from resizing when the user flips Listening History on or off.
    private var unifiedRecentCard: some View {
        VStack(alignment: .leading, spacing: DSSpace.s3) {
            cardHeader("Recently played", systemImage: "clock.arrow.circlepath")

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
                .font(.system(size: DSFont.Size.x28, weight: .light))
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
            ForEach(Array(visible.enumerated()), id: \.offset) { _, play in
                HStack(spacing: DSSpace.s3) {
                    Image(systemName: "music.note")
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(.secondary)
                        .frame(width: DSFont.Size.x16)
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
            ToggleSettingRow(
                title: "!stats Twitch command",
                subtitle: "Lets chat ask for today's top track. Replies only while your stream is live.",
                isOn: $statsCommandEnabled,
                accessibilityLabel: "Toggle the stats Twitch command",
                accessibilityIdentifier: "statsCommandToggle"
            )

            if statsCommandEnabled {
                Divider()
                cooldownRow(title: "Global cooldown", value: $statsGlobalCooldown)
                cooldownRow(title: "Per-user cooldown", value: $statsUserCooldown)
            }
        }
        .padding(AppConstants.SettingsUI.cardPadding)
        .cardStyleUnpadded()
    }

    @ViewBuilder
    private func cooldownRow(title: String, value: Binding<Double>) -> some View {
        HStack(spacing: DSSpace.s4) {
            Text(title)
                .font(.system(size: DSFont.Size.body))
            Spacer()
            Slider(value: value, in: 0...60, step: 5)
                .frame(width: 160)
            Text("\(Int(value.wrappedValue))s")
                .font(.system(size: DSFont.Size.body, weight: .medium))
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)
        }
    }

    // MARK: - Actions

    private var actionsRow: some View {
        HStack(spacing: DSSpace.s3) {
            if statsEnabled {
                Button {
                    showWrapSheet = true
                } label: {
                    Label("Monthly Wrap", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .pointerCursor()
            }

            Spacer()

            Button(role: .destructive) {
                showClearAlert = true
            } label: {
                Label("Clear History", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .pointerCursor()
            .disabled(snapshot.totalPlays == 0)
            .accessibilityIdentifier("clearHistoryButton")
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func cardHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: DSFont.Size.sm, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
        }
        .accessibilityAddTraits(.isHeader)
    }

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
        NotificationCenter.default.post(
            AppConstants.Notifications.listeningHistorySettingChanged,
            userInfo: ["enabled": enabled]
        )
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
