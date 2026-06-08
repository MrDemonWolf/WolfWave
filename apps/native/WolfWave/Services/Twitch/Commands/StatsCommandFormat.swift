//
//  StatsCommandFormat.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-08.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

// MARK: - StatsWindow

/// The time window the `!stats` chat command reports over.
///
/// The streamer picks one in **Settings → History & Stats → !stats command**;
/// the raw value is stored in `AppConstants.UserDefaults.statsCommandWindow` and
/// resolved at send time via ``current(_:)``. Switching it takes effect on the
/// next `!stats`.
///
/// Declared `nonisolated` so the chat-dispatch path and the SwiftUI settings
/// view can both read it without crossing actor isolation.
nonisolated enum StatsWindow: String, CaseIterable, Identifiable, Sendable {

    /// Plays since the start of the local calendar day.
    case today

    /// Plays since the current Twitch stream went live. Falls back to ``today``
    /// when the stream isn't live (no session start to anchor to).
    case session

    /// The trailing seven calendar days, including today.
    case week

    /// Every recorded play, including the lifetime tally of trimmed history.
    case allTime

    /// The window applied when nothing has been chosen yet.
    static let `default`: StatsWindow = .today

    // MARK: - Identifiable

    var id: String { rawValue }

    // MARK: - Display

    /// Short label shown in the settings picker.
    var pickerLabel: String {
        switch self {
        case .today: return "Today"
        case .session: return "This stream"
        case .week: return "Last 7 days"
        case .allTime: return "All time"
        }
    }

    /// The lead-in shown in the chat line, e.g. `🐺 This stream: …`.
    var chatLabel: String {
        switch self {
        case .today: return "Today"
        case .session: return "This stream"
        case .week: return "Last 7 days"
        case .allTime: return "All time"
        }
    }

    // MARK: - Resolution

    /// Resolves the streamer's selected window from UserDefaults.
    ///
    /// - Parameter defaults: Store to read from (injectable for tests).
    /// - Returns: The stored window, or ``default`` when unset or unrecognized.
    static func current(_ defaults: Foundation.UserDefaults = .standard) -> StatsWindow {
        guard
            let raw = defaults.string(forKey: AppConstants.UserDefaults.statsCommandWindow),
            let window = StatsWindow(rawValue: raw)
        else {
            return .default
        }
        return window
    }
}

// MARK: - StatsPart

/// A single fact the `!stats` chat command can include in its reply.
///
/// The streamer toggles any combination on; the selection is stored as a
/// comma-separated list of raw values in
/// `AppConstants.UserDefaults.statsCommandParts`. ``CaseIterable`` order is the
/// canonical render order, so the chat line always reads the same way regardless
/// of the order the streamer tapped the chips.
nonisolated enum StatsPart: String, CaseIterable, Identifiable, Sendable {

    /// How many tracks played in the window.
    case plays

    /// Total listening time in the window.
    case listeningTime

    /// The most-played track in the window.
    case topTrack

    /// The most-played artist in the window.
    case topArtist

    /// The facts included when nothing has been chosen yet. Matches the
    /// historical `!stats` reply: a play count plus the top track.
    static let defaults: [StatsPart] = [.plays, .topTrack]

    // MARK: - Identifiable

    var id: String { rawValue }

    // MARK: - Display

    /// Short label shown on the settings chip.
    var label: String {
        switch self {
        case .plays: return "Plays"
        case .listeningTime: return "Listening time"
        case .topTrack: return "Top track"
        case .topArtist: return "Top artist"
        }
    }

    // MARK: - Resolution

    /// Resolves the streamer's selected facts from UserDefaults.
    ///
    /// Unknown or duplicate tokens are dropped, the result is re-ordered to the
    /// canonical ``CaseIterable`` order, and an empty/garbage value falls back to
    /// ``defaults`` so the command never produces an empty reply.
    ///
    /// - Parameter defaults: Store to read from (injectable for tests).
    /// - Returns: The resolved facts in canonical order (never empty).
    static func current(_ defaults: Foundation.UserDefaults = .standard) -> [StatsPart] {
        guard let raw = defaults.string(forKey: AppConstants.UserDefaults.statsCommandParts) else {
            return Self.defaults
        }
        return decode(raw)
    }

    /// Parses a comma-separated raw-value list into canonical-ordered parts.
    ///
    /// - Parameter raw: Comma-separated `StatsPart` raw values.
    /// - Returns: The parsed facts in canonical order, or ``defaults`` when none parse.
    static func decode(_ raw: String) -> [StatsPart] {
        let tokens = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let selected = Set(tokens.compactMap { StatsPart(rawValue: $0) })
        guard !selected.isEmpty else { return Self.defaults }
        // Re-emit in canonical order so the chat line reads consistently.
        return Self.allCases.filter { selected.contains($0) }
    }

    /// Serializes parts to the comma-separated raw-value list stored in UserDefaults.
    ///
    /// - Parameter parts: The selected facts.
    /// - Returns: A comma-separated raw-value string in canonical order.
    static func encode(_ parts: [StatsPart]) -> String {
        let selected = Set(parts)
        return Self.allCases.filter { selected.contains($0) }
            .map(\.rawValue)
            .joined(separator: ",")
    }
}

// MARK: - StatsChatLine

/// Pure assembly of the `!stats` chat reply from a resolved window summary.
///
/// Kept separate from `ListeningHistoryService` (which owns the records and
/// resolves the window bounds) so the formatting is testable without a
/// disk-backed service.
///
/// MainActor-isolated (the module default) because it calls `HistoryFormat`,
/// which is itself MainActor-isolated. Every caller (the service, the settings
/// preview, tests) already runs on the main actor.
enum StatsChatLine {

    /// Renders the chat line for a window's summary.
    ///
    /// - Parameters:
    ///   - label: The window's chat lead-in, e.g. `"This stream"`.
    ///   - summary: The window-scoped rollup.
    ///   - parts: The facts to include, in any order (rendered in canonical order).
    /// - Returns: The chat line, prefixed with the 🐺 mark.
    static func render(label: String, summary: WindowSummary, parts: [StatsPart]) -> String {
        guard summary.hasData else {
            return "🐺 \(label): nothing logged yet. The music's just getting started!"
        }

        let chosen = Set(parts.isEmpty ? StatsPart.defaults : parts)
        var segments: [String] = []
        for part in StatsPart.allCases where chosen.contains(part) {
            switch part {
            case .plays:
                segments.append(HistoryFormat.playCount(summary.plays))
            case .listeningTime:
                segments.append(HistoryFormat.listeningTime(summary.listeningSeconds))
            case .topTrack:
                if let track = summary.topTrack {
                    let by = track.detail.map { " by \($0)" } ?? ""
                    segments.append("top track \(track.name)\(by) (\(times(track.count)))")
                }
            case .topArtist:
                if let artist = summary.topArtist {
                    segments.append("top artist \(artist.name) (\(times(artist.count)))")
                }
            }
        }

        // Guard against an all-nil selection (e.g. only "top artist" with no data).
        if segments.isEmpty {
            segments.append(HistoryFormat.playCount(summary.plays))
        }
        return "🐺 \(label): \(segments.joined(separator: " · "))"
    }

    /// Formats a play count as a multiplier, e.g. `1×`, `12×`.
    private static func times(_ count: Int) -> String {
        count == 1 ? "1×" : "\(count)×"
    }
}
