//
//  MenuStatusFormatter.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 5/22/26.
//

import Foundation

/// Pure formatting helpers for the tray menu's connection-status subtitles
/// and the song-request collapse threshold.
///
/// Extracted from `AppDelegate+MenuBar.swift` so the logic can be unit
/// tested without spinning up AppKit / NSStatusItem.
enum MenuStatusFormatter {

    // MARK: - Sync Music

    /// Status string for the "Sync Music" tray item.
    /// - Parameter trackingEnabled: Whether music tracking is currently on.
    static func musicStatus(trackingEnabled: Bool) -> String {
        trackingEnabled ? "Tracking" : "Paused"
    }

    // MARK: - Twitch

    /// Status string for the "Twitch Chat" tray item.
    /// - Parameters:
    ///   - isConnected: Whether the bot is connected to the broadcaster's channel.
    ///   - channelName: Persisted channel name, or `nil` if none is saved.
    static func twitchStatus(isConnected: Bool, channelName: String?) -> String {
        if isConnected, let channelName, !channelName.isEmpty {
            return "@\(channelName)"
        }
        if let channelName, !channelName.isEmpty {
            return "Not connected"
        }
        return "No channel set"
    }

    // MARK: - Discord

    /// Discord IPC connection states surfaced in the tray.
    enum DiscordState: String {
        case connected
        case connecting
        case disconnected
    }

    /// Status string for the "Discord Status" tray item.
    /// - Parameters:
    ///   - enabled: Whether Discord Rich Presence is enabled in settings.
    ///   - state: Current IPC connection state.
    static func discordStatus(enabled: Bool, state: DiscordState) -> String {
        guard enabled else { return "Off" }
        switch state {
        case .connected: return "Connected"
        case .connecting: return "Reconnecting\u{2026}"
        case .disconnected: return "Disconnected"
        }
    }

    // MARK: - Stream Widgets

    /// Status string for the "Stream Widgets" tray item.
    /// - Parameters:
    ///   - enabled: Whether the websocket / widget HTTP servers are on.
    ///   - widgetPort: Port the widget HTTP server is listening on.
    ///   - clientCount: Number of overlays currently connected over the websocket.
    static func widgetsStatus(enabled: Bool, widgetPort: UInt16, clientCount: Int) -> String {
        guard enabled else { return "Off" }
        let viewers = clientCount == 1 ? "1 viewer" : "\(clientCount) viewers"
        return ":\(widgetPort) · \(viewers)"
    }

    // MARK: - Song Requests

    /// Whether the tray menu should collapse the song-request section into a
    /// `Song Requests ▸` submenu rather than rendering rows inline.
    ///
    /// Threshold: queue has ≥2 pending, OR ≥1 pending with something already
    /// playing. Below that the flat layout reads more like a status line and
    /// avoids an unnecessary submenu hop.
    /// - Parameters:
    ///   - queueCount: Number of pending song requests.
    ///   - hasNowPlaying: Whether a request is currently playing.
    static func shouldCollapseSongRequests(queueCount: Int, hasNowPlaying: Bool) -> Bool {
        if queueCount >= 2 { return true }
        if hasNowPlaying && queueCount >= 1 { return true }
        return false
    }
}
