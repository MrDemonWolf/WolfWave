//
//  Preferences.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-28.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Typed accessors for the non-boolean preference values persisted in
/// `UserDefaults` (strings, ints, and "may not be set yet" objects).
///
/// Sibling to ``FeatureFlags`` (which covers booleans). Centralizes the
/// repeated `UserDefaults.standard.string(forKey:)` /
/// `UserDefaults.standard.integer(forKey:)` pattern so default semantics and
/// fallbacks live in one place — adding a new pref means one property here
/// rather than hunting for the matching read/write across `AppDelegate+*`,
/// `WolfWaveApp`, and the settings views.
///
/// Conventions:
/// - Read-only computed properties expose the current value with the right
///   default.
/// - Mutating writes are exposed as plain `static func set…(…)` so call sites
///   are searchable and intent is explicit.
nonisolated enum Preferences {

    private static var defaults: Foundation.UserDefaults { .standard }

    // MARK: - Defaulted Primitive Reads

    /// Reads an integer preference, substituting `defaultValue` when the key is
    /// unset or stored as a non-positive sentinel (`0`).
    ///
    /// Centralizes the `let stored = …integer(forKey:); stored > 0 ? stored : default`
    /// idiom that was duplicated across the queue, vote, and request services.
    static func int(_ key: String, default defaultValue: Int) -> Int {
        let stored = defaults.integer(forKey: key)
        return stored > 0 ? stored : defaultValue
    }

    /// Reads a boolean preference, substituting `defaultValue` when the key has
    /// never been written.
    ///
    /// Distinct from `defaults.bool(forKey:)`, which collapses "unset" to
    /// `false`. Use this when the default is `true` or when "unset" must be
    /// distinguished from an explicit `false`.
    static func bool(_ key: String, default defaultValue: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultValue
    }

    /// Reads a double preference, substituting `defaultValue` when the key has
    /// never been written.
    static func double(_ key: String, default defaultValue: Double) -> Double {
        defaults.object(forKey: key) as? Double ?? defaultValue
    }

    // MARK: - Twitch

    /// Lower-cased Twitch channel name configured in Settings. Empty when the
    /// user has not entered one yet.
    static var twitchChannelName: String {
        defaults.string(forKey: AppConstants.UserDefaults.twitchChannelName) ?? ""
    }

    /// Whether the most recent EventSub connection failed in a way that
    /// requires the user to re-authorize Twitch.
    static var twitchReauthNeeded: Bool {
        defaults.bool(forKey: AppConstants.UserDefaults.twitchReauthNeeded)
    }

    static func setTwitchReauthNeeded(_ value: Bool) {
        defaults.set(value, forKey: AppConstants.UserDefaults.twitchReauthNeeded)
    }

    // MARK: - WebSocket / Widget

    /// Port the embedded WebSocket server should listen on. `0` means "use the
    /// default" — callers are expected to substitute `AppConstants.WebSocket.defaultPort`.
    static var websocketServerPort: Int {
        defaults.integer(forKey: AppConstants.UserDefaults.websocketServerPort)
    }

    /// Port the embedded widget HTTP server should listen on. `0` means "use
    /// the default" — callers substitute `AppConstants.WebSocket.defaultWidgetPort`.
    static var widgetPort: Int {
        defaults.integer(forKey: AppConstants.UserDefaults.widgetPort)
    }

    static func setWebSocketEnabled(_ value: Bool) {
        defaults.set(value, forKey: AppConstants.UserDefaults.websocketEnabled)
    }

    static func setWidgetHTTPEnabled(_ value: Bool) {
        defaults.set(value, forKey: AppConstants.UserDefaults.widgetHTTPEnabled)
    }

    // MARK: - Settings / UI

    /// Currently-selected sidebar section in the Settings window. `nil` when
    /// the user has not navigated yet.
    static var selectedSettingsSection: String? {
        defaults.string(forKey: AppConstants.UserDefaults.selectedSettingsSection)
    }

    static func setSelectedSettingsSection(_ value: String) {
        defaults.set(value, forKey: AppConstants.UserDefaults.selectedSettingsSection)
    }

    /// Dock visibility mode persisted by the App Visibility setting (raw value).
    static var dockVisibility: String? {
        defaults.string(forKey: AppConstants.UserDefaults.dockVisibility)
    }

    // MARK: - Onboarding / What's New

    static var hasCompletedOnboarding: Bool {
        defaults.bool(forKey: AppConstants.UserDefaults.hasCompletedOnboarding)
    }

    static var lastSeenWhatsNewVersion: String {
        defaults.string(forKey: AppConstants.UserDefaults.lastSeenWhatsNewVersion) ?? ""
    }

    static func setLastSeenWhatsNewVersion(_ version: String) {
        defaults.set(version, forKey: AppConstants.UserDefaults.lastSeenWhatsNewVersion)
    }

    // MARK: - Tracking First-Launch Default

    /// First-launch default for music tracking. Returns `true` when the key has
    /// never been written; idempotent on subsequent calls.
    @discardableResult
    static func seedTrackingEnabledDefaultIfNeeded() -> Bool {
        let key = AppConstants.UserDefaults.trackingEnabled
        if defaults.object(forKey: key) == nil {
            defaults.set(true, forKey: key)
            return true
        }
        return false
    }
}
