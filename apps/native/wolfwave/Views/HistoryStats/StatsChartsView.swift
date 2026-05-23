//
//  StatsChartsView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 5/22/26.
//

import SwiftUI
import Charts

/// SwiftUI Charts visualizations for the History & Stats pane: a 7-day play
/// trend and a listening-by-hour breakdown.
struct StatsChartsView: View {

    // MARK: - Properties

    let snapshot: StatsSnapshot

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.SettingsUI.sectionSpacing) {
            weekChart
            hourChart
        }
    }

    // MARK: - Last 7 Days

    @ViewBuilder
    private var weekChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            chartHeader("Last 7 days", systemImage: "calendar")

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
            .frame(height: 140)
            .accessibilityLabel("Plays per day over the last 7 days")
        }
        .padding(AppConstants.SettingsUI.cardPadding)
        .cardStyleUnpadded()
    }

    // MARK: - By Hour

    @ViewBuilder
    private var hourChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            chartHeader("When you listen", systemImage: "clock")

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
            .frame(height: 120)
            .accessibilityLabel("Plays by hour of day")
        }
        .padding(AppConstants.SettingsUI.cardPadding)
        .cardStyleUnpadded()
    }

    // MARK: - Helpers

    @ViewBuilder
    private func chartHeader(_ title: String, systemImage: String) -> some View {
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
