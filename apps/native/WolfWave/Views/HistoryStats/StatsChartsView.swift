//
//  StatsChartsView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI
import Charts

// MARK: - Week Chart Card

/// A standalone card showing the 7-day play trend. Split out from the old
/// `StatsChartsView` so the History & Stats pane can pair it beside the
/// by-hour chart in a `ResponsiveRow` (two columns when wide, stacked when not).
struct WeekChartCard: View {

    let snapshot: StatsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s3) {
            chartCardHeader("Last 7 days", systemImage: "calendar")

            Chart(snapshot.last7Days) { day in
                BarMark(
                    x: .value("Day", day.day, unit: .day),
                    y: .value("Plays", day.count)
                )
                .foregroundStyle(AppConstants.Brand.appleMusicGradientEnd.gradient)
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: DSDimension.HistoryStats.chartHeight)
            .accessibilityLabel("Plays per day over the last 7 days")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppConstants.SettingsUI.cardPadding)
        .cardStyleUnpadded()
    }
}

// MARK: - Hour Chart Card

/// A standalone card showing the listening-by-hour breakdown.
struct HourChartCard: View {

    let snapshot: StatsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s3) {
            chartCardHeader("When you listen", systemImage: "clock")

            Chart(0..<24, id: \.self) { hour in
                BarMark(
                    x: .value("Hour", hour),
                    y: .value("Plays", playsAtHour(hour))
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(2)
            }
            .chartXScale(domain: 0...23)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                    AxisValueLabel {
                        if let hour = value.as(Int.self) {
                            Text(hourLabel(hour))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: DSDimension.HistoryStats.chartHeight)
            .accessibilityLabel("Plays by hour of day")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppConstants.SettingsUI.cardPadding)
        .cardStyleUnpadded()
    }

    /// Play count for a given hour, safely handling an unexpected array size.
    private func playsAtHour(_ hour: Int) -> Int {
        snapshot.playsByHour.indices.contains(hour) ? snapshot.playsByHour[hour] : 0
    }

    /// Formats an hour-of-day axis label (e.g. `12a`, `6a`, `12p`, `6p`).
    private func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0: return "12a"
        case 12: return "12p"
        case let h where h < 12: return "\(h)a"
        default: return "\(hour - 12)p"
        }
    }
}

// MARK: - Combined View (back-compat / previews)

/// SwiftUI Charts visualizations for the History & Stats pane: a 7-day play
/// trend and a listening-by-hour breakdown, stacked vertically.
///
/// The History & Stats pane now places `WeekChartCard` and `HourChartCard`
/// side by side via `ResponsiveRow`; this combined view is retained for
/// previews and any single-column caller.
struct StatsChartsView: View {

    let snapshot: StatsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.SettingsUI.sectionSpacing) {
            WeekChartCard(snapshot: snapshot)
            HourChartCard(snapshot: snapshot)
        }
    }
}

// MARK: - Shared Header

/// Eyebrow header shared by the chart cards. Mirrors the in-card header used
/// elsewhere in the History & Stats pane (SF Symbol + sentence-case eyebrow).
@ViewBuilder
private func chartCardHeader(_ title: String, systemImage: String) -> some View {
    HStack(spacing: DSSpace.s1h) {
        Image(systemName: systemImage)
            .font(.system(size: DSFont.Size.sm, weight: .semibold))
            .foregroundStyle(.secondary)
        Text(title)
            .sectionEyebrow()
    }
    .accessibilityAddTraits(.isHeader)
}

// MARK: - Previews

#Preview("With data") {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let week: [DailyCount] = (0..<7).reversed().map { offset in
        let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
        let counts = [12, 18, 7, 24, 31, 15, 22]
        return DailyCount(id: day, count: counts[offset], seconds: TimeInterval(counts[offset] * 210))
    }
    let hours: [Int] = [
        0, 0, 0, 0, 0, 0,       //  0-5: overnight
        2, 5, 9, 14, 18, 12,    //  6-11: morning
        20, 24, 22, 19, 16, 17, // 12-17: afternoon
        21, 18, 12, 6, 3, 1,    // 18-23: evening
    ]
    let snapshot = StatsSnapshot(
        totalPlays: 129,
        totalListeningSeconds: 27_100,
        playsToday: 22,
        listeningSecondsToday: 4_620,
        playsThisWeek: 129,
        listeningSecondsThisWeek: 27_100,
        topArtists: [],
        topTracks: [],
        topAlbums: [],
        last7Days: week,
        playsByHour: hours,
        recent: [],
        topTrackToday: nil
    )
    return ResponsiveRow {
        WeekChartCard(snapshot: snapshot)
    } right: {
        HourChartCard(snapshot: snapshot)
    }
    .padding()
    .frame(width: 720)
}

#Preview("Empty") {
    StatsChartsView(snapshot: .empty)
        .padding()
        .frame(width: 600)
}
