//
//  ByteFormatting.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-01.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Shared byte-count formatting backed by a single reused `ByteCountFormatter`.
///
/// Replaces the per-call-site `ByteCountFormatter()` allocations the audit
/// found in the Advanced and Debug panes (log size, artwork cache size,
/// diagnostics payloads). The formatter is created once and reused. The app
/// builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so the shared
/// instance is main-actor isolated and these main-thread UI call sites never
/// race on it.
enum ByteFormatting {

    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        // Floor at KB so log / cache / diagnostics sizes read consistently
        // ("Zero KB", "157 KB", "1.2 MB") instead of flipping to raw bytes.
        formatter.allowedUnits = [.useKB, .useMB]
        return formatter
    }()

    /// Formats a byte count using the file-size style (e.g. "1.2 MB", "Zero KB").
    static func string(_ byteCount: Int64) -> String {
        formatter.string(fromByteCount: byteCount)
    }

    /// Formats an `Int` byte count using the file-size style.
    static func string(_ byteCount: Int) -> String {
        string(Int64(byteCount))
    }
}
