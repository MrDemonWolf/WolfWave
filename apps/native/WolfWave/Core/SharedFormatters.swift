//
//  SharedFormatters.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-28.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Process-wide `DateFormatter` and `ISO8601DateFormatter` instances.
///
/// `DateFormatter` allocation is non-trivial; the system caches its internal
/// CFDateFormatter even on copies. Sharing per-purpose singletons cuts repeated
/// construction across the diagnostics path, the log writer, the monthly wrap
/// renderer, and the onboarding date stamp.
nonisolated enum SharedFormatters {

    /// Strict ISO 8601 (`2026-05-28T12:34:56Z`).
    ///
    /// `ISO8601DateFormatter` (unlike `DateFormatter`) is not annotated `Sendable`
    /// even though formatting calls are documented as thread-safe, hence
    /// `nonisolated(unsafe)`. Don't mutate `formatOptions` after init.
    nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()

    /// `HH:mm:ss.SSS`. Retained for UI surfaces that show a time-of-day only.
    ///
    /// Not used by the log writer any more: a time without a date makes a
    /// multi-day log ambiguous to order and impossible to line up against a
    /// crash report. See ``logTimestampISO``.
    static let logTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    /// `2026-08-14T14:03:22.481-05:00`, the leading field of every log line.
    ///
    /// Full ISO 8601 with millisecond precision and an explicit UTC offset, so a
    /// log entry is orderable and comparable against any other timestamped
    /// artifact (crash markers, the NDJSON play log, server logs) without
    /// guessing the year or the timezone.
    ///
    /// Locale is pinned to `en_US_POSIX`: without it a user's regional calendar
    /// or numbering system can rewrite the digits, which would break the parser
    /// in ``LogRecord``.
    static let logTimestampISO: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        return formatter
    }()
}
