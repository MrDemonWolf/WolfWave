//
//  HistoryFormatting.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 5/22/26.
//

import Foundation

/// Shared display formatting for listening-history values.
///
/// Keeps duration / relative-time strings consistent across the settings pane,
/// the charts, the monthly wrap, and the `!stats` command.
enum HistoryFormat {

    /// Formats a listening duration compactly, e.g. `6h 12m`, `12m`, `45s`.
    ///
    /// - Parameter seconds: Duration in seconds.
    /// - Returns: A short human-readable string.
    static func listeningTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total)s" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    /// Formats a play count with its noun, e.g. `1 play`, `42 plays`.
    static func playCount(_ count: Int) -> String {
        count == 1 ? "1 play" : "\(count) plays"
    }

    /// Shared relative-time formatter ("2 min ago").
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// Formats how long ago `date` was relative to `now`.
    ///
    /// - Parameters:
    ///   - date: The past date.
    ///   - now: Reference point. Defaults to the current time.
    /// - Returns: A short relative string such as `2 min ago`.
    static func relative(_ date: Date, now: Date = Date()) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: now)
    }
}
