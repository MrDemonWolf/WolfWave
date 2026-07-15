//
//  AppConstants+Twitch.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-07-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

extension AppConstants {
    /// Twitch API and integration constants.
    nonisolated enum Twitch {
        /// Base URL for Twitch Helix API endpoints
        static let apiBaseURL = "https://api.twitch.tv/helix"

        /// Settings section identifier for Twitch configuration
        static let settingsSection = "twitchIntegration"

        /// Timeout in seconds for receiving the session_welcome WebSocket message
        static let sessionWelcomeTimeout: TimeInterval = 10.0

        /// Grace period added to Twitch's advertised `keepalive_timeout_seconds`
        /// before the keepalive watchdog fires. Twitch sends a `session_keepalive`
        /// (or any other frame) within the advertised window when the connection
        /// is healthy; the grace absorbs scheduling and network jitter so a single
        /// late frame doesn't trip a needless reconnect.
        static let keepaliveGraceSeconds: TimeInterval = 10.0

        /// Fallback keepalive timeout (seconds) used when the `session_welcome`
        /// payload omits or malforms `keepalive_timeout_seconds`. Twitch's default
        /// is 10s; this mirrors it so the watchdog still arms safely.
        static let keepaliveDefaultTimeoutSeconds: TimeInterval = 10.0

        /// Maximum length for bot chat messages (Twitch limit)
        static let maxMessageLength = 500

        /// Truncation suffix appended when a message exceeds `maxMessageLength`
        static let messageTruncationSuffix = "..."

        /// Connection confirmation message sent when the bot joins a channel
        static let connectionMessage = "WolfWave is connected! 🎵"

        /// Maximum reconnection attempts before giving up
        static let maxReconnectionAttempts = 5

        /// Maximum network-triggered reconnect cycles to prevent infinite loops
        static let maxNetworkReconnectCycles = 5

        /// Cooldown period in seconds before resetting network reconnect cycle counter
        nonisolated static let networkReconnectCooldown: TimeInterval = 60.0

        /// Maximum retry attempts for failed message sends
        static let maxMessageRetries = 3

        /// Maximum buffered messages in the per-message retry queue. Past this
        /// cap the oldest pending message is dropped (drop-oldest backpressure).
        static let maxPendingMessages = 64

        /// Bounded buffer for the `chatMessages` AsyncStream (drop-oldest). Chat
        /// can burst, so this is sized larger than the control streams.
        static let chatMessageStreamBuffer = 256

        /// Bounded buffer for the control AsyncStreams
        /// (`connectionStateChanges`, `skipPollResults`) using drop-oldest.
        static let controlStreamBuffer = 16

        /// Delay before sending connection message after subscribing (seconds)
        static let connectionMessageDelay: TimeInterval = 1.5

        // MARK: EventSub Subscription Types

        /// EventSub type for incoming chat messages.
        static let eventSubChatMessage = "channel.chat.message"

        /// EventSub type fired when a viewer redeems a custom channel-point reward.
        static let eventSubChannelPointsRedemption = "channel.channel_points_custom_reward_redemption.add"

        /// EventSub type fired when a viewer uses bits (cheers or Power-ups).
        static let eventSubBitsUse = "channel.bits.use"

        // MARK: OAuth Scopes

        /// OAuth scopes required for core chat functionality.
        static let chatScopes = ["user:read:chat", "user:write:chat"]

        /// OAuth scope for creating and managing custom channel-point rewards.
        static let channelPointsScope = "channel:manage:redemptions"

        /// OAuth scope for reading bit-usage events.
        static let bitsScope = "bits:read"

        /// OAuth scope for managing Twitch Polls (used by chat vote-skip in Polls mode).
        static let pollsScope = "channel:manage:polls"

        /// Every scope WolfWave ever needs, requested together at sign-in.
        ///
        /// Channel-point, bit, and poll features are off by default, but asking
        /// for their scopes up front means a streamer who turns one on later
        /// never has to disconnect and re-authorize. Twitch only prompts for the
        /// extra scopes once, at the initial grant.
        static let allScopes = chatScopes + [channelPointsScope, bitsScope, pollsScope]

        /// Title of the WolfWave-managed custom channel-point reward.
        static let songRequestRewardTitle = "Request a Song"
    }
}
