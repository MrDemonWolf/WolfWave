//
//  TwitchChatService+Redemptions.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-07-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

extension TwitchChatService {

    // MARK: - Redemption EventSub Subscriptions

    /// Subscribes to channel-point and/or bit EventSub events when the matching
    /// song-request features are enabled. Channel-point and bit subscriptions
    /// require the signed-in account to be the broadcaster. When a separate bot
    /// account is in use they are skipped and the UI is notified.
    func subscribeToRedemptionsIfEnabled() async {
        let defaults = UserDefaults.standard

        // Channel-point and bit toggles are independent of the master switch, so
        // skip every redemption subscription while the feature as a whole is off.
        // Pause the managed reward first so it can't be redeemed at the source.
        guard defaults.bool(forKey: AppConstants.UserDefaults.songRequestEnabled) else {
            await pauseManagedRewardIfPossible()
            setRedemptionStatus(.ok)
            return
        }

        let channelPointsEnabled = defaults.bool(
            forKey: AppConstants.UserDefaults.songRequestChannelPointsEnabled)
        let bitsEnabled = defaults.bool(forKey: AppConstants.UserDefaults.songRequestBitsEnabled)

        // Channel points off but a reward may still exist on the channel: pause it
        // so viewers can't spend points on a request WolfWave would only refund.
        if !channelPointsEnabled {
            await pauseManagedRewardIfPossible()
        }

        guard channelPointsEnabled || bitsEnabled else {
            setRedemptionStatus(.ok)
            return
        }

        // Channel-point and bit EventSub require the broadcaster's own token.
        guard let broadcasterID, let botID, broadcasterID == botID else {
            Log.warn(
                "TwitchChatService: Redemption events need the broadcaster account, skipping",
                category: "Twitch")
            setRedemptionStatus(.botAccount)
            return
        }

        setRedemptionStatus(.ok)

        if channelPointsEnabled {
            await ensureSongRequestRewardAndSubscribe()
        }
        if bitsEnabled {
            await subscribeToBitsUse()
        }
    }

    /// Re-evaluates redemption subscriptions against the current settings.
    /// Called by the settings UI after the streamer changes a redemption toggle.
    func refreshRedemptionSubscriptions() async {
        guard isConnected else { return }
        await subscribeToRedemptionsIfEnabled()
    }

    /// Ensures the WolfWave channel-point reward exists, syncs its cost, and
    /// subscribes to its redemption events.
    private func ensureSongRequestRewardAndSubscribe() async {
        guard let credentials = currentChannelPointCredentials() else { return }
        let cost = channelPointsCostSetting()
        do {
            let rewardID = try await channelPointsService.ensureReward(
                credentials: credentials, cost: cost)
            // Make sure a previously-paused reward is live again now that the
            // feature is on. A failure here leaves the reward greyed out on
            // Twitch even though everything else worked, so don't swallow it:
            // log it and surface a non-ok status in the settings banner.
            var unpauseFailed = false
            do {
                try await channelPointsService.setRewardPaused(
                    credentials: credentials, rewardID: rewardID, paused: false)
            } catch {
                unpauseFailed = true
                Log.error(
                    "TwitchChatService: Failed to un-pause channel-point reward - \(error.localizedDescription)",
                    category: "Twitch")
            }
            // Cost sync is non-fatal (the reward still works at its old cost),
            // but don't swallow the failure silently; surface it in the log.
            do {
                try await channelPointsService.updateRewardCost(
                    credentials: credentials, rewardID: rewardID, cost: cost)
            } catch {
                Log.warn(
                    "TwitchChatService: Couldn't sync channel-point reward cost; the reward still works at its current cost - \(error.localizedDescription)",
                    category: "Twitch")
            }
            await subscribeToChannelPointsRedemption()
            setRedemptionStatus(unpauseFailed ? .subscribeFailed : .ok)
        } catch {
            Log.error(
                "TwitchChatService: Failed to set up channel-point reward - \(error.localizedDescription)",
                category: "Twitch")
            setRedemptionStatus(.subscribeFailed)
        }
    }

    /// Pauses the WolfWave-managed channel-point reward so it can't be redeemed
    /// while channel-point requests are off. No-op when no reward was ever
    /// created or broadcaster credentials are unavailable.
    private func pauseManagedRewardIfPossible() async {
        let storedID = UserDefaults.standard.string(
            forKey: AppConstants.UserDefaults.songRequestChannelPointsRewardID) ?? ""
        guard !storedID.isEmpty, let credentials = currentChannelPointCredentials() else { return }
        do {
            try await channelPointsService.setRewardPaused(
                credentials: credentials, rewardID: storedID, paused: true)
            Log.info("TwitchChatService: Paused channel-point reward (requests off)", category: "Twitch")
        } catch {
            Log.error(
                "TwitchChatService: Failed to pause channel-point reward - \(error.localizedDescription)",
                category: "Twitch")
        }
    }

    private func subscribeToChannelPointsRedemption() async {
        guard let broadcasterID, let token = oauthToken, let clientID, let sessionID else { return }
        let body = Self.eventSubBody(
            type: AppConstants.Twitch.eventSubChannelPointsRedemption,
            broadcasterID: broadcasterID, sessionID: sessionID)
        await postEventSubSubscription(body: body, token: token, clientID: clientID, label: "channel-point redemptions")
    }

    private func subscribeToBitsUse() async {
        guard let broadcasterID, let token = oauthToken, let clientID, let sessionID else { return }
        let body = Self.eventSubBody(
            type: AppConstants.Twitch.eventSubBitsUse,
            broadcasterID: broadcasterID, sessionID: sessionID)
        await postEventSubSubscription(body: body, token: token, clientID: clientID, label: "bit usage")
    }

    // MARK: - Redemption Event Handlers

    /// Handles a channel-point reward redemption. Ignores redemptions for any
    /// reward other than the WolfWave-managed one, routes the viewer's input
    /// into the song-request pipeline, then fulfils the redemption on success
    /// or cancels it (refunding the points) on failure.
    func handleChannelPointsRedemption(_ payload: [String: Any]) {
        // Note: the enabled check happens inside the Task below (after we confirm
        // this is our reward), so a redemption that arrives while the feature is
        // off is refunded rather than silently swallowed.
        guard let event = payload["event"] as? [String: Any] else { return }

        let rewardID = ((event["reward"] as? [String: Any])?["id"] as? String) ?? ""
        let storedRewardID = UserDefaults.standard.string(
            forKey: AppConstants.UserDefaults.songRequestChannelPointsRewardID) ?? ""
        guard !rewardID.isEmpty, rewardID == storedRewardID else { return }

        let redemptionID = (event["id"] as? String) ?? ""
        let userName = ((event["user_name"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let userInput = ((event["user_input"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !redemptionID.isEmpty, !userName.isEmpty else { return }

        let credentials = currentChannelPointCredentials()
        let songRequestService = self.songRequestService

        let taskID = UUID()
        redemptionTasks[taskID] = Task { [weak self] in
            await self?.runChannelPointsRedemption(
                credentials: credentials,
                rewardID: rewardID,
                redemptionID: redemptionID,
                userName: userName,
                userInput: userInput,
                service: songRequestService)
            await self?.clearRedemptionTask(taskID)
        }
    }

    /// Runs the channel-point redemption pipeline. Cancellation (disconnect or
    /// teardown) suppresses chat replies only; the redemption itself is always
    /// resolved (fulfil/refund is Helix HTTP, independent of the chat socket),
    /// so viewer points never strand in the pending state.
    private func runChannelPointsRedemption(
        credentials: TwitchChannelPointsService.Credentials?,
        rewardID: String,
        redemptionID: String,
        userName: String,
        userInput: String,
        service: SongRequestService?
    ) async {
        guard let service, !Task.isCancelled else {
            // Service not wired up, or cancelled before starting: the points
            // were already spent, so refund rather than strand the redemption
            // in the pending state forever.
            await resolveRedemption(
                credentials, rewardID: rewardID, redemptionID: redemptionID, as: .canceled)
            return
        }

        // Channel-point requests off (toggle flipped between subscribe and
        // redemption, or the reward wasn't paused in time): refund.
        guard UserDefaults.standard.bool(
            forKey: AppConstants.UserDefaults.songRequestChannelPointsEnabled) else {
            if !Task.isCancelled {
                await sendMessage(
                    "@\(userName) channel-point song requests are off right now. Refunding your points.")
            }
            await resolveRedemption(
                credentials, rewardID: rewardID, redemptionID: redemptionID, as: .canceled)
            return
        }

        if userInput.isEmpty {
            if !Task.isCancelled {
                await sendMessage(
                    "@\(userName) add a song name when you redeem. Refunding your points.")
            }
            await resolveRedemption(
                credentials, rewardID: rewardID, redemptionID: redemptionID, as: .canceled)
            return
        }

        let result = await service.processRequest(
            query: userInput,
            username: userName,
            source: .channelPoints(redemptionID: redemptionID, rewardID: rewardID))
        let (message, resolution) = redemptionOutcome(for: result, username: userName)
        if !Task.isCancelled {
            await sendMessage(message)
        }
        await resolveRedemption(
            credentials, rewardID: rewardID, redemptionID: redemptionID, as: resolution)
    }

    /// Drops a finished redemption pipeline task from the tracking table.
    private func clearRedemptionTask(_ id: UUID) {
        redemptionTasks[id] = nil
    }

    /// Handles a `channel.bits.use` event.
    func handleBitsUse(_ payload: [String: Any]) {
        let defaults = UserDefaults.standard
        guard
            defaults.bool(forKey: AppConstants.UserDefaults.songRequestBitsEnabled),
            let event = payload["event"] as? [String: Any]
        else { return }

        let bits = (event["bits"] as? Int) ?? 0
        guard bits > 0, bits >= bitsMinimumSetting() else { return }

        let userName = ((event["user_name"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userName.isEmpty else { return }

        let boostEnabled = defaults.bool(
            forKey: AppConstants.UserDefaults.songRequestBitsBoostEnabled)
        let query = Self.cleanBitsMessage(event["message"] as? [String: Any])
        let songRequestService = self.songRequestService

        let taskID = UUID()
        redemptionTasks[taskID] = Task { [weak self] in
            await self?.runBitsUse(
                userName: userName,
                bits: bits,
                boostEnabled: boostEnabled,
                query: query,
                service: songRequestService)
            await self?.clearRedemptionTask(taskID)
        }
    }

    /// Runs the bits-cheer pipeline. Unlike channel points there is nothing to
    /// refund, so cancellation (disconnect or teardown) simply stops the
    /// pipeline and suppresses chat replies.
    private func runBitsUse(
        userName: String,
        bits: Int,
        boostEnabled: Bool,
        query: String,
        service: SongRequestService?
    ) async {
        guard let service, !Task.isCancelled else { return }

        if boostEnabled, let boosted = await service.boost(username: userName) {
            if !Task.isCancelled {
                await sendMessage(
                    "@\(userName) boosted \"\(boosted.title)\" to the front of the queue! (\(bits) bits)")
            }
            return
        }

        guard !query.isEmpty else {
            if boostEnabled, !Task.isCancelled {
                await sendMessage(
                    "@\(userName) no song of yours to boost. Include a song name in your cheer to request one.")
            }
            return
        }

        guard !Task.isCancelled else { return }
        let result = await service.processRequest(
            query: query, username: userName, source: .bits(amount: bits))
        if !Task.isCancelled {
            await sendMessage(bitsOutcomeMessage(for: result, username: userName))
        }
    }

    // MARK: - Redemption Helpers

    /// Resolves a channel-point redemption via Helix, logging any failure.
    private func resolveRedemption(
        _ credentials: TwitchChannelPointsService.Credentials?,
        rewardID: String,
        redemptionID: String,
        as resolution: TwitchChannelPointsService.Resolution
    ) async {
        // Prefer fresh credentials at resolve time: a momentary nil when the
        // event arrived must not doom the later resolution (the never-strand
        // invariant). Fall back to the credentials captured at event time.
        guard let credentials = currentChannelPointCredentials() ?? credentials else {
            Log.error(
                "TwitchChatService: Cannot \(resolution.rawValue) redemption \(redemptionID) (reward \(rewardID)) - no credentials; redemption stays pending on Twitch",
                category: "Twitch")
            return
        }
        do {
            try await channelPointsService.resolveRedemption(
                credentials: credentials,
                rewardID: rewardID,
                redemptionID: redemptionID,
                as: resolution)
        } catch {
            Log.error(
                "TwitchChatService: Failed to \(resolution.rawValue) redemption - \(error.localizedDescription)",
                category: "Twitch")
        }
    }

    /// Maps a request result to a chat message and a redemption resolution.
    private func redemptionOutcome(
        for result: SongRequestService.RequestResult,
        username: String
    ) -> (message: String, resolution: TwitchChannelPointsService.Resolution) {
        switch result {
        case let .added(item, position):
            return (
                "@\(username) added \"\(item.title)\" by \(item.artist), #\(position) in queue",
                .fulfilled)
        case let .pendingApproval(item):
            // ponytail: fulfill on submit-to-review. A later reject can't refund
            // points once the redemption is resolved, so approval-mode redemptions
            // consume points on request, not on approval.
            return (
                "@\(username) sent \"\(item.title)\" by \(item.artist) to the streamer for approval.",
                .fulfilled)
        case let .queueFull(max):
            return ("@\(username) the queue is full (\(max)). Points refunded.", .canceled)
        case let .userLimitReached(max):
            return ("@\(username) you already have \(max) songs queued. Points refunded.", .canceled)
        case .alreadyInQueue:
            return ("@\(username) that song is already queued. Points refunded.", .canceled)
        case .blocked:
            return ("@\(username) that song is on the blocklist. Points refunded.", .canceled)
        case let .notFound(query):
            let truncated = StringFormatting.truncatedWithEllipsis(query)
            return ("@\(username) no results for \"\(truncated)\". Points refunded.", .canceled)
        case .linkNotFound:
            return ("@\(username) couldn't find that on Apple Music. Points refunded.", .canceled)
        case .notAuthorized:
            return ("@\(username) song requests aren't available right now. Points refunded.", .canceled)
        case .featureDisabled:
            return ("@\(username) song requests are off right now. Points refunded.", .canceled)
        case let .error(message):
            return ("@\(username) \(message) Points refunded.", .canceled)
        }
    }

    /// Builds a chat reply for a bit-cheer song request.
    private func bitsOutcomeMessage(
        for result: SongRequestService.RequestResult,
        username: String
    ) -> String {
        switch result {
        case let .added(item, position):
            return "@\(username) added \"\(item.title)\" by \(item.artist), #\(position) in queue. Thanks for the bits!"
        case let .pendingApproval(item):
            return "@\(username) sent \"\(item.title)\" by \(item.artist) to the streamer for approval. Thanks for the bits!"
        case let .queueFull(max):
            return "@\(username) the queue is full (\(max)/\(max)). Try again soon!"
        case let .userLimitReached(max):
            return "@\(username) you already have \(max) songs queued."
        case .alreadyInQueue:
            return "@\(username) that song is already in the queue."
        case .blocked:
            return "@\(username) sorry, that song/artist is on the blocklist."
        case let .notFound(query):
            let truncated = StringFormatting.truncatedWithEllipsis(query)
            return "@\(username) no results for \"\(truncated)\"."
        case .linkNotFound:
            return "@\(username) couldn't find that on Apple Music."
        case .notAuthorized:
            return "@\(username) song requests aren't available right now."
        case .featureDisabled:
            return "@\(username) song requests are off right now."
        case let .error(message):
            return "@\(username) \(message)"
        }
    }

    /// Current broadcaster credentials for Helix channel-point calls, or `nil`
    /// when any credential is missing.
    private func currentChannelPointCredentials() -> TwitchChannelPointsService.Credentials? {
        guard let broadcasterID, let token = oauthToken, let clientID,
              !broadcasterID.isEmpty, !token.isEmpty, !clientID.isEmpty else { return nil }
        return TwitchChannelPointsService.Credentials(
            broadcasterID: broadcasterID, token: token, clientID: clientID)
    }

    /// Configured channel-point cost for the managed reward (default 500).
    nonisolated private func channelPointsCostSetting() -> Int {
        Preferences.int(AppConstants.UserDefaults.songRequestChannelPointsCost, default: AppConstants.UserDefaults.Defaults.songRequestChannelPointsCost)
    }

    /// Configured minimum bits required to trigger a request (default 100).
    nonisolated private func bitsMinimumSetting() -> Int {
        Preferences.int(AppConstants.UserDefaults.songRequestBitsMinimum, default: AppConstants.UserDefaults.Defaults.songRequestBitsMinimum)
    }

    /// Persists the redemption integration health for the settings UI.
    nonisolated func setRedemptionStatus(_ status: RedemptionStatus) {
        UserDefaults.standard.set(
            status.rawValue, forKey: AppConstants.UserDefaults.songRequestRedemptionStatus)
    }

    /// Extracts the viewer's song query from a `channel.bits.use` message,
    /// dropping cheermote tokens.
    nonisolated static func cleanBitsMessage(_ message: [String: Any]?) -> String {
        guard let message else { return "" }

        if let fragments = message["fragments"] as? [[String: Any]] {
            let textParts = fragments.compactMap { fragment -> String? in
                guard (fragment["type"] as? String) == "text" else { return nil }
                return fragment["text"] as? String
            }
            let joined = textParts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { return joined }
        }

        let raw = (message["text"] as? String) ?? ""
        return stripLeadingCheermotes(raw)
    }

    /// Cached compiled pattern for the leading-cheermote strip. Compiling it per call on the
    /// hot chat path was wasteful. NSRegularExpression is thread-safe for matching.
    private nonisolated static let cheermotePrefixRegex = try? NSRegularExpression(
        pattern: "^(?:[Cc]heer[0-9]+\\s*)+")

    /// Removes leading `Cheer<amount>` tokens from a raw cheer message.
    nonisolated static func stripLeadingCheermotes(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let regex = cheermotePrefixRegex,
            let match = regex.firstMatch(
                in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
            let range = Range(match.range, in: trimmed)
        else {
            return trimmed
        }
        var stripped = trimmed
        stripped.removeSubrange(range)
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
