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
/// fallbacks live in one place. Adding a new pref means one property here
/// rather than hunting for the matching read/write across `AppDelegate+*`,
/// `WolfWaveApp`, and the settings views.
///
/// Conventions:
/// - Read-only computed properties expose the current value with the right
///   default.
/// - Mutating writes are exposed as plain `static func set…(…)` so call sites
///   are searchable and intent is explicit.
nonisolated enum Preferences {

    private static var defaults: Foundation.UserDefaults { DefaultsStore.store }

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

    /// Backup-restored channel waiting for a successful OAuth grant. This value
    /// is presentation/input state only; connection code reads canonical
    /// Keychain credentials instead.
    static var pendingImportedTwitchChannelName: String {
        defaults.string(
            forKey: AppConstants.UserDefaults.twitchPendingImportedChannelName
        ) ?? ""
    }

    static func clearPendingImportedTwitchChannelName() {
        defaults.removeObject(
            forKey: AppConstants.UserDefaults.twitchPendingImportedChannelName
        )
    }

    /// Public song-list URL echoed by the `!playlist` command (plus any
    /// user-configured aliases; see `SongListCommand`). Whitespace-trimmed;
    /// empty when the streamer hasn't shared one.
    static var songRequestSongListURL: String {
        (defaults.string(forKey: AppConstants.UserDefaults.songRequestSongListURL) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
    /// default": callers substitute `AppConstants.WebSocketServer.defaultPort`.
    static var websocketServerPort: Int {
        defaults.integer(forKey: AppConstants.UserDefaults.websocketServerPort)
    }

    /// Port the embedded widget HTTP server should listen on. `0` means "use
    /// the default": callers substitute `AppConstants.WebSocketServer.widgetDefaultPort`.
    static var widgetPort: Int {
        defaults.integer(forKey: AppConstants.UserDefaults.widgetPort)
    }

    /// The effective WebSocket server port as a `UInt16`, ready to bind.
    ///
    /// Resolves ``websocketServerPort``: unset/zero falls back to
    /// `AppConstants.WebSocketServer.defaultPort`, and any out-of-range stored
    /// value (a hand-edited plist or corrupted backup) is clamped instead of
    /// trapping. The single source of truth for this conversion; do not
    /// re-derive it at call sites.
    static var resolvedWebSocketServerPort: UInt16 {
        resolvePort(websocketServerPort, default: AppConstants.WebSocketServer.defaultPort)
    }

    /// The effective widget HTTP server port as a `UInt16`, ready to bind.
    ///
    /// Resolves ``widgetPort`` with the same semantics as
    /// ``resolvedWebSocketServerPort``, falling back to
    /// `AppConstants.WebSocketServer.widgetDefaultPort`.
    static var resolvedWidgetPort: UInt16 {
        resolvePort(widgetPort, default: AppConstants.WebSocketServer.widgetDefaultPort)
    }

    /// Shared port resolution: non-positive means "use the default"; anything
    /// else is clamped into `UInt16` range so a bad stored value can never trap.
    static func resolvePort(_ stored: Int, default defaultPort: UInt16) -> UInt16 {
        stored > 0 ? UInt16(clamping: stored) : defaultPort
    }

    // MARK: - Domain-Resolved Reads

    /// `stored` when it is one of `allowed`, otherwise `defaultValue`.
    ///
    /// Pure, so the UI layer can share it. See ``resolvedInt(_:default:)`` for
    /// why an out-of-domain value has to be caught before it reaches a control.
    static func resolveAllowed(_ stored: Int, allowed: Set<Int>, default defaultValue: Int) -> Int {
        allowed.contains(stored) ? stored : defaultValue
    }

    /// `stored` clamped into `range`; non-finite falls back to `defaultValue`.
    ///
    /// The `isFinite` check is the load-bearing half. `Int(Double.nan)` and
    /// `Int(1e300)` both trap, and a `Double` read out of `UserDefaults` is
    /// attacker-shaped in the sense that anything can put it there.
    static func resolveClamped(
        _ stored: Double,
        range: ClosedRange<Double>,
        default defaultValue: Double
    ) -> Double {
        stored.isFinite ? min(max(stored, range.lowerBound), range.upperBound) : defaultValue
    }

    /// Reads an integer preference validated against the domain declared for
    /// `key` in `AppConstants.UserDefaults.exportablePreferences`.
    ///
    /// Import validation already rejects out-of-domain values, but nothing
    /// guards a value that arrives another way: a hand-edited plist,
    /// `defaults write`, a key written by an older build, or a test process
    /// sharing the app's domain. Such a value reaching a SwiftUI `Picker` as its
    /// selection is not a cosmetic problem. The segmented style traps inside
    /// SwiftUI ("Double value cannot be converted to Int"), taking the whole
    /// settings window with it, after logging only
    /// `Picker: the selection "1" is invalid and does not have an associated tag`.
    ///
    /// Keys without a declared domain keep ``int(_:default:)`` semantics.
    static func resolvedInt(_ key: String, default defaultValue: Int) -> Int {
        guard case .int(let domain)? = AppConstants.UserDefaults.exportRule(for: key) else {
            return int(key, default: defaultValue)
        }
        // `integer(forKey:)` bridges a stored huge Double or string through
        // `NSNumber` without trapping, so the domain check below is what
        // actually rejects it.
        let stored = defaults.integer(forKey: key)
        switch domain {
        case .values(let allowed):
            return resolveAllowed(stored, allowed: allowed, default: defaultValue)
        case .zeroOrRange(let range):
            return stored == 0
                ? defaultValue
                : min(max(stored, range.lowerBound), range.upperBound)
        }
    }

    /// The `Double` sibling of ``resolvedInt(_:default:)``.
    ///
    /// NaN and infinity resolve to `defaultValue`; a finite value clamps into
    /// the declared range. Step is deliberately not enforced: import validation
    /// owns step, and clamping alone is what makes a downstream `Int(…)` total.
    static func resolvedDouble(_ key: String, default defaultValue: Double) -> Double {
        let stored = double(key, default: defaultValue)
        guard case .double(let domain)? = AppConstants.UserDefaults.exportRule(for: key) else {
            return stored.isFinite ? stored : defaultValue
        }
        return resolveClamped(stored, range: domain.range, default: defaultValue)
    }

    static func setWebSocketEnabled(_ value: Bool) {
        defaults.set(value, forKey: AppConstants.UserDefaults.websocketEnabled)
    }

    static func setWidgetHTTPEnabled(_ value: Bool) {
        defaults.set(value, forKey: AppConstants.UserDefaults.widgetHTTPEnabled)
    }

    // MARK: - Settings / UI

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
