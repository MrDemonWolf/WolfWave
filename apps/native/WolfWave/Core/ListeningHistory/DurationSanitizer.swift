//
//  DurationSanitizer.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-07-18.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Clamps a raw duration to a finite, non-negative, in-`Int`-range value.
///
/// The play log is a user-inspectable NDJSON file, so a corrupt or hand-edited
/// value (`inf`, `nan`, `1e300`) can reach the app. This is the single guard
/// that keeps such a value from trapping a downstream `Int(_:)` conversion in
/// stats or formatting. Shared by `PlayRecord`'s decode boundary and
/// `HistoryFormatting`.
///
/// `nonisolated` because `PlayRecord.init(from:)` is a nonisolated decode
/// context and the module otherwise defaults to `MainActor`.
nonisolated enum DurationSanitizer {

    /// The ceiling. `Double(Int.max)` rounds up to `Int.max + 1`, which would
    /// itself trap on conversion; `9e18` is safely below it (~292 billion years).
    static let ceiling: Double = 9.0e18

    /// Returns `value` clamped to `0...ceiling`, or `0` when it is `nil` or not
    /// finite.
    static func clampFiniteSeconds(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0 }
        return min(max(value, 0), ceiling)
    }
}
