//
//  HistoryFormatting.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Shared display formatting for listening-history values.
///
/// Keeps duration / relative-time strings consistent across the settings pane,
/// the charts, the monthly wrap, and the `!stats` command.
enum HistoryFormat {

    // MARK: - Duration Formatting

    /// Formats a listening duration compactly, e.g. `6h 12m`, `12m`, `45s`.
    ///
    /// - Parameter seconds: Duration in seconds.
    /// - Returns: A short human-readable string.
    static func listeningTime(_ seconds: TimeInterval) -> String {
        let total = safeSeconds(seconds)
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

    /// Formats a playback position as a clock string, e.g. `3:07`, `12:45`.
    ///
    /// Used for now-playing position and remaining time. Distinct from
    /// ``listeningTime(_:)``, which is a compact `6h 12m` duration summary.
    ///
    /// - Parameter seconds: Position in seconds. Negative values clamp to `0`.
    /// - Returns: A `M:SS` string.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = safeSeconds(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Clamps a duration to `0...Int.max` and rounds to whole seconds.
    ///
    /// `Int(_:)` traps on non-finite or out-of-range Doubles. Play-log
    /// durations decode raw from a user-inspectable NDJSON file, so a corrupt
    /// or hand-edited value (`inf`, `1e300`) must not reach the conversion.
    private static func safeSeconds(_ seconds: TimeInterval) -> Int {
        guard seconds.isFinite else { return 0 }
        // Cap below Int.max: `Double(Int.max)` rounds up to Int.max+1, which
        // would itself trap on conversion. 9e18 is ~292 billion years.
        return Int(min(max(seconds, 0), 9.0e18).rounded())
    }

    // MARK: - Relative Time

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
