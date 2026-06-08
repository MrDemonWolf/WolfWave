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
/// Moderators and the broadcaster always bypass these restrictions. The
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

    /// Convenience overload that reads roles straight off a `BotCommandContext`.
    ///
    /// This is the single permission chokepoint reused everywhere a chat sender's
    /// request must be gated, so the badge-to-policy mapping lives in one place.
    ///
    /// - Parameter context: The chat sender's context (badges + identity).
    /// - Returns: `true` when the sender may request under this audience.
    func permits(_ context: BotCommandContext) -> Bool {
        permits(
            isSubscriber: context.isSubscriber,
            isVIP: context.isVIP,
            isModerator: context.isModerator,
            isBroadcaster: context.isBroadcaster
        )
    }
}

// MARK: - RequestSource

/// The channel through which a song request arrived.
///
/// Determines how the request is gated and how the outcome is acknowledged.
enum RequestSource {
    /// Requested via the `!sr` chat command, gated by `RequestAudience`.
    case chatCommand(BotCommandContext)
    /// Redeemed with channel points via a WolfWave-managed custom reward.
    case channelPoints(redemptionID: String, rewardID: String)
    /// Requested with a bit cheer of the given amount.
    case bits(amount: Int)
}

// MARK: - SongRequestPreset

/// One-tap request-policy presets shown as chips in settings.
///
/// The active preset is stored explicitly (`songRequestPolicyMode`) rather than
/// inferred from the individual toggles, so the highlighted chip is always
/// deterministic and `.custom` can be selected on purpose to reveal the
/// fine-grained audience dropdown. Presets only drive the **chat** side of
/// requests (whether `!sr` is on and who it's for); channel-point and bit
/// toggles stay under the streamer's manual control in the Redemptions card,
/// except `.channelPointsOnly`, whose whole purpose is to flip to the points
/// path.
enum SongRequestPreset: String, CaseIterable, Identifiable {
    /// `!sr` open to everyone. Bits boost the cheerer's queued song.
    case open
    /// `!sr` for subscribers only.
    case subsOnly
    /// `!sr` off; requests come from the channel-point reward.
    case channelPointsOnly
    /// Manual configuration; reveals the audience dropdown.
    case custom

    var id: String { rawValue }

    /// Short label for the preset chip.
    var displayName: String {
        switch self {
        case .open: return "Open"
        case .subsOnly: return "Sub Only"
        case .channelPointsOnly: return "Channel Point Only"
        case .custom: return "Custom"
        }
    }

    /// One-line explanation of what the preset does.
    var summary: String {
        switch self {
        case .open: return "Anyone can request: !sr, channel points, or bits. Bits bump a song to the front."
        case .subsOnly: return "Only subscribers can request. Channel points and bits are off."
        case .channelPointsOnly: return "!sr is off. Viewers redeem the channel-point reward to request."
        case .custom: return "Fine-tune exactly who can use !sr below."
        }
    }

    /// Writes this preset's full configuration (chat command, audience, and the
    /// channel-point / bit redemption toggles) into `UserDefaults`.
    ///
    /// Always records the active mode. `.custom` records the mode only and leaves
    /// every other setting intact so the streamer can fine-tune by hand.
    ///
    /// Toggling the redemption flags only changes preferences; the caller is
    /// responsible for re-running `refreshRedemptionSubscriptions()` so the
    /// managed Twitch reward is actually created or torn down. The settings
    /// Access card does this after every `apply(_:)`.
    func apply(to defaults: Foundation.UserDefaults = .standard) {
        defaults.set(rawValue, forKey: AppConstants.UserDefaults.songRequestPolicyMode)
        switch self {
        case .open:
            defaults.set(true, forKey: AppConstants.UserDefaults.srCommandEnabled)
            defaults.set(RequestAudience.everyone.rawValue, forKey: AppConstants.UserDefaults.songRequestChatAudience)
            defaults.set(true, forKey: AppConstants.UserDefaults.songRequestChannelPointsEnabled)
            defaults.set(true, forKey: AppConstants.UserDefaults.songRequestBitsEnabled)
            // Bits bump the cheerer's queued song to the front under Open.
            defaults.set(true, forKey: AppConstants.UserDefaults.songRequestBitsBoostEnabled)
        case .subsOnly:
            defaults.set(true, forKey: AppConstants.UserDefaults.srCommandEnabled)
            defaults.set(RequestAudience.subscribers.rawValue, forKey: AppConstants.UserDefaults.songRequestChatAudience)
            defaults.set(false, forKey: AppConstants.UserDefaults.songRequestChannelPointsEnabled)
            defaults.set(false, forKey: AppConstants.UserDefaults.songRequestBitsEnabled)
        case .channelPointsOnly:
            defaults.set(false, forKey: AppConstants.UserDefaults.srCommandEnabled)
            defaults.set(true, forKey: AppConstants.UserDefaults.songRequestChannelPointsEnabled)
            defaults.set(false, forKey: AppConstants.UserDefaults.songRequestBitsEnabled)
        case .custom:
            break
        }
    }

    /// The active preset, read from the stored mode.
    ///
    /// On a fresh install or a pre-mode upgrade (no stored value) the chat
    /// settings are inferred so an existing config maps to a sensible chip;
    /// a brand-new install lands on `.open`.
    static func current(in defaults: Foundation.UserDefaults = .standard) -> SongRequestPreset {
        if let raw = defaults.string(forKey: AppConstants.UserDefaults.songRequestPolicyMode),
           let stored = SongRequestPreset(rawValue: raw) {
            return stored
        }

        let srEnabled = defaults.object(forKey: AppConstants.UserDefaults.srCommandEnabled) as? Bool ?? true
        let audience = RequestAudience(
            rawValue: defaults.string(forKey: AppConstants.UserDefaults.songRequestChatAudience) ?? ""
        ) ?? .everyone
        let channelPoints = defaults.bool(forKey: AppConstants.UserDefaults.songRequestChannelPointsEnabled)

        if !srEnabled { return channelPoints ? .channelPointsOnly : .custom }
        switch audience {
        case .everyone: return .open
        case .subscribers: return .subsOnly
        case .vipsAndSubs, .modsOnly: return .custom
        }
    }
}

// MARK: - QueueLimitMode

/// How the per-role queue limits combine for a viewer who holds more than one
/// role. Persisted as a raw `String` so it can back an `@AppStorage` property.
enum QueueLimitMode: String, CaseIterable, Identifiable {
    /// The viewer gets the largest single limit among the roles they hold.
    case highest
    /// The viewer gets the sum of the limits for every role they hold.
    case stacked

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .highest: return "Highest tier"
        case .stacked: return "Stacked"
        }
    }

    var summary: String {
        switch self {
        case .highest: return "A viewer gets the limit of their best role."
        case .stacked: return "Limits add up across every role a viewer holds."
        }
    }
}

// MARK: - SongRequestLimits

/// Resolves a requester's effective per-user queue limit from the configured
/// per-role limits and the combine mode. Shared so the chat command, channel
/// points, and bits all compute the same cap.
enum SongRequestLimits {

    /// The configured combine mode (defaults to `.highest`).
    static func mode(in defaults: Foundation.UserDefaults = .standard) -> QueueLimitMode {
        QueueLimitMode(rawValue: defaults.string(forKey: AppConstants.UserDefaults.songRequestLimitStackMode) ?? "")
            ?? .highest
    }

    /// The effective number of simultaneous queued requests allowed for a viewer
    /// with the given roles.
    ///
    /// The "everyone" tier always applies; subscriber/VIP/mod tiers add to the
    /// pool when the viewer holds that badge (the broadcaster counts as a mod).
    /// In `.highest` mode the largest applicable tier wins; in `.stacked` mode
    /// the applicable tiers are summed.
    static func effectiveLimit(
        isSubscriber: Bool,
        isVIP: Bool,
        isModerator: Bool,
        isBroadcaster: Bool,
        in defaults: Foundation.UserDefaults = .standard
    ) -> Int {
        let everyone = defaults.object(forKey: AppConstants.UserDefaults.songRequestPerUserLimit) as? Int ?? 2
        let sub = defaults.object(forKey: AppConstants.UserDefaults.songRequestLimitSubscriber) as? Int ?? 2
        let vip = defaults.object(forKey: AppConstants.UserDefaults.songRequestLimitVIP) as? Int ?? 2
        let mod = defaults.object(forKey: AppConstants.UserDefaults.songRequestLimitModerator) as? Int ?? 2

        var applicable = [everyone]
        if isSubscriber { applicable.append(sub) }
        if isVIP { applicable.append(vip) }
        if isModerator || isBroadcaster { applicable.append(mod) }

        switch mode(in: defaults) {
        case .highest: return applicable.max() ?? everyone
        case .stacked: return applicable.reduce(0, +)
        }
    }

    /// Effective limit for a requester arriving via a non-chat source (channel
    /// points / bits), where no chat badges are available. Uses the everyone tier.
    static func nonChatLimit(in defaults: Foundation.UserDefaults = .standard) -> Int {
        effectiveLimit(
            isSubscriber: false, isVIP: false, isModerator: false, isBroadcaster: false, in: defaults)
    }
}

// MARK: - RedemptionStatus

/// Health of the channel-point / bit redemption integration. Drives the
/// re-authentication banner in song request settings. Persisted as a raw
/// `String` so it can back an `@AppStorage` property.
enum RedemptionStatus: String {
    /// Redemptions are working (or not in use).
    case ok
    /// The signed-in token is missing the redemption OAuth scopes. Re-auth needed.
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

// MARK: - PlaylistSetupStatus

/// Health of the song-request playlist setup. Drives the top-of-pane "needs
/// setup again" banner and the fallback policy when the streamer's playlist
/// gets deleted or un-shared. Persisted as a raw `String` so it can back an
/// `@AppStorage` property. Same shape as `RedemptionStatus`.
///
/// Two failure tiers, on purpose:
/// - **Essential** (`playlistMissing`, `musicAccessLost`): nothing can play, so
///   the live feature is held and the banner walks the streamer back through
///   setup.
/// - **Cosmetic** (`linkUnshared`): only the `!playlist` link is dead, so just
///   that command is turned off. `!sr`, channel points, and bits keep working,
///   never killing a live stream over a broken link.
enum PlaylistSetupStatus: String {
    /// Working, or setup not started yet. No banner.
    case ok
    /// The WolfWave Requests playlist is gone and couldn't be rebuilt.
    case playlistMissing
    /// A song-list link was set but the playlist is no longer public.
    case linkUnshared
    /// Apple Music access (or an active subscription) is no longer available.
    case musicAccessLost

    /// Banner message shown at the top of the pane, or `nil` when healthy.
    var bannerMessage: String? {
        switch self {
        case .ok:
            return nil
        case .playlistMissing:
            return "Your WolfWave Requests playlist is gone. Set up song requests again to rebuild it."
        case .linkUnshared:
            return "Your song list link stopped working. Re-share your requests playlist so !playlist works again."
        case .musicAccessLost:
            return "WolfWave lost access to Apple Music. Grant access again to keep song requests playing."
        }
    }

    /// Whether the break stops the whole feature (essential) rather than just the
    /// `!playlist` link (cosmetic). Essential breaks hold the live feature and
    /// re-engage the setup gate; cosmetic breaks leave requests flowing.
    var isEssential: Bool {
        switch self {
        case .ok, .linkUnshared:
            return false
        case .playlistMissing, .musicAccessLost:
            return true
        }
    }

    /// Primary-action label for the banner button, or `nil` when healthy.
    var actionLabel: String? {
        switch self {
        case .ok:
            return nil
        case .playlistMissing:
            return "Set Up Again"
        case .linkUnshared:
            return "Re-share Playlist"
        case .musicAccessLost:
            return "Grant Access"
        }
    }

    /// Banner tint. Essential breaks read as errors; the cosmetic link break is a
    /// softer warning.
    var isError: Bool { isEssential }
}
