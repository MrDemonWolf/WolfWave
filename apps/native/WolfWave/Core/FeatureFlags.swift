//
//  FeatureFlags.swift
//  WolfWave
//
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Typed accessors for the boolean feature toggles persisted in `UserDefaults`.
///
/// Centralizes the repeated `UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.…)`
/// pattern so default semantics are defined once. Adding a new toggle means adding
/// one computed property here rather than hunting for every read site.
nonisolated enum FeatureFlags {
    private static var defaults: Foundation.UserDefaults { .standard }

    // MARK: Integrations

    static var discordEnabled: Bool {
        defaults.bool(forKey: AppConstants.UserDefaults.discordPresenceEnabled)
    }

    static var websocketEnabled: Bool {
        defaults.bool(forKey: AppConstants.UserDefaults.websocketEnabled)
    }

    /// Reads as `Bool?` first to distinguish "never set" from "explicitly false",
    /// matching the original mixed-cast behavior in `AppDelegate+Services`.
    static var widgetHTTPEnabled: Bool {
        defaults.object(forKey: AppConstants.UserDefaults.widgetHTTPEnabled) as? Bool ?? false
    }

    // MARK: Tracking & history

    /// Music tracking. Defaults to `true` on first launch; once `trackingEnabled`
    /// has been explicitly written it returns the stored value.
    static var trackingEnabled: Bool {
        if defaults.object(forKey: AppConstants.UserDefaults.trackingEnabled) == nil {
            return true
        }
        return defaults.bool(forKey: AppConstants.UserDefaults.trackingEnabled)
    }

    static var listeningHistoryEnabled: Bool {
        defaults.bool(forKey: AppConstants.UserDefaults.listeningHistoryEnabled)
    }

    // MARK: Song request

    static var songRequestEnabled: Bool {
        defaults.bool(forKey: AppConstants.UserDefaults.songRequestEnabled)
    }

    static var songCommandSongLinkEnabled: Bool {
        defaults.bool(forKey: AppConstants.UserDefaults.songCommandSongLinkEnabled)
    }

    static var songChangeNotificationsEnabled: Bool {
        defaults.bool(forKey: AppConstants.UserDefaults.songChangeNotificationsEnabled)
    }

    // MARK: UI

    static var streamerModeEnabled: Bool {
        defaults.bool(forKey: AppConstants.UserDefaults.streamerModeEnabled)
    }
}
