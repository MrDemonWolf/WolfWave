//
//  NotificationPayloads.swift
//  WolfWave
//
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

//  Typed payload helpers for NotificationCenter.
//
//  `AppConstants+Notifications.swift` centralizes the notification *names*.
//  This file centralizes the *payloads* — the `userInfo` dictionaries that
//  used to be hand-built (and hand-decoded) at every call site. Each notification
//  that carries data gets a typed `post…` method on `NotificationCenter` plus a
//  matching typed accessor on `Notification`, so the string keys and value casts
//  live in exactly one place.
//
//  Posters and decoders share the key constants in `NotificationKeys`, so a key
//  rename can't silently desync the two sides.

/// String keys used inside notification `userInfo` dictionaries.
enum NotificationKeys {
    nonisolated static let track = "track"
    nonisolated static let artist = "artist"
    nonisolated static let album = "album"
    nonisolated static let playlist = "playlist"
    nonisolated static let isPaused = "isPaused"
    nonisolated static let enabled = "enabled"
    nonisolated static let widgetHTTPEnabled = "widgetHTTPEnabled"
    nonisolated static let port = "port"
    nonisolated static let state = "state"
    nonisolated static let clients = "clients"
    nonisolated static let isConnected = "isConnected"
    nonisolated static let error = "error"
    nonisolated static let section = "section"
    nonisolated static let mode = "mode"
    nonisolated static let isReducedMode = "isReducedMode"
    nonisolated static let count = "count"
    nonisolated static let needed = "needed"
    nonisolated static let isUpdateAvailable = "isUpdateAvailable"
    nonisolated static let latestVersion = "latestVersion"
    nonisolated static let releaseURL = "releaseURL"
}

// MARK: - Typed Posters

extension NotificationCenter {

    /// Posts `.nowPlayingChanged` with the current track metadata. Omitted
    /// (`nil`) string fields are left out of the payload, matching the prior
    /// hand-built behavior; `isPaused` is always included.
    nonisolated func postNowPlaying(
        track: String?,
        artist: String?,
        album: String?,
        playlist: String? = nil,
        isPaused: Bool = false
    ) {
        var info: [String: Any] = [:]
        if let track { info[NotificationKeys.track] = track }
        if let artist { info[NotificationKeys.artist] = artist }
        if let album { info[NotificationKeys.album] = album }
        if let playlist { info[NotificationKeys.playlist] = playlist }
        info[NotificationKeys.isPaused] = isPaused
        post(name: .nowPlayingChanged, object: nil, userInfo: info)
    }

    /// Posts `.discordStateChanged` with a connection-state raw value.
    nonisolated func postDiscordState(_ rawValue: String) {
        post(name: .discordStateChanged, object: nil, userInfo: [NotificationKeys.state: rawValue])
    }

    /// Posts a notification carrying only an `enabled` flag. Used by the many
    /// per-feature toggles (`.discordPresenceSettingsChanged`,
    /// `.songRequestSettingChanged`, `.listeningHistorySettingChanged`, etc.).
    nonisolated func postEnabled(_ name: NSNotification.Name, enabled: Bool) {
        post(name: name, object: nil, userInfo: [NotificationKeys.enabled: enabled])
    }

    /// Posts `.dockVisibilityChanged` with the new visibility mode raw value.
    nonisolated func postDockVisibility(mode: String) {
        post(name: .dockVisibilityChanged, object: nil, userInfo: [NotificationKeys.mode: mode])
    }

    /// Posts `.powerStateChanged` with the reduced-mode flag.
    nonisolated func postPowerState(isReducedMode: Bool) {
        post(name: .powerStateChanged, object: nil, userInfo: [NotificationKeys.isReducedMode: isReducedMode])
    }

    /// Posts `.websocketServerChanged`. All parameters are optional because the
    /// notification is used both to nudge a port change and to flip the enabled
    /// flags; only the supplied keys are attached. With no arguments it posts a
    /// bare signal (matching the prior `userInfo: nil` call).
    nonisolated func postWebSocketServerChanged(
        enabled: Bool? = nil,
        widgetHTTPEnabled: Bool? = nil,
        port: UInt16? = nil
    ) {
        var info: [String: Any] = [:]
        if let enabled { info[NotificationKeys.enabled] = enabled }
        if let widgetHTTPEnabled { info[NotificationKeys.widgetHTTPEnabled] = widgetHTTPEnabled }
        if let port { info[NotificationKeys.port] = port }
        post(name: .websocketServerChanged, object: nil, userInfo: info.isEmpty ? nil : info)
    }

    /// Posts `.websocketServerStateChanged` with the lifecycle state and the
    /// connected client count.
    nonisolated func postWebSocketServerState(_ state: String, clients: Int) {
        post(
            name: .websocketServerStateChanged,
            object: nil,
            userInfo: [NotificationKeys.state: state, NotificationKeys.clients: clients]
        )
    }

    /// Posts `.twitchConnectionStateChanged` with the connection flag and an
    /// optional error message.
    nonisolated func postTwitchConnectionState(isConnected: Bool, error: String? = nil) {
        var info: [String: Any] = [NotificationKeys.isConnected: isConnected]
        if let error { info[NotificationKeys.error] = error }
        post(name: .twitchConnectionStateChanged, object: nil, userInfo: info)
    }

    /// Posts `.updateStateChanged` describing update availability.
    nonisolated func postUpdateState(isUpdateAvailable: Bool, latestVersion: String, releaseURL: String? = nil) {
        var info: [String: Any] = [
            NotificationKeys.isUpdateAvailable: isUpdateAvailable,
            NotificationKeys.latestVersion: latestVersion,
        ]
        if let releaseURL { info[NotificationKeys.releaseURL] = releaseURL }
        post(name: .updateStateChanged, object: nil, userInfo: info)
    }

    /// Posts `.openSettingsSection` requesting navigation to a settings pane.
    nonisolated func postOpenSettingsSection(_ section: String) {
        post(name: .openSettingsSection, object: nil, userInfo: [NotificationKeys.section: section])
    }

    /// Posts `.voteSkipStateChanged`. Passing `nil` clears the indicator (no
    /// active session) by posting an empty payload.
    nonisolated func postVoteSkipState(_ state: (count: Int, needed: Int)?) {
        var info: [String: Any] = [:]
        if let state {
            info[NotificationKeys.count] = state.count
            info[NotificationKeys.needed] = state.needed
        }
        post(name: .voteSkipStateChanged, object: nil, userInfo: info.isEmpty ? nil : info)
    }
}

// MARK: - Typed Decoders

extension Notification {

    /// Now-playing metadata from `.nowPlayingChanged`.
    nonisolated var nowPlaying: (track: String?, artist: String?, album: String?, playlist: String?, isPaused: Bool) {
        (
            userInfo?[NotificationKeys.track] as? String,
            userInfo?[NotificationKeys.artist] as? String,
            userInfo?[NotificationKeys.album] as? String,
            userInfo?[NotificationKeys.playlist] as? String,
            userInfo?[NotificationKeys.isPaused] as? Bool ?? false
        )
    }

    /// The `enabled` flag, when present.
    nonisolated var enabledFlag: Bool? { userInfo?[NotificationKeys.enabled] as? Bool }

    /// The `widgetHTTPEnabled` flag, when present.
    nonisolated var widgetHTTPEnabledFlag: Bool? { userInfo?[NotificationKeys.widgetHTTPEnabled] as? Bool }

    /// The `port` value, when present.
    nonisolated var portValue: UInt16? { userInfo?[NotificationKeys.port] as? UInt16 }

    /// A connection/lifecycle `state` raw value, when present.
    nonisolated var stateString: String? { userInfo?[NotificationKeys.state] as? String }

    /// The connected `clients` count, when present.
    nonisolated var clientsCount: Int? { userInfo?[NotificationKeys.clients] as? Int }

    /// The `isConnected` flag, when present.
    nonisolated var isConnectedFlag: Bool? { userInfo?[NotificationKeys.isConnected] as? Bool }

    /// An `error` message string, when present.
    nonisolated var errorMessage: String? { userInfo?[NotificationKeys.error] as? String }

    /// The target settings `section` raw value, when present.
    nonisolated var sectionString: String? { userInfo?[NotificationKeys.section] as? String }

    /// The dock/app-visibility `mode` raw value, when present.
    nonisolated var modeString: String? { userInfo?[NotificationKeys.mode] as? String }

    /// The `isReducedMode` flag, when present.
    nonisolated var isReducedModeFlag: Bool? { userInfo?[NotificationKeys.isReducedMode] as? Bool }

    /// Vote-skip progress from `.voteSkipStateChanged`, or `nil` when cleared.
    nonisolated var voteSkipState: (count: Int, needed: Int)? {
        guard let count = userInfo?[NotificationKeys.count] as? Int,
              let needed = userInfo?[NotificationKeys.needed] as? Int else { return nil }
        return (count, needed)
    }

    /// Update-availability payload from `.updateStateChanged`, when complete.
    nonisolated var updateState: (isUpdateAvailable: Bool, latestVersion: String, releaseURL: String?)? {
        guard let available = userInfo?[NotificationKeys.isUpdateAvailable] as? Bool,
              let version = userInfo?[NotificationKeys.latestVersion] as? String else { return nil }
        return (available, version, userInfo?[NotificationKeys.releaseURL] as? String)
    }
}
