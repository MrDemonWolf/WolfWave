//
//  StreamerMode.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-25.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// UI-only redaction helper for **Streamer Mode**.
///
/// When the user enables Streamer Mode from the tray menu, sensitive values
/// (channel name, overlay URL, WebSocket URI, auth-adjacent identifiers) are
/// swapped for opaque placeholders so the WolfWave UI is safe to show on
/// camera. It does **not** alter what is sent over the WebSocket, to Discord,
/// or to Twitch chat — those payloads are out-of-band of the user's screen.
nonisolated enum StreamerMode {

    /// Placeholder style — chosen so the redacted glyph hints at the value
    /// shape it replaces.
    enum Style {
        case url
        case token
        case channel
        case generic
    }

    /// The value to show in the UI for `value` given the current mode.
    ///
    /// - Returns: `value` unchanged when `isOn == false`; otherwise a
    ///   placeholder appropriate for `style`. An empty input is returned
    ///   unchanged so views can still render the "not set" empty state.
    ///
    /// Placeholders always name **why** the value is hidden so a viewer on
    /// camera (or a confused user) immediately knows it's Streamer Mode
    /// masking the value, not a bug or empty state.
    static func mask(_ value: String, style: Style, isOn: Bool) -> String {
        guard isOn, !value.isEmpty else { return value }
        switch style {
        case .url:     return "hidden — streamer mode"
        case .token:   return "hidden — streamer mode"
        case .channel: return "hidden"
        case .generic: return "hidden"
        }
    }

    /// Live UserDefaults read. Prefer `@AppStorage` inside SwiftUI views so the
    /// view re-renders on flip; this is for non-SwiftUI call sites (AppKit
    /// menu rebuild, plain-Swift helpers).
    static var isEnabled: Bool {
        FeatureFlags.streamerModeEnabled
    }
}
