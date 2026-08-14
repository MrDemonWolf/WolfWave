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
/// button in the Debug tab. Pure value type, no UI, no pasteboard. Mirrors the
/// environment block built by `BugReportURL.make(…)` but routes to the pasteboard
/// for quick pasting into a GitHub issue.
enum DebugDiagnostics {

    // MARK: - Snapshot

    /// Snapshot of app state at the moment "Copy Diagnostics" is clicked.
    ///
    /// Preferences and connections are deliberately separate. They used to be
    /// one "Service State" table fed from `@AppStorage` toggles plus a
    /// Keychain-token presence check, which meant a pasted issue could report
    /// "Discord | Yes" for someone whose RPC socket never connected, and
    /// "Twitch | Yes" purely because a stale token sat in the Keychain. A
    /// diagnostics blob that quietly reports intent as if it were fact sends
    /// debugging down the wrong path, which is the opposite of its job.
    struct Snapshot: Equatable {
        // Environment
        let appVersion: String
        let build: String
        let osVersion: String
        let arch: String
        let installMethod: String
        let logSizeBytes: Int64
        let logLineCount: Int

        /// What the user asked for (`@AppStorage` toggles).
        let musicTrackingEnabled: Bool
        let discordPresenceEnabled: Bool
        let widgetHTTPEnabled: Bool

        /// What is actually true right now (live service state).
        let twitchConnected: Bool
        let discordConnection: String
        let twitchTokenStored: Bool
    }

    // MARK: - Formatting

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

        ## Connections

        Live state, not settings.

        | Service | State |
        |---|---|
        | Twitch chat | \(snapshot.twitchConnected ? "connected" : "not connected") |
        | Discord RPC | \(snapshot.discordConnection) |
        | Twitch token in Keychain | \(yesNo(snapshot.twitchTokenStored)) |

        ## Preferences

        What the user turned on, which is not the same as whether it works.

        | Setting | Enabled |
        |---|---|
        | Music tracking | \(yesNo(snapshot.musicTrackingEnabled)) |
        | Discord presence | \(yesNo(snapshot.discordPresenceEnabled)) |
        | Widget HTTP server | \(yesNo(snapshot.widgetHTTPEnabled)) |
        """
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }
}
#endif
