//
//  AppConstants+Notifications.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 4/13/26.
//

import Foundation

/// Typed `NSNotification.Name` constants for all WolfWave notifications.
///
/// Use these instead of `NSNotification.Name(AppConstants.Notifications.xxx)` to eliminate
/// the verbose string-wrapping boilerplate at every call site.
///
/// Example:
/// ```swift
/// // Before
/// NotificationCenter.default.publisher(for: NSNotification.Name(AppConstants.Notifications.nowPlayingChanged))
/// // After
/// NotificationCenter.default.publisher(for: .nowPlayingChanged)
/// ```
extension NSNotification.Name {
    static let trackingSettingChanged = NSNotification.Name(AppConstants.Notifications.trackingSettingChanged)
    static let dockVisibilityChanged = NSNotification.Name(AppConstants.Notifications.dockVisibilityChanged)
    static let twitchReauthNeededChanged = NSNotification.Name(AppConstants.Notifications.twitchReauthNeededChanged)
    static let discordPresenceChanged = NSNotification.Name(AppConstants.Notifications.discordPresenceChanged)
    static let discordStateChanged = NSNotification.Name(AppConstants.Notifications.discordStateChanged)
    static let nowPlayingChanged = NSNotification.Name(AppConstants.Notifications.nowPlayingChanged)
    static let updateStateChanged = NSNotification.Name(AppConstants.Notifications.updateStateChanged)
    static let websocketServerChanged = NSNotification.Name(AppConstants.Notifications.websocketServerChanged)
    static let websocketServerStateChanged = NSNotification.Name(AppConstants.Notifications.websocketServerStateChanged)
    static let widgetHTTPServerChanged = NSNotification.Name(AppConstants.Notifications.widgetHTTPServerChanged)
    static let powerStateChanged = NSNotification.Name(AppConstants.Notifications.powerStateChanged)
    static let twitchConnectionStateChanged = NSNotification.Name(AppConstants.Notifications.twitchConnectionStateChanged)
    static let songRequestSettingChanged = NSNotification.Name(AppConstants.Notifications.songRequestSettingChanged)
    static let songRequestQueueChanged = NSNotification.Name(AppConstants.Notifications.songRequestQueueChanged)
}
