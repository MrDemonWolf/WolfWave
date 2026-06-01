//
//  DebugDiagnostics.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-26.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

#if DEBUG
import Foundation

/// DEBUG-only diagnostics snapshot + markdown formatter for the "Copy Diagnostics"
/// button in the Debug tab. Pure value type — no UI, no pasteboard. Mirrors the
/// environment block built by `BugReportURL.make(…)` but routes to the pasteboard
/// for quick pasting into a GitHub issue.
enum DebugDiagnostics {

    /// Snapshot of app + service state at the moment "Copy Diagnostics" is clicked.
    struct Snapshot: Equatable {
        let appVersion: String
        let build: String
        let osVersion: String
        let arch: String
        let installMethod: String
        let logSizeBytes: Int64
        let logLineCount: Int
        let twitchConnected: Bool
        let discordConnected: Bool
        let widgetEnabled: Bool
        let musicTrackingEnabled: Bool
    }

    /// Returns a markdown blob suitable for pasting into a GitHub issue.
    static func markdown(_ snapshot: Snapshot) -> String {
        let size = ByteFormatting.string(snapshot.logSizeBytes)
        return """
        ## Environment

        | Field | Value |
        |---|---|
        | App version | \(snapshot.appVersion) (build \(snapshot.build)) |
        | macOS | \(snapshot.osVersion) |
        | Architecture | \(snapshot.arch) |
        | Install method | \(snapshot.installMethod) |
        | Log file size | \(size) |
        | Log line count | \(snapshot.logLineCount) |

        ## Service State

        | Service | State |
        |---|---|
        | Twitch | \(yesNo(snapshot.twitchConnected)) |
        | Discord | \(yesNo(snapshot.discordConnected)) |
        | Widget HTTP | \(yesNo(snapshot.widgetEnabled)) |
        | Music tracking | \(yesNo(snapshot.musicTrackingEnabled)) |
        """
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }
}
#endif
