//
//  SongRequestAccess.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

// MARK: - RequestAudience

/// Who is allowed to request a song through the `!sr` chat command.
///
/// Moderators and the broadcaster always bypass these restrictions — the
/// audience only constrains regular viewers. Persisted as a raw `String` so it
/// can back an `@AppStorage` property.
enum RequestAudience: String, CaseIterable, Identifiable {
    /// Anyone in chat may request.
    case everyone
    /// Only subscribers may request.
    case subscribers
    /// Subscribers and VIPs may request.
    case vipsAndSubs
    /// Only moderators and the broadcaster may request.
    case modsOnly

    var id: String { rawValue }

    /// Short human-readable label for pickers.
    var displayName: String {
        switch self {
        case .everyone: return "Everyone"
        case .subscribers: return "Subscribers"
        case .vipsAndSubs: return "VIPs & Subscribers"
        case .modsOnly: return "Mods Only"
        }
    }

    /// Chat-facing reason shown when a viewer is not permitted to request.
    var denialMessage: String {
        switch self {
        case .everyone:
            return "Song requests aren't open right now."
        case .subscribers:
            return "Song requests are subscriber-only right now."
        case .vipsAndSubs:
            return "Song requests are for VIPs and subscribers right now."
        case .modsOnly:
            return "Only mods can request songs right now."
        }
    }

    /// Whether a viewer with the given Twitch roles may request a song.
    ///
    /// Moderators and the broadcaster are always permitted regardless of the
    /// configured audience.
    ///
    /// - Parameters:
    ///   - isSubscriber: Whether the viewer has a subscriber badge.
    ///   - isVIP: Whether the viewer has a VIP badge.
    ///   - isModerator: Whether the viewer has a moderator badge.
    ///   - isBroadcaster: Whether the viewer is the channel broadcaster.
    /// - Returns: `true` when the viewer may request.
    func permits(isSubscriber: Bool, isVIP: Bool, isModerator: Bool, isBroadcaster: Bool) -> Bool {
        if isModerator || isBroadcaster { return true }
        switch self {
        case .everyone: return true
        case .subscribers: return isSubscriber
        case .vipsAndSubs: return isSubscriber || isVIP
        case .modsOnly: return false
        }
    }
}

// MARK: - RequestSource

/// The channel through which a song request arrived.
///
/// Determines how the request is gated and how the outcome is acknowledged.
enum RequestSource {
    /// Requested via the `!sr` chat command — gated by `RequestAudience`.
    case chatCommand(BotCommandContext)
    /// Redeemed with channel points via a WolfWave-managed custom reward.
    case channelPoints(redemptionID: String, rewardID: String)
    /// Requested with a bit cheer of the given amount.
    case bits(amount: Int)
}

// MARK: - SongRequestPreset

/// One-tap configurations that set the chat audience and redemption toggles
/// together, so a streamer can switch the channel's request policy quickly.
enum SongRequestPreset: String, CaseIterable, Identifiable {
    /// `!sr` open to everyone, channel points and bits on.
    case open
    /// `!sr` for subscribers, channel points and bits still on (paid path for non-subs).
    case subsOnly
    /// `!sr` for subscribers only, channel points and bits off.
    case subsStrict
    /// `!sr` disabled, channel points and bits on.
    case paidOnly
    /// `!sr` for mods only, channel points and bits off.
    case locked

    var id: String { rawValue }

    /// Short label for the preset button.
    var displayName: String {
        switch self {
        case .open: return "Open"
        case .subsOnly: return "Subs Only"
        case .subsStrict: return "Subs Strict"
        case .paidOnly: return "Paid Only"
        case .locked: return "Locked"
        }
    }

    /// One-line explanation of what the preset does.
    var summary: String {
        switch self {
        case .open: return "Anyone can request — chat, points, or bits."
        case .subsOnly: return "!sr for subs; everyone else can pay with points or bits."
        case .subsStrict: return "Subscribers only — points and bits off."
        case .paidOnly: return "!sr off — requests come only from points or bits."
        case .locked: return "Only mods can request — redemptions off."
        }
    }

    /// Whether the `!sr` chat command is enabled under this preset.
    var chatCommandEnabled: Bool {
        switch self {
        case .open, .subsOnly, .subsStrict, .locked: return true
        case .paidOnly: return false
        }
    }

    /// The chat-command audience under this preset.
    var audience: RequestAudience {
        switch self {
        case .open, .paidOnly: return .everyone
        case .subsOnly, .subsStrict: return .subscribers
        case .locked: return .modsOnly
        }
    }

    /// Whether channel-point requests are enabled under this preset.
    var channelPointsEnabled: Bool {
        switch self {
        case .open, .subsOnly, .paidOnly: return true
        case .subsStrict, .locked: return false
        }
    }

    /// Whether bit-cheer requests are enabled under this preset.
    var bitsEnabled: Bool { channelPointsEnabled }

    /// Writes this preset's configuration into `UserDefaults`.
    func apply(to defaults: Foundation.UserDefaults = .standard) {
        defaults.set(chatCommandEnabled, forKey: AppConstants.UserDefaults.srCommandEnabled)
        defaults.set(audience.rawValue, forKey: AppConstants.UserDefaults.songRequestChatAudience)
        defaults.set(channelPointsEnabled, forKey: AppConstants.UserDefaults.songRequestChannelPointsEnabled)
        defaults.set(bitsEnabled, forKey: AppConstants.UserDefaults.songRequestBitsEnabled)
    }

    /// Returns the preset that matches the current `UserDefaults` state, or
    /// `nil` when the settings don't match any preset ("Custom").
    static func current(in defaults: Foundation.UserDefaults = .standard) -> SongRequestPreset? {
        let srEnabled = defaults.object(forKey: AppConstants.UserDefaults.srCommandEnabled) as? Bool ?? true
        let audience = RequestAudience(
            rawValue: defaults.string(forKey: AppConstants.UserDefaults.songRequestChatAudience) ?? ""
        ) ?? .everyone
        let channelPoints = defaults.bool(forKey: AppConstants.UserDefaults.songRequestChannelPointsEnabled)
        let bits = defaults.bool(forKey: AppConstants.UserDefaults.songRequestBitsEnabled)

        return allCases.first { preset in
            preset.chatCommandEnabled == srEnabled
                && preset.audience == audience
                && preset.channelPointsEnabled == channelPoints
                && preset.bitsEnabled == bits
        }
    }
}

// MARK: - RedemptionStatus

/// Health of the channel-point / bit redemption integration. Drives the
/// re-authentication banner in song request settings. Persisted as a raw
/// `String` so it can back an `@AppStorage` property.
enum RedemptionStatus: String {
    /// Redemptions are working (or not in use).
    case ok
    /// The signed-in token is missing the redemption OAuth scopes — re-auth needed.
    case scopeMissing
    /// The signed-in account is not the broadcaster, so it cannot read redemptions.
    case botAccount
    /// An EventSub subscription request was rejected by Twitch.
    case subscribeFailed

    /// Banner message shown to the streamer, or `nil` when everything is fine.
    var bannerMessage: String? {
        switch self {
        case .ok:
            return nil
        case .scopeMissing:
            return "Reconnect with Twitch to grant channel-point and bits access."
        case .botAccount:
            return "Channel-point and bit requests need you to sign in with your broadcaster account, not a separate bot account."
        case .subscribeFailed:
            return "WolfWave couldn't subscribe to redemption events. Try reconnecting to Twitch."
        }
    }
}
