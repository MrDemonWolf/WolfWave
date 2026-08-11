//
//  TwitchChatService+EventSub.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-07-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

extension TwitchChatService {

    #if DEBUG
    /// Debug-only role override for exercising viewer permissions and cooldowns
    /// with real chat messages. Never compiled into release builds.
    static func shouldTreatAsViewer(
        event: [String: Any],
        defaults: UserDefaults = .standard
    ) -> Bool {
        if defaults.bool(forKey: AppConstants.UserDefaults.debugTreatAllChattersAsViewers) {
            return true
        }
        let login = (event["chatter_user_login"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = (event["chatter_user_name"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let username = login.isEmpty ? displayName : login
        let names = defaults.string(forKey: AppConstants.UserDefaults.debugViewerUsernames) ?? ""
        return names
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .contains(username.lowercased())
    }
    #endif

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

        if Self.isPotentialCommand(text) {
            let isDuplicateCommand = commandMessageDeduplicator.isDuplicate(messageID)
            if isDuplicateCommand {
                Log.debug(
                    "TwitchChatService: Dropping duplicate command message (id: \(messageID))",
                    category: "Twitch")
            } else if commandsEnabled {
                let roles = chatMessage.roles
                #if DEBUG
                let treatAsViewer = Self.shouldTreatAsViewer(event: event)
                #else
                let treatAsViewer = false
                #endif
                let bypassCooldown = !treatAsViewer && (roles.isModerator || roles.isBroadcaster)

                let context = BotCommandContext(
                    userID: userID,
                    username: username,
                    isModerator: !treatAsViewer && roles.isModerator,
                    isBroadcaster: !treatAsViewer && roles.isBroadcaster,
                    isSubscriber: !treatAsViewer && roles.isSubscriber,
                    isVIP: !treatAsViewer && roles.isVIP,
                    messageID: messageID
                )

                startCommandDispatch(
                    text: text,
                    userID: userID,
                    isModerator: bypassCooldown,
                    context: context,
                    replyTo: messageID,
                    generation: connectionGeneration,
                    broadcasterID: broadcasterID)
            }
        }

        chatMessagesContinuation.yield(chatMessage)
    }

    /// Starts a command pipeline without stalling the serial WebSocket receive
    /// loop. The task is tracked until completion and canceled whenever its
    /// connection generation is superseded.
    private func startCommandDispatch(
        text: String,
        userID: String,
        isModerator: Bool,
        context: BotCommandContext,
        replyTo messageID: String,
        generation: UInt64,
        broadcasterID: String
    ) {
        let taskID = UUID()
        commandTasks[taskID] = Task { [weak self] in
            await self?.runCommandDispatch(
                text: text,
                userID: userID,
                isModerator: isModerator,
                context: context,
                replyTo: messageID,
                generation: generation,
                broadcasterID: broadcasterID)
            await self?.clearCommandTask(taskID)
        }
    }

    private func runCommandDispatch(
        text: String,
        userID: String,
        isModerator: Bool,
        context: BotCommandContext,
        replyTo messageID: String,
        generation: UInt64,
        broadcasterID: String
    ) async {
        guard !Task.isCancelled,
              commandReplyIsCurrent(generation: generation, broadcasterID: broadcasterID) else {
            return
        }

        // BotCommandDispatcher is MainActor-isolated. The tracked task awaits
        // its async result while the EventSub receive task remains free to read
        // keepalives and later notifications.
        Log.debug("TwitchChatService: dispatch enter text=\(text.prefix(40))", category: "Twitch")
        let response = await commandDispatcher.processMessageAsync(
            text,
            userID: userID,
            isModerator: isModerator,
            context: context)
        Log.debug("TwitchChatService: dispatch exit response=\(response?.prefix(40) ?? "nil")", category: "Twitch")

        guard let response, !Task.isCancelled else { return }
        await sendCommandReply(
            response,
            replyTo: messageID,
            generation: generation,
            broadcasterID: broadcasterID)
    }

    private func clearCommandTask(_ id: UUID) {
        commandTasks[id] = nil
    }

    // MARK: - EventSub Message Routing

    /// Handles a received WebSocket message.
    func handleWebSocketMessage(_ text: String) async {
        await handleWebSocketMessage(text, receiveContext: nil)
    }

    /// Production receive entry point carrying ownership of the socket that
    /// produced the frame. The nil-context wrapper above remains a parsing seam
    /// for focused unit tests.
    func handleWebSocketMessage(
        _ text: String,
        receiveContext: EventSubReceiveContext?
    ) async {
        guard receiveContextIsCurrent(receiveContext) else { return }
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
        var timestamp = try? Date.ISO8601FormatStyle(
            includingFractionalSeconds: true
        ).parse(messageTimestamp)
        if timestamp == nil {
            // Fallback: try without fractional seconds.
            timestamp = try? Date.ISO8601FormatStyle().parse(messageTimestamp)
        }
        guard let timestamp else {
            // Twitch guarantees RFC3339. Accepting an unparseable timestamp
            // would make the bounded replay and paid-event dedup horizon false.
            Log.warn(
                "TwitchChatService: Rejecting EventSub message with invalid timestamp: \(messageTimestamp)",
                category: "Twitch")
            return
        }
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
            await handleSessionWelcome(json, receiveContext: receiveContext)
        case "notification":
            await handleNotification(
                json,
                messageID: messageID,
                receiveContext: receiveContext)
        case "session_keepalive":
            break
        case "session_reconnect":
            await handleSessionReconnect(json, receiveContext: receiveContext)
        case "revocation":
            await handleRevocation(json, receiveContext: receiveContext)
        default:
            break
        }
    }

    /// Handles a `session_reconnect` message by migrating to the server-provided
    /// `reconnect_url`. The migrated session keeps its existing subscriptions, so
    /// the resulting `session_welcome` must NOT re-run the `subscribeTo*` calls.
    ///
    /// Twitch requires the source socket to remain open until the replacement
    /// sends `session_welcome`. Both receive loops therefore run during the
    /// handoff; message-ID deduplication makes overlapping deliveries safe.
    private func handleSessionReconnect(
        _ json: [String: Any],
        receiveContext: EventSubReceiveContext?
    ) async {
        guard !eventSubTeardownQuiescing.value,
              receiveContextIsCurrent(receiveContext) else { return }
        guard !isMigratingSession else {
            Log.debug(
                "TwitchChatService: Ignoring duplicate session_reconnect during migration",
                category: "Twitch")
            return
        }
        guard let url = TwitchChatService.reconnectURL(from: json) else {
            Log.warn(
                "TwitchChatService: session_reconnect missing a valid reconnect_url; reconnecting fresh",
                category: "Twitch")
            disconnectFromEventSub()
            scheduleReconnect()
            return
        }

        Log.info("TwitchChatService: Migrating EventSub session to reconnect_url", category: "Twitch")

        // Move ownership of the source socket/loop aside without cancelling it.
        // Session-bound command and paid redemption work remains valid because
        // this is a transport handoff for the same logical channel session.
        migrationSourceWebSocketTask = webSocketTask
        migrationSourceReceiveTask = receiveTask
        webSocketTask = nil
        receiveTask = nil
        sessionWelcomeTask?.cancel()
        sessionWelcomeTask = nil

        isMigratingSession = true
        connectToEventSub(urlString: url)
    }

    /// Handles every documented EventSub revocation status. Terminal account,
    /// client-version, and permission failures stop without retry; transient
    /// maintenance/WebSocket statuses use the existing bounded reconnect loop.
    private func handleRevocation(
        _ json: [String: Any],
        receiveContext: EventSubReceiveContext?
    ) async {
        guard !eventSubTeardownQuiescing.value,
              receiveContextIsCurrent(receiveContext) else { return }
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
        case .accountUnavailable:
            stopEventSubWithoutReconnect(
                error: "The connected Twitch account is no longer available.")
            Log.error(
                "TwitchChatService: EventSub account removed (\(type)); connection stopped",
                category: "Twitch")
        case .clientUpdateRequired:
            stopEventSubWithoutReconnect(
                error: "Twitch retired an EventSub version used by WolfWave. Please update WolfWave.")
            Log.error(
                "TwitchChatService: EventSub version removed (\(type)); client update required",
                category: "Twitch")
        case .permissionLost:
            stopEventSubWithoutReconnect(
                error: "WolfWave no longer has permission to receive Twitch chat events.")
            Log.error(
                "TwitchChatService: EventSub permission/channel access lost (\(type)/\(status))",
                category: "Twitch")
        case .reconnect:
            Log.warn(
                "TwitchChatService: Transient EventSub revocation (\(type)/\(status)); reconnecting",
                category: "Twitch")
            disconnectFromEventSub(error: "Twitch temporarily interrupted EventSub delivery.")
            if isNetworkReachable {
                scheduleReconnect()
            }
        case .ignore:
            Log.debug(
                "TwitchChatService: Ignoring revocation status \(status) for \(type)",
                category: "Twitch")
        }
    }

    private func stopEventSubWithoutReconnect(error: String) {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectionAttempts = 0
        disconnectFromEventSub(error: error)
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
    private func handleSessionWelcome(
        _ json: [String: Any],
        receiveContext: EventSubReceiveContext?
    ) async {
        guard !eventSubTeardownQuiescing.value,
              receiveContextIsCurrent(receiveContext) else { return }
        if isMigratingSession,
           let receiveContext,
           migrationSourceWebSocketTask === receiveContext.webSocketTask {
            Log.debug(
                "TwitchChatService: Ignoring unexpected duplicate welcome from migration source",
                category: "Twitch")
            return
        }
        guard let payload = json["payload"] as? [String: Any],
              let session = payload["session"] as? [String: Any],
              let sessionID = session["id"] as? String else {
            Log.error("TwitchChatService: Failed to parse session ID", category: "Twitch")
            return
        }

        cancelSessionWelcomeTimeout()
        reconnectTask?.cancel()
        reconnectTask = nil
        welcomedWebSocketTask = receiveContext?.webSocketTask ?? webSocketTask
        self.sessionID = sessionID
        Log.info(
            "TwitchChatService: EventSub session established with ID: \(sessionID)",
            category: "Twitch")

        // Arm the keepalive watchdog from the advertised timeout (+ grace).
        // A migration source may already have a watchdog sleeping against its
        // own (possibly much longer) deadline. Merely updating the shared
        // deadline does not wake that task, so a valid target welcome must
        // invalidate the source generation and start a target-owned sleeper.
        let completesMigration = isMigratingSession
        if completesMigration {
            cancelKeepaliveWatchdog()
        }
        let timeout = TwitchChatService.keepaliveTimeoutSeconds(from: json)
            ?? AppConstants.Twitch.keepaliveDefaultTimeoutSeconds
        let deadline = TwitchChatService.keepaliveDeadline(
            timeoutSeconds: timeout, grace: AppConstants.Twitch.keepaliveGraceSeconds)
        armKeepaliveWatchdog(deadlineSeconds: deadline)

        // A `session_reconnect` migration carries its subscriptions to the new
        // session, so skip re-subscribing. Only fresh connects subscribe.
        if completesMigration {
            let sourceSocket = migrationSourceWebSocketTask
            migrationSourceWebSocketTask = nil
            sourceSocket?.cancel(with: .goingAway, reason: nil)
            migrationSourceReceiveTask?.cancel()
            migrationSourceReceiveTask = nil
            isMigratingSession = false
            reconnectionAttempts = 0
            networkReconnectCycles = 0
            broadcastConnectionState(true)
            Log.info(
                "TwitchChatService: Session migration complete; subscriptions carried over",
                category: "Twitch")
            return
        }

        let chatSubscribed = await subscribeToChannelChatMessage(
            receiveContext: receiveContext
        )
        guard receiveContextIsCurrent(receiveContext) else { return }
        guard chatSubscribed else { return }

        // A fresh connection is usable only after its critical chat
        // subscription succeeds. Reset retry budgets at that point, not merely
        // on session_welcome, so repeated subscription failures remain bounded.
        reconnectionAttempts = 0
        networkReconnectCycles = 0
        broadcastConnectionState(true)

        try? await Task.sleep(for: .milliseconds(200))
        guard receiveContextIsCurrent(receiveContext) else { return }
        await subscribeToPollEvents(receiveContext: receiveContext)
        guard receiveContextIsCurrent(receiveContext) else { return }
        try? await Task.sleep(for: .milliseconds(200))
        guard receiveContextIsCurrent(receiveContext) else { return }
        await subscribeToStreamEvents(receiveContext: receiveContext)
        guard receiveContextIsCurrent(receiveContext) else { return }
        await seedStreamLiveState(receiveContext: receiveContext)
        guard receiveContextIsCurrent(receiveContext) else { return }
        try? await Task.sleep(for: .milliseconds(200))
        guard receiveContextIsCurrent(receiveContext) else { return }
        await subscribeToRedemptionsIfEnabled(receiveContext: receiveContext)
    }

    /// Handles notification messages containing EventSub events.
    private func handleNotification(
        _ json: [String: Any],
        messageID: String,
        receiveContext: EventSubReceiveContext?
    ) async {
        guard receiveContextIsCurrent(receiveContext) else { return }
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
            handleBitsUse(
                payload, eventSubMessageID: messageID)
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
    private func subscribeToPollEvents(
        receiveContext: EventSubReceiveContext? = nil
    ) async {
        guard receiveContextIsCurrent(receiveContext) else { return }
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
        await postEventSubSubscription(
            body: body,
            token: token,
            clientID: clientID,
            label: "channel.poll.end",
            receiveContext: receiveContext
        )
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
    @discardableResult
    private func subscribeToChannelChatMessage(
        receiveContext: EventSubReceiveContext? = nil
    ) async -> Bool {
        guard receiveContextIsCurrent(receiveContext) else { return false }
        guard let sessionID,
              let broadcasterID,
              let botID,
              let token = oauthToken,
              let clientID else {
            Log.error(
                "TwitchChatService: Missing credentials for EventSub subscription",
                category: "Twitch")
            disconnectFromEventSub()
            return false
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
        let expectedCredential = TwitchCredentialStore.shared
            .connectionSnapshot(
                matchingAccessToken: token
            )?.accessExpectation
        var failureStatus: Int?
        let subscribed = await postEventSubSubscription(
            body: body,
            token: token,
            clientID: clientID,
            label: "channel.chat.message",
            receiveContext: receiveContext,
            onSuccess: {
                Log.info("TwitchChatService: Connected to chat", category: "Twitch")
                if shouldSendConnectionMessageOnSubscribe {
                    sendConnectionMessage()
                }
            },
            onFailureStatus: { status in
                failureStatus = status
            }
        )

        guard receiveContextIsCurrent(receiveContext) else { return false }
        guard !subscribed else { return true }

        if failureStatus == 401 {
            let generation = receiveContext?.generation ?? connectionGeneration
            Log.error(
                "TwitchChatService: Chat subscription returned 401; attempting token refresh",
                category: "Twitch")
            if let expectedCredential {
                let recovery = await recoverRejectedAccessToken(
                    expectedCredential,
                    clientID: clientID,
                    generation: generation,
                    broadcasterID: broadcasterID
                )
                guard receiveContextIsCurrent(receiveContext) else { return false }
                if case .invalid? = recovery {
                    signalReauthNeededAndStop()
                    return false
                }
            }
        }

        let reconnectCredentialIsReady = prepareCurrentStoredCredentialForReconnect(
            replacing: token,
            clientID: clientID,
            broadcasterID: broadcasterID,
            authorizedUserID: botID)
        // No welcomed socket may survive without the critical chat subscription.
        // If the stored grant rotated for this broadcaster, adopt it before
        // scheduling; a different/unresolved account remains disconnected.
        disconnectFromEventSub()
        if reconnectCredentialIsReady, isNetworkReachable { scheduleReconnect() }
        return false
    }

    #if DEBUG
    func subscribeToChannelChatMessageForTesting(
        receiveContext: EventSubReceiveContext
    ) async -> Bool {
        await subscribeToChannelChatMessage(receiveContext: receiveContext)
    }
    #endif

    /// Subscribes to `stream.online` / `stream.offline` so `streamLive` stays current.
    private func subscribeToStreamEvents(
        receiveContext: EventSubReceiveContext? = nil
    ) async {
        guard receiveContextIsCurrent(receiveContext) else { return }
        guard let sessionID,
              let broadcasterID,
              let token = oauthToken,
              let clientID else { return }

        for eventType in ["stream.online", "stream.offline"] {
            let body = Self.eventSubBody(
                type: eventType, broadcasterID: broadcasterID, sessionID: sessionID)
            await postEventSubSubscription(
                body: body,
                token: token,
                clientID: clientID,
                label: eventType,
                receiveContext: receiveContext
            )
            guard receiveContextIsCurrent(receiveContext) else { return }
        }
    }

    /// Seeds `streamLive` with a single Helix "Get Streams" call.
    private func seedStreamLiveState(
        receiveContext: EventSubReceiveContext? = nil
    ) async {
        guard receiveContextIsCurrent(receiveContext) else { return }
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
            guard receiveContextIsCurrent(receiveContext) else { return }
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
            guard receiveContextIsCurrent(receiveContext) else { return }
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
    /// A 409 is not success for WebSocket transport: the existing subscription
    /// may belong to the superseded socket. Twitch includes that subscription's
    /// exact ID in the error body, so delete it and retry the POST once.
    ///
    /// - Returns: `true` only after Twitch accepts the subscription POST.
    @discardableResult
    func postEventSubSubscription(
        body: [String: Any],
        token: String,
        clientID: String,
        label: String,
        receiveContext: EventSubReceiveContext? = nil,
        onSuccess: () -> Void = {},
        onFailureStatus: (Int) -> Void = { _ in }
    ) async -> Bool {
        guard receiveContextIsCurrent(receiveContext) else { return false }
        guard let url = URL(string: apiBaseURL + "/eventsub/subscriptions") else { return false }

        var recoveredConflict = false
        while true {
            let request: URLRequest
            do {
                request = try HelixClient.buildRequest(
                    url: url, method: "POST",
                    credentials: .init(token: token, clientID: clientID), body: body)
            } catch {
                guard receiveContextIsCurrent(receiveContext) else { return false }
                Log.error(
                    "TwitchChatService: Failed to serialize \(label) subscription - \(error.localizedDescription)",
                    category: "Twitch")
                return false
            }

            do {
                let (data, http) = try await eventSubHTTPClient.send(request)
                guard receiveContextIsCurrent(receiveContext) else { return false }
                if (200..<300).contains(http.statusCode) {
                    Log.info("TwitchChatService: Subscribed to \(label)", category: "Twitch")
                    onSuccess()
                    return true
                }
                if http.statusCode == 409,
                   !recoveredConflict,
                   let conflictingID = Self.conflictingSubscriptionID(from: data) {
                    recoveredConflict = true
                    let removed = await deleteConflictingEventSubSubscription(
                        id: conflictingID,
                        token: token,
                        clientID: clientID,
                        receiveContext: receiveContext,
                        onFailureStatus: onFailureStatus)
                    guard receiveContextIsCurrent(receiveContext), removed else { return false }
                    continue
                }

                let responseText = String(data: data, encoding: .utf8) ?? "No response"
                Log.error(
                    "TwitchChatService: \(label) subscription failed - HTTP \(http.statusCode) - \(responseText)",
                    category: "Twitch")
                if label == "channel-point redemptions" || label == "bit usage" {
                    setRedemptionStatus(http.statusCode == 403 ? .scopeMissing : .subscribeFailed)
                }
                onFailureStatus(http.statusCode)
                return false
            } catch {
                guard receiveContextIsCurrent(receiveContext) else { return false }
                Log.error(
                    "TwitchChatService: \(label) subscription error - \(error.localizedDescription)",
                    category: "Twitch")
                return false
            }
        }
    }

    /// Twitch's Create EventSub 409 response exposes the conflicting
    /// subscription as a top-level `id`. Tolerate the regular `data[0].id`
    /// envelope too so mocked/local Twitch-compatible endpoints work as well.
    nonisolated static func conflictingSubscriptionID(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let candidate = (json["id"] as? String)
            ?? ((json["data"] as? [[String: Any]])?.first?["id"] as? String)
        let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func deleteConflictingEventSubSubscription(
        id: String,
        token: String,
        clientID: String,
        receiveContext: EventSubReceiveContext?,
        onFailureStatus: (Int) -> Void
    ) async -> Bool {
        guard receiveContextIsCurrent(receiveContext),
              var components = URLComponents(string: apiBaseURL + "/eventsub/subscriptions") else {
            return false
        }
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        guard let url = components.url else { return false }

        do {
            let request = try HelixClient.buildRequest(
                url: url,
                method: "DELETE",
                credentials: .init(token: token, clientID: clientID))
            let (_, response) = try await eventSubHTTPClient.send(request)
            guard receiveContextIsCurrent(receiveContext) else { return false }
            if response.statusCode == 204 || response.statusCode == 404 {
                Log.info(
                    "TwitchChatService: Removed conflicting EventSub subscription \(id)",
                    category: "Twitch")
                return true
            }
            onFailureStatus(response.statusCode)
            Log.error(
                "TwitchChatService: Could not remove conflicting EventSub subscription - HTTP \(response.statusCode)",
                category: "Twitch")
            return false
        } catch {
            guard receiveContextIsCurrent(receiveContext) else { return false }
            Log.error(
                "TwitchChatService: Conflicting EventSub delete failed - \(error.localizedDescription)",
                category: "Twitch")
            return false
        }
    }
}
