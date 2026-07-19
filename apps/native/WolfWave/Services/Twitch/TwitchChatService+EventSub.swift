//
//  TwitchChatService+EventSub.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-01-08.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

extension TwitchChatService {

    // MARK: - Message Parsing

    /// Parses and handles an incoming message from EventSub.
    func handleEventSubMessage(_ json: [String: Any]) async {
        Log.debug("TwitchChatService: handleEventSubMessage enter (isProcessingDisconnect=\(isProcessingDisconnect))", category: "Twitch")
        if isProcessingDisconnect { return }

        guard let event = json["event"] as? [String: Any] else {
            Log.debug("TwitchChatService: handleEventSubMessage: payload has no event, bail", category: "Twitch")
            return
        }

        let messageID = (event["message_id"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let username = (event["chatter_user_name"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let userID = (event["chatter_user_id"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let broadcasterID = event["broadcaster_user_id"] as? String ?? ""
        let messageText = event["message"] as? [String: Any]
        let text = (messageText?["text"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !messageID.isEmpty, !username.isEmpty, !userID.isEmpty, !text.isEmpty else { return }

        var badges: [ChatMessage.Badge] = []
        if let badgeArray = event["badges"] as? [[String: Any]] {
            for badge in badgeArray {
                if let setID = badge["set_id"] as? String,
                   let id = badge["id"] as? String,
                   !setID.isEmpty, !id.isEmpty {
                    let info = (badge["info"] as? String ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    badges.append(ChatMessage.Badge(setID: setID, id: id, info: info))
                }
            }
        }

        var reply: ChatMessage.Reply?
        if let replyObj = event["reply"] as? [String: Any] {
            let parentMessageID = (replyObj["parent_message_id"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let parentBody = (replyObj["parent_message_body"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let parentUserID = (replyObj["parent_user_id"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let parentUsername = (replyObj["parent_user_name"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !parentMessageID.isEmpty && !parentUserID.isEmpty {
                reply = ChatMessage.Reply(
                    parentMessageID: parentMessageID,
                    parentMessageBody: parentBody,
                    parentUserID: parentUserID,
                    parentUsername: parentUsername
                )
            }
        }

        let chatMessage = ChatMessage(
            messageID: messageID,
            username: username,
            userID: userID,
            message: text,
            channel: broadcasterID,
            badges: badges,
            reply: reply
        )

        if commandsEnabled {
            let roles = chatMessage.roles
            let bypassCooldown = roles.isModerator || roles.isBroadcaster

            let context = BotCommandContext(
                userID: userID,
                username: username,
                isModerator: roles.isModerator,
                isBroadcaster: roles.isBroadcaster,
                isSubscriber: roles.isSubscriber,
                isVIP: roles.isVIP,
                messageID: messageID
            )

            let asyncReply: @Sendable (String) -> Void = { [weak self] response in
                guard let self else { return }
                Task { await self.sendMessage(response, replyTo: messageID) }
            }

            // BotCommandDispatcher is `@MainActor`. `processMessageAsync` auto-hops
            // and awaits the async track-info providers, so MainActor isn't blocked
            // on a semaphore while the provider tries to re-enter MainActor (which
            // was the original `runSync` deadlock).
            Log.debug("TwitchChatService: dispatch enter text=\(text.prefix(40))", category: "Twitch")
            let response: String? = await commandDispatcher.processMessageAsync(
                text,
                userID: userID,
                isModerator: bypassCooldown,
                context: context,
                asyncReply: asyncReply
            )
            Log.debug("TwitchChatService: dispatch exit response=\(response?.prefix(40) ?? "nil")", category: "Twitch")
            if let response {
                await sendMessage(response, replyTo: messageID)
            }
        }

        chatMessagesContinuation.yield(chatMessage)
    }

    // MARK: - EventSub Message Routing

    /// Handles a received WebSocket message.
    func handleWebSocketMessage(_ text: String) async {
        // Any inbound frame is proof the connection is alive: reset the keepalive
        // watchdog before doing anything else, even if the frame later fails to
        // parse. A no-op until the watchdog has been armed by `session_welcome`.
        resetKeepaliveWatchdog()

        guard let data = text.data(using: .utf8) else {
            Log.warn("TwitchChatService: WebSocket message is not valid UTF-8", category: "Twitch")
            return
        }

        let json: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                Log.warn("TwitchChatService: WebSocket message is not a JSON object", category: "Twitch")
                return
            }
            json = parsed
        } catch {
            Log.warn(
                "TwitchChatService: Failed to parse WebSocket message JSON - \(error.localizedDescription)",
                category: "Twitch")
            return
        }

        guard let metadata = json["metadata"] as? [String: Any],
              let messageType = metadata["message_type"] as? String,
              let messageID = metadata["message_id"] as? String, !messageID.isEmpty,
              let messageTimestamp = metadata["message_timestamp"] as? String, !messageTimestamp.isEmpty else {
            Log.warn("TwitchChatService: EventSub message missing required metadata fields", category: "Twitch")
            return
        }

        // Reject messages older than 10 minutes to prevent replay attacks
        var timestamp = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            .parse(messageTimestamp)
        if timestamp == nil {
            // Fallback: try without fractional seconds
            timestamp = try? Date.ISO8601FormatStyle().parse(messageTimestamp)
            if timestamp == nil {
                Log.warn(
                    "TwitchChatService: Failed to parse EventSub timestamp: \(messageTimestamp)",
                    category: "Twitch")
            }
        }
        if let timestamp {
            let age = Date().timeIntervalSince(timestamp)
            if age > 600 {
                Log.warn(
                    "TwitchChatService: Rejecting stale EventSub message (age: \(Int(age))s)",
                    category: "Twitch")
                return
            }
            // Reject messages timestamped more than 30s in the future (clock-skew
            // grace). A negative age means the message is ahead of our clock.
            if age < -30 {
                Log.warn(
                    "TwitchChatService: Rejecting future-dated EventSub message (skew: \(Int(-age))s)",
                    category: "Twitch")
                return
            }
        }

        // Twitch EventSub is at-least-once delivery: duplicate frames
        // (especially around session_reconnect) would re-run chat commands,
        // channel-point redemptions, and bits events. Drop any frame whose
        // message_id was already seen within the dedup window.
        if messageDeduplicator.isDuplicate(messageID) {
            Log.debug(
                "TwitchChatService: Dropping duplicate EventSub message (id: \(messageID))",
                category: "Twitch")
            return
        }

        switch messageType {
        case "session_welcome":
            await handleSessionWelcome(json)
        case "notification":
            await handleNotification(json)
        case "session_keepalive":
            break
        case "session_reconnect":
            await handleSessionReconnect(json)
        case "revocation":
            await handleRevocation(json)
        default:
            break
        }
    }

    /// Handles a `session_reconnect` message by migrating to the server-provided
    /// `reconnect_url`. The migrated session keeps its existing subscriptions, so
    /// the resulting `session_welcome` must NOT re-run the `subscribeTo*` calls.
    ///
    /// Safety: if the URL is missing/invalid OR anything goes wrong, fall back to
    /// the proven fresh-connect path (`disconnectFromEventSub()` +
    /// `scheduleReconnect()`), which re-subscribes. A brief event gap during the
    /// migration is acceptable; correctness beats zero-gap.
    private func handleSessionReconnect(_ json: [String: Any]) async {
        guard let url = TwitchChatService.reconnectURL(from: json) else {
            Log.warn(
                "TwitchChatService: session_reconnect missing a valid reconnect_url; reconnecting fresh",
                category: "Twitch")
            disconnectFromEventSub()
            scheduleReconnect()
            return
        }

        Log.info("TwitchChatService: Migrating EventSub session to reconnect_url", category: "Twitch")

        // Tear down only the old socket/receive loop; keep credentials and the
        // armed-deadline value. Mark migration so the next welcome skips re-subscribe.
        let oldTask = webSocketTask
        webSocketTask = nil
        sessionID = nil
        receiveTask?.cancel()
        receiveTask = nil
        keepaliveWatchdogTask?.cancel()
        keepaliveWatchdogTask = nil
        sessionWelcomeTask?.cancel()
        sessionWelcomeTask = nil

        isMigratingSession = true
        connectToEventSub(urlString: url)

        // Close the old socket only after the new connect was initiated, so the
        // new welcome can arrive without us re-entering the fresh path on close.
        oldTask?.cancel(with: .goingAway, reason: nil)
    }

    /// Handles a `revocation` message. Routes `authorization_revoked` to the
    /// shared re-auth signal and stops reconnecting; routes `user_removed` /
    /// `version_removed` to a safe full re-subscribe.
    private func handleRevocation(_ json: [String: Any]) async {
        guard let payload = json["payload"] as? [String: Any],
              let subscription = payload["subscription"] as? [String: Any] else {
            Log.warn("TwitchChatService: revocation missing subscription payload", category: "Twitch")
            return
        }
        let type = (subscription["type"] as? String) ?? ""
        let status = (subscription["status"] as? String) ?? ""

        switch TwitchChatService.revocationDisposition(type: type, status: status) {
        case .reauth:
            Log.error(
                "TwitchChatService: EventSub authorization revoked (\(type)); signaling re-auth",
                category: "Twitch")
            signalReauthNeededAndStop()
        case .resubscribe:
            Log.warn(
                "TwitchChatService: EventSub subscription revoked (\(type)/\(status)); re-subscribing",
                category: "Twitch")
            guard sessionID != nil else {
                // No live session: tear down and let the reconnect loop rebuild
                // the session and subscriptions from scratch.
                Log.warn(
                    "TwitchChatService: No active session during revocation resubscribe; reconnecting",
                    category: "Twitch")
                disconnectFromEventSub()
                scheduleReconnect()
                return
            }
            await subscribeToChannelChatMessage()
            try? await Task.sleep(for: .milliseconds(200))
            await subscribeToPollEvents()
            try? await Task.sleep(for: .milliseconds(200))
            await subscribeToStreamEvents()
            await seedStreamLiveState()
            try? await Task.sleep(for: .milliseconds(200))
            await subscribeToRedemptionsIfEnabled()
        case .ignore:
            Log.debug(
                "TwitchChatService: Ignoring revocation status \(status) for \(type)",
                category: "Twitch")
        }
    }

    /// Signals that interactive Twitch re-auth is required and stops the reconnect
    /// loop. Reuses the existing re-auth banner path (`Preferences` flag plus the
    /// `.twitchReauthNeededChanged` notification observed by `TwitchViewModel`).
    func signalReauthNeededAndStop() {
        // Stop any pending/active reconnect so we don't burn attempts on a dead token.
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectionAttempts = 0

        disconnectFromEventSub()

        // Preferences is a `nonisolated enum`, safe to call from the actor.
        Preferences.setTwitchReauthNeeded(true)
        // Post on the main actor: SwiftUI panes observe this via
        // NotificationCenter.publisher + .onReceive with no main hop, so posting
        // from the actor's background executor would mutate MainActor view state
        // off-main (executor-assert SIGTRAP class).
        Task { @MainActor in
            NotificationCenter.default.post(name: Notification.Name.twitchReauthNeededChanged, object: nil)
        }
    }

    /// Handles the session_welcome message from EventSub.
    private func handleSessionWelcome(_ json: [String: Any]) async {
        guard let payload = json["payload"] as? [String: Any],
              let session = payload["session"] as? [String: Any],
              let sessionID = session["id"] as? String else {
            Log.error("TwitchChatService: Failed to parse session ID", category: "Twitch")
            return
        }

        cancelSessionWelcomeTimeout()
        self.sessionID = sessionID
        Log.info(
            "TwitchChatService: EventSub session established with ID: \(sessionID)",
            category: "Twitch")

        // Arm the keepalive watchdog from the advertised timeout (+ grace).
        let timeout = TwitchChatService.keepaliveTimeoutSeconds(from: json)
            ?? AppConstants.Twitch.keepaliveDefaultTimeoutSeconds
        let deadline = TwitchChatService.keepaliveDeadline(
            timeoutSeconds: timeout, grace: AppConstants.Twitch.keepaliveGraceSeconds)
        armKeepaliveWatchdog(deadlineSeconds: deadline)

        broadcastConnectionState(true)

        // A `session_reconnect` migration carries its subscriptions to the new
        // session, so skip re-subscribing. Only fresh connects subscribe.
        if isMigratingSession {
            isMigratingSession = false
            Log.info(
                "TwitchChatService: Session migration complete; subscriptions carried over",
                category: "Twitch")
            return
        }

        await subscribeToChannelChatMessage()
        try? await Task.sleep(for: .milliseconds(200))
        await subscribeToPollEvents()
        try? await Task.sleep(for: .milliseconds(200))
        await subscribeToStreamEvents()
        await seedStreamLiveState()
        try? await Task.sleep(for: .milliseconds(200))
        await subscribeToRedemptionsIfEnabled()
    }

    /// Handles notification messages containing EventSub events.
    private func handleNotification(_ json: [String: Any]) async {
        guard let payload = json["payload"] as? [String: Any] else { return }
        guard let subscription = payload["subscription"] as? [String: Any],
              let subType = subscription["type"] as? String else {
            Log.warn(
                "TwitchChatService: EventSub notification missing subscription type",
                category: "Twitch")
            return
        }

        Log.debug("TwitchChatService: handleNotification subType=\(subType)", category: "Twitch")

        switch subType {
        case AppConstants.Twitch.eventSubChatMessage:
            Log.debug("TwitchChatService: routing chat message → handleEventSubMessage", category: "Twitch")
            await handleEventSubMessage(payload)
        case "channel.poll.end":
            handlePollEndEvent(payload)
        case AppConstants.Twitch.eventSubChannelPointsRedemption:
            handleChannelPointsRedemption(payload)
        case AppConstants.Twitch.eventSubBitsUse:
            handleBitsUse(payload)
        default:
            handleStreamStateNotification(type: subType)
        }
    }

    /// Parses a `channel.poll.end` event and, when it is our vote-skip poll,
    /// forwards the Skip/Keep tallies to the `skipPollResults` stream.
    private func handlePollEndEvent(_ payload: [String: Any]) {
        guard let event = payload["event"] as? [String: Any],
              let title = event["title"] as? String,
              title == TwitchChatService.skipPollTitle,
              let choices = event["choices"] as? [[String: Any]] else { return }

        var skipVotes = 0
        var keepVotes = 0
        for choice in choices {
            let votes = choice["votes"] as? Int ?? 0
            switch choice["title"] as? String {
            case TwitchChatService.skipPollSkipChoice: skipVotes = votes
            case TwitchChatService.skipPollKeepChoice: keepVotes = votes
            default: break
            }
        }

        Log.info(
            "TwitchChatService: Vote-skip poll ended: \(skipVotes) skip / \(keepVotes) keep",
            category: "Twitch")
        skipPollResultsContinuation.yield(SkipPollResult(skipVotes: skipVotes, keepVotes: keepVotes))
    }

    // MARK: - Vote-Skip Polls

    /// Creates a native Twitch poll asking chat to vote on skipping the current song.
    ///
    /// Requires the `channel:manage:polls` scope and Affiliate/Partner status.
    /// Missing either causes Twitch to reject the request, in which case this
    /// returns `false` and `SkipVoteManager` falls back to a chat tally.
    func createSkipPoll(title: String, durationSeconds: Int) async -> Bool {
        guard let broadcasterID,
              let token = oauthToken,
              let clientID else {
            Log.warn("TwitchChatService: Cannot create poll: missing credentials", category: "Twitch")
            return false
        }

        guard let url = URL(string: apiBaseURL + "/polls") else { return false }

        let duration = min(max(durationSeconds, 15), 1800)
        let body: [String: Any] = [
            "broadcaster_id": broadcasterID,
            "title": String(title.prefix(60)),
            "choices": [
                ["title": TwitchChatService.skipPollSkipChoice],
                ["title": TwitchChatService.skipPollKeepChoice],
            ],
            "duration": duration,
        ]

        let request: URLRequest
        do {
            request = try HelixClient.buildRequest(
                url: url, method: "POST",
                credentials: .init(token: token, clientID: clientID), body: body)
        } catch {
            Log.error(
                "TwitchChatService: Failed to serialize poll body - \(error.localizedDescription)",
                category: "Twitch")
            return false
        }

        do {
            let (data, http) = try await HTTPClient.shared.send(request)
            if (200..<300).contains(http.statusCode) {
                Log.info("TwitchChatService: Vote-skip poll created", category: "Twitch")
                return true
            }
            let text = String(data: data, encoding: .utf8) ?? "No response"
            Log.warn(
                "TwitchChatService: Poll creation failed: HTTP \(http.statusCode): \(text)",
                category: "Twitch")
            return false
        } catch {
            Log.error(
                "TwitchChatService: Poll creation request failed - \(error.localizedDescription)",
                category: "Twitch")
            return false
        }
    }

    /// Subscribes to `channel.poll.end` so finished vote-skip polls can be tallied.
    private func subscribeToPollEvents() async {
        guard FeatureFlags.voteSkipEnabled,
              UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.voteSkipUsePolls) else { return }

        guard let sessionID,
              let broadcasterID,
              let token = oauthToken,
              let clientID else {
            Log.warn(
                "TwitchChatService: Missing credentials for poll EventSub subscription",
                category: "Twitch")
            return
        }

        let body = Self.eventSubBody(
            type: "channel.poll.end", broadcasterID: broadcasterID, sessionID: sessionID)
        await postEventSubSubscription(body: body, token: token, clientID: clientID, label: "channel.poll.end")
    }

    /// Updates `streamLive` from a `stream.online` / `stream.offline` event.
    private func handleStreamStateNotification(type: String) {
        switch type {
        case "stream.online":
            // Anchor the "This stream" stats window before flipping `streamLive`
            // so a synchronous snapshot reader can never observe live=true with
            // a nil anchor. The event payload carries no start time here, so
            // the moment we're notified is close enough.
            streamLiveSince = Date()
            streamLive = true
            Log.info("TwitchChatService: Stream went live", category: "Twitch")
        case "stream.offline":
            streamLive = false
            streamLiveSince = nil
            Log.info("TwitchChatService: Stream went offline", category: "Twitch")
        default:
            Log.debug("TwitchChatService: Ignoring unexpected EventSub type: \(type)", category: "Twitch")
        }
    }

    // MARK: - EventSub Subscriptions

    /// Builds a version-1 EventSub subscription body over the WebSocket
    /// transport. The `condition` always carries `broadcaster_user_id`; pass
    /// `extraCondition` for events (e.g. `channel.chat.message`) that need more
    /// condition keys. Serialized via `JSONSerialization`, so key order is
    /// irrelevant. Centralizes the version/transport scaffolding every
    /// subscription otherwise hand-builds.
    nonisolated static func eventSubBody(
        type: String,
        broadcasterID: String,
        sessionID: String,
        extraCondition: [String: String] = [:]
    ) -> [String: Any] {
        var condition: [String: String] = ["broadcaster_user_id": broadcasterID]
        condition.merge(extraCondition) { _, new in new }
        return [
            "type": type,
            "version": "1",
            "condition": condition,
            "transport": ["method": "websocket", "session_id": sessionID],
        ]
    }

    /// Subscribes to the channel.chat.message EventSub event.
    private func subscribeToChannelChatMessage() async {
        guard let sessionID,
              let broadcasterID,
              let botID,
              let token = oauthToken,
              let clientID else {
            Log.error(
                "TwitchChatService: Missing credentials for EventSub subscription",
                category: "Twitch")
            broadcastConnectionState(false)
            return
        }

        let body = Self.eventSubBody(
            type: "channel.chat.message",
            broadcasterID: broadcasterID,
            sessionID: sessionID,
            extraCondition: ["user_id": botID])

        // Shares the EventSub POST scaffolding with every other subscription.
        // The chat subscription is the critical one: its extra success
        // side-effect is the connection confirmation message, and a failure
        // tears the connection back down.
        var sawAuthFailure = false
        let subscribed = await postEventSubSubscription(
            body: body,
            token: token,
            clientID: clientID,
            label: "channel.chat.message",
            onSuccess: {
                Log.info("TwitchChatService: Connected to chat", category: "Twitch")
                if shouldSendConnectionMessageOnSubscribe {
                    sendConnectionMessage()
                }
            },
            onFailureStatus: { status in
                // A 401 on the critical chat subscription means the token is dead.
                // The subscription runs async after `session_welcome`, so it can't
                // throw back into `attemptReconnect`; surface it as a re-auth signal.
                if status == 401 { sawAuthFailure = true }
            }
        )

        if !subscribed {
            broadcastConnectionState(false)
            if sawAuthFailure {
                Log.error(
                    "TwitchChatService: Chat subscription returned 401; signaling re-auth",
                    category: "Twitch")
                signalReauthNeededAndStop()
            }
        }
    }

    /// Subscribes to `stream.online` / `stream.offline` so `streamLive` stays current.
    private func subscribeToStreamEvents() async {
        guard let sessionID,
              let broadcasterID,
              let token = oauthToken,
              let clientID else { return }

        for eventType in ["stream.online", "stream.offline"] {
            let body = Self.eventSubBody(
                type: eventType, broadcasterID: broadcasterID, sessionID: sessionID)
            await postEventSubSubscription(body: body, token: token, clientID: clientID, label: eventType)
        }
    }

    /// Seeds `streamLive` with a single Helix "Get Streams" call.
    private func seedStreamLiveState() async {
        guard let broadcasterID,
              let token = oauthToken,
              let clientID,
              var components = URLComponents(string: apiBaseURL + "/streams") else { return }
        components.queryItems = [URLQueryItem(name: "user_id", value: broadcasterID)]
        guard let url = components.url else { return }

        do {
            let response: HelixStreamsResponse = try await HTTPClient.shared.get(
                url: url,
                headers: HelixClient.headers(for: .init(token: token, clientID: clientID)))
            let live = !response.data.isEmpty
            // Anchor "This stream" to the real start time when available, else now.
            // The anchor is set before `streamLive` flips true (and cleared after
            // it flips false) so snapshot readers never see live=true with no anchor.
            if live {
                let startedAt = response.data.first?.startedAt
                    .flatMap { SharedFormatters.iso8601.date(from: $0) }
                streamLiveSince = startedAt ?? Date()
                streamLive = true
            } else {
                streamLive = false
                streamLiveSince = nil
            }
            Log.info("TwitchChatService: Seeded stream-live state: live=\(live)", category: "Twitch")
        } catch {
            Log.debug(
                "TwitchChatService: Stream-live seed request failed - \(error.localizedDescription)",
                category: "Twitch")
        }
    }

    /// Posts an EventSub subscription request. Logs success/failure and updates
    /// redemption status on 403 (scope) / non-2xx (subscribeFailed).
    ///
    /// - Parameters:
    ///   - onSuccess: Side effect run once on a 2xx response. Defaults to a
    ///     no-op; `subscribeToChannelChatMessage` uses it to send the connection
    ///     confirmation message.
    /// - Returns: `true` when the subscription is in place (2xx, or 409 "already
    ///   active"), `false` on any other failure. `subscribeToChannelChatMessage`
    ///   branches on this to decide whether the connection is healthy.
    @discardableResult
    func postEventSubSubscription(
        body: [String: Any],
        token: String,
        clientID: String,
        label: String,
        onSuccess: () -> Void = {},
        onFailureStatus: (Int) -> Void = { _ in }
    ) async -> Bool {
        guard let url = URL(string: apiBaseURL + "/eventsub/subscriptions") else { return false }

        let request: URLRequest
        do {
            request = try HelixClient.buildRequest(
                url: url, method: "POST",
                credentials: .init(token: token, clientID: clientID), body: body)
        } catch {
            Log.error(
                "TwitchChatService: Failed to serialize \(label) subscription - \(error.localizedDescription)",
                category: "Twitch")
            return false
        }

        do {
            let (data, http) = try await HTTPClient.shared.send(request)
            if (200..<300).contains(http.statusCode) {
                Log.info("TwitchChatService: Subscribed to \(label)", category: "Twitch")
                onSuccess()
                return true
            } else if http.statusCode == 409 {
                Log.info("TwitchChatService: \(label) subscription already active", category: "Twitch")
                return true
            } else {
                let responseText = String(data: data, encoding: .utf8) ?? "No response"
                Log.error(
                    "TwitchChatService: \(label) subscription failed - HTTP \(http.statusCode) - \(responseText)",
                    category: "Twitch")
                if label == "channel-point redemptions" || label == "bit usage" {
                    setRedemptionStatus(http.statusCode == 403 ? .scopeMissing : .subscribeFailed)
                }
                onFailureStatus(http.statusCode)
                return false
            }
        } catch {
            Log.error(
                "TwitchChatService: \(label) subscription error - \(error.localizedDescription)",
                category: "Twitch")
            return false
        }
    }
}
