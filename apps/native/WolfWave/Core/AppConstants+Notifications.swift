//
//  AppConstants+Notifications.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
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
    nonisolated static let trackingSettingChanged = NSNotification.Name(AppConstants.Notifications.trackingSettingChanged)
    nonisolated static let dockVisibilityChanged = NSNotification.Name(AppConstants.Notifications.dockVisibilityChanged)
    nonisolated static let twitchReauthNeededChanged = NSNotification.Name(AppConstants.Notifications.twitchReauthNeededChanged)
    nonisolated static let discordPresenceChanged = NSNotification.Name(AppConstants.Notifications.discordPresenceChanged)
    nonisolated static let discordStateChanged = NSNotification.Name(AppConstants.Notifications.discordStateChanged)
    nonisolated static let discordPresenceSettingsChanged = NSNotification.Name(AppConstants.Notifications.discordPresenceSettingsChanged)
    nonisolated static let nowPlayingChanged = NSNotification.Name(AppConstants.Notifications.nowPlayingChanged)
    nonisolated static let updateStateChanged = NSNotification.Name(AppConstants.Notifications.updateStateChanged)
    nonisolated static let websocketServerChanged = NSNotification.Name(AppConstants.Notifications.websocketServerChanged)
    nonisolated static let websocketServerStateChanged = NSNotification.Name(AppConstants.Notifications.websocketServerStateChanged)
    nonisolated static let widgetHTTPServerChanged = NSNotification.Name(AppConstants.Notifications.widgetHTTPServerChanged)
    nonisolated static let powerStateChanged = NSNotification.Name(AppConstants.Notifications.powerStateChanged)
    nonisolated static let twitchConnectionStateChanged = NSNotification.Name(AppConstants.Notifications.twitchConnectionStateChanged)
    nonisolated static let songRequestSettingChanged = NSNotification.Name(AppConstants.Notifications.songRequestSettingChanged)
    nonisolated static let songRequestQueueChanged = NSNotification.Name(AppConstants.Notifications.songRequestQueueChanged)
    nonisolated static let songRequestHoldChanged = NSNotification.Name(AppConstants.Notifications.songRequestHoldChanged)
    nonisolated static let voteSkipStateChanged = NSNotification.Name(AppConstants.Notifications.voteSkipStateChanged)
    nonisolated static let musicPermissionDenied = NSNotification.Name(AppConstants.Notifications.musicPermissionDenied)
    nonisolated static let openSettingsSection = NSNotification.Name(AppConstants.Notifications.openSettingsSection)
    nonisolated static let listeningHistorySettingChanged = NSNotification.Name(AppConstants.Notifications.listeningHistorySettingChanged)
    nonisolated static let streamerModeChanged = NSNotification.Name(AppConstants.Notifications.streamerModeChanged)
}
