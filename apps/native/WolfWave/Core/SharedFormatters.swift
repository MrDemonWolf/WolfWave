//
//  SharedFormatters.swift
//  WolfWave
//
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
    /// even though formatting calls are documented as thread-safe — hence
    /// `nonisolated(unsafe)`. Don't mutate `formatOptions` after init.
    nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()

    /// `HH:mm:ss.SSS` — used by the log writer.
    static let logTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    /// Short medium date (e.g. `May 28, 2026`).
    static let mediumDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
