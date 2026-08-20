//
//  StreamDeckPaneStatus.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-19.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Resolves the Stream Deck pane's header chip from the two switches that gate
/// a working key.
///
/// Pure and `nonisolated` so the precedence rule is testable without standing up
/// the view: the shared server switch outranks the command switch, because
/// turning commands on while the server is off does nothing and a key would just
/// sit there looking broken. The chip therefore reports the *first* thing in the
/// user's way rather than a bare "Off" that leaves them hunting for which switch.
nonisolated enum StreamDeckPaneStatus {

    // MARK: - Resolved

    /// One chip's worth of state: label, tint, and the glyph that carries the
    /// same meaning through shape (WCAG 1.4.1).
    struct Resolved: Equatable {
        let text: String
        let color: Color
        let symbol: String
    }

    // MARK: - Public Methods

    /// Resolves the chip for the current switch positions.
    ///
    /// - Parameters:
    ///   - controlEnabled: Whether Stream Deck commands are allowed.
    ///   - serverEnabled: Whether the shared WebSocket server (Stream Widgets)
    ///     is on. Outranks `controlEnabled`; both panes are served by one
    ///     `WebSocketServerService` on one port.
    /// - Returns: The label, tint, and glyph for the header chip.
    static func resolve(controlEnabled: Bool, serverEnabled: Bool) -> Resolved {
        guard serverEnabled else {
            return Resolved(
                text: "Server off",
                color: DSColor.neutral,
                symbol: StatusChip.StateGlyph.off
            )
        }

        guard controlEnabled else {
            return Resolved(
                text: "Commands off",
                color: DSColor.warning,
                symbol: StatusChip.StateGlyph.starting
            )
        }

        return Resolved(
            text: "Ready",
            color: DSColor.success,
            symbol: StatusChip.StateGlyph.on
        )
    }
}
