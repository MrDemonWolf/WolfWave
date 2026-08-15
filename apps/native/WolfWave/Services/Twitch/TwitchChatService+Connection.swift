//
//  TwitchChatService+Connection.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-07-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import Network

extension TwitchChatService {

    // MARK: - Reconnect Decisions

    enum RefreshedReconnectFailureDisposition: Sendable, Equatable {
        case authenticationFailure
        case retryableFailure
        case cancelled
    }

    /// Separates a second 401 from cancellation and transient connection errors
    /// after a reactive token refresh.
    nonisolated static func refreshedReconnectFailureDisposition(
        for error: Error
    ) -> RefreshedReconnectFailureDisposition {
        if error is CancellationError { return .cancelled }
        if let connectionError = error as? ConnectionError,
           case .authenticationFailed = connectionError {
            return .authenticationFailure
        }
        return .retryableFailure
    }

    /// True only while the rejected credential still owns both durable storage
    /// and the actor session that issued the request.
    func rejectedCredentialIsCurrent(
        _ expected: TwitchCredentialStore.AccessExpectation,
        clientID: String,
        generation: UInt64,
        broadcasterID expectedBroadcasterID: String?
    ) -> Bool {
        !Task.isCancelled
            && connectionAttemptIsCurrent(generation)
            && oauthToken == expected.accessToken
            && self.clientID == clientID
            && (expectedBroadcasterID == nil || broadcasterID == expectedBroadcasterID)
            && TwitchCredentialStore.shared.matches(expected)
    }

    /// Reconnect-specific ownership check used when no active OAuth actor field
    /// has been published yet.
    private func reconnectCredentialIsCurrent(
        _ expected: TwitchCredentialStore.AccessExpectation,
        channelName: String,
        clientID: String,
        generation: UInt64
    ) -> Bool {
        !Task.isCancelled
            && connectionAttemptIsCurrent(generation)
            && reconnectChannelName == channelName
            && reconnectToken == expected.accessToken
            && reconnectClientID == clientID
            && TwitchCredentialStore.shared.matches(expected)
    }

    /// CAS-adopts a persisted access-token rotation into the active and reconnect
    /// state. If a backoff task captured the old token, reschedule it so it cannot
    /// wake, fail its stale-configuration guard, and silently end recovery.
    @discardableResult
    func adoptRefreshedAccessCredential(
        _ refreshed: TwitchCredentialStore.AccessExpectation,
        replacing rejected: TwitchCredentialStore.AccessExpectation,
        restartPendingReconnect: Bool = true
    ) -> Bool {
        guard refreshed.revision == rejected.revision,
              TwitchCredentialStore.shared.matches(refreshed) else {
            return false
        }

        let ownsRejected = oauthToken == rejected.accessToken
            || reconnectToken == rejected.accessToken
        let alreadyAdopted = oauthToken == refreshed.accessToken
            || reconnectToken == refreshed.accessToken
        guard ownsRejected || alreadyAdopted
                || (oauthToken == nil && reconnectToken == nil) else {
            return false
        }

        let hadPendingReconnect = reconnectTask != nil
            && reconnectToken == rejected.accessToken
        let hadLiveSession = webSocketTask != nil
            && oauthToken == rejected.accessToken
        if oauthToken == rejected.accessToken {
            oauthToken = refreshed.accessToken
        }
        if reconnectToken == rejected.accessToken {
            reconnectToken = refreshed.accessToken
        }
        if restartPendingReconnect && (hadPendingReconnect || hadLiveSession) {
            if hadLiveSession {
                // EventSub subscriptions are authorized for the token/session
                // pair that created them. A rotation starts a fresh generation.
                disconnectFromEventSub()
            }
            if isNetworkReachable { scheduleReconnect() }
        }
        return true
    }

    /// Adopts a stored rotation only when it still belongs to the actor's
    /// authorized chat user; broadcaster ownership is checked separately. A
    /// different or unresolved account remains disconnected so an old socket cannot outlive credential replacement.
    func prepareCurrentStoredCredentialForReconnect(
        replacing staleToken: String,
        clientID: String,
        broadcasterID: String,
        authorizedUserID: String
    ) -> Bool {
        guard self.clientID == clientID,
              self.broadcasterID == broadcasterID,
              botID == authorizedUserID else { return false }
        let reconnectCandidate = reconnectToken ?? staleToken
        if let matching = TwitchCredentialStore.shared.connectionSnapshot(
            matchingAccessToken: reconnectCandidate),
           matching.userID == authorizedUserID {
            return true
        }
        guard let current = TwitchCredentialStore.shared.connectionSnapshot(),
              current.userID == authorizedUserID else { return false }
        let stale = TwitchCredentialStore.AccessExpectation(
            revision: current.revision,
            accessToken: staleToken)
        return adoptRefreshedAccessCredential(
            current.accessExpectation,
            replacing: stale,
            restartPendingReconnect: false)
    }

    /// Runs the shared credential-keyed refresh decision for a 401 emitted by
    /// live chat or EventSub HTTP work. Every post-await result is revalidated
    /// before it may mutate actor state or authorize re-auth.
    func recoverRejectedAccessToken(
        _ expected: TwitchCredentialStore.AccessExpectation,
        clientID: String,
        generation: UInt64,
        broadcasterID expectedBroadcasterID: String?
    ) async -> TwitchTokenRefresher.RefreshResult? {
        guard rejectedCredentialIsCurrent(
            expected,
            clientID: clientID,
            generation: generation,
            broadcasterID: expectedBroadcasterID
        ) else { return nil }

        let result: TwitchTokenRefresher.RefreshResult
        do {
            result = try await reactiveTokenRefresh(clientID, expected: expected)
        } catch is CancellationError {
            return nil
        } catch {
            result = .temporarilyUnavailable
        }

        switch result {
        case .refreshed(let refreshedToken):
            let refreshed = expected.replacingAccessToken(refreshedToken)
            guard !Task.isCancelled,
                  connectionAttemptIsCurrent(generation),
                  oauthToken == expected.accessToken,
                  self.clientID == clientID,
                  expectedBroadcasterID == nil
                    || broadcasterID == expectedBroadcasterID,
                  TwitchCredentialStore.shared.matches(refreshed) else {
                return nil
            }
            guard adoptRefreshedAccessCredential(
                refreshed,
                replacing: expected,
                restartPendingReconnect: false
            ) else { return nil }
            return result
        case .invalid, .temporarilyUnavailable:
            guard rejectedCredentialIsCurrent(
                expected,
                clientID: clientID,
                generation: generation,
                broadcasterID: expectedBroadcasterID
            ) else { return nil }
            return result
        case .superseded:
            return nil
        }
    }

    // MARK: - Network Monitoring

    /// Starts monitoring network connectivity and sets up automatic reconnection.
    func startNetworkMonitoring() {
        networkPathMonitor?.pathUpdateHandler = nil
        networkPathMonitor?.cancel()
        networkMonitorGeneration &+= 1
        let generation = networkMonitorGeneration

        let monitor = NWPathMonitor()
        networkPathMonitor = monitor

        monitor.pathUpdateHandler = { [weak self] path in
            Task { await self?.handleNetworkPathChange(path, generation: generation) }
        }

        monitor.start(queue: networkMonitorQueue)
    }

    /// Handles network path changes and triggers reconnection if needed.
    ///
    /// Rate-limits network-triggered reconnects to prevent infinite loops when
    /// the network path flaps rapidly between available/unavailable states.
    private func handleNetworkPathChange(_ path: NWPath, generation: UInt64) async {
        guard generation == networkMonitorGeneration else { return }
        await handleNetworkReachabilityChange(path.status == .satisfied)
    }

    /// Boolean seam shared by the path monitor and lifecycle tests.
    func handleNetworkReachabilityChange(_ isReachable: Bool) async {
        let wasReachable = isNetworkReachable
        isNetworkReachable = isReachable

        if !wasReachable && isReachable {
            let now = Date().timeIntervalSince1970
            // Reset cycle counter if enough time has passed
            if now - lastNetworkReconnectTime > AppConstants.Twitch.networkReconnectCooldown {
                networkReconnectCycles = 0
            }

            guard networkReconnectCycles < maxNetworkReconnectCycles else {
                Log.error(
                    "TwitchChatService: Max network reconnect cycles reached, not reconnecting",
                    category: .twitchEvents)
                return
            }

            networkReconnectCycles += 1
            lastNetworkReconnectTime = now
            // An accepted network-recovery cycle gets its own bounded attempt
            // budget. Without this reset, a prior exhausted transport cycle
            // could never recover after connectivity actually returned.
            reconnectionAttempts = 0
            scheduleReconnect()
        } else if wasReachable && !isReachable {
            Log.warn("TwitchChatService: Network unavailable, disconnecting", category: .twitchEvents)
            // Do this before tearing down the socket so a delayed backoff task
            // cannot wake and consume an attempt while the machine is offline.
            reconnectTask?.cancel()
            reconnectTask = nil
            disconnectFromEventSub()
        }
    }

    // MARK: - Reconnection

    /// Schedules a reconnection attempt with exponential backoff. Cancels any
    /// existing scheduled attempt so we never have two pending at once.
    func scheduleReconnect() {
        guard !eventSubTeardownQuiescing.value else { return }
        guard let channelName = reconnectChannelName,
              let token = reconnectToken,
              let clientID = reconnectClientID else {
            Log.debug("TwitchChatService: Cannot reconnect - missing credentials", category: .twitchEvents)
            return
        }

        let attempts = reconnectionAttempts

        if attempts >= maxReconnectionAttempts {
            Log.error(
                "TwitchChatService: Max reconnection attempts reached",
                category: .twitchEvents,
                fields: ["limit": maxReconnectionAttempts])
            // Keep the exhausted count intact. A manual connection may still
            // start, and an accepted network-recovery cycle gets a fresh bounded
            // budget; otherwise only session_welcome proves transport success.
            return
        }

        // Exponential backoff: 1s, 2s, 4s, 8s, 16s
        let delaySeconds = min(pow(2.0, Double(attempts)), 16.0)

        Log.info(
            "TwitchChatService: Scheduling reconnection",
            category: .twitchEvents,
            fields: [
                "attempt": attempts + 1,
                "limit": maxReconnectionAttempts,
                "after": String(format: "%.1fs", delaySeconds)
            ])

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            // Backoff timing tolerates 10% jitter, lets the wakeup coalesce.
            try? await Task.sleep(for: .seconds(delaySeconds), tolerance: .seconds(delaySeconds * 0.1))
            if Task.isCancelled { return }
            await self?.attemptReconnect(channelName: channelName, token: token, clientID: clientID)
        }
    }

    private func attemptReconnect(channelName: String, token: String, clientID: String) async {
        guard !Task.isCancelled else {
            Log.debug(
                "TwitchChatService: Scheduled reconnect cancelled before starting",
                category: .twitchEvents)
            return
        }
        guard !isProcessingDisconnect else {
            Log.debug(
                "TwitchChatService: Disconnect in progress, skipping scheduled reconnect",
                category: .twitchEvents)
            return
        }
        guard reconnectChannelName == channelName,
              reconnectToken == token,
              reconnectClientID == clientID else {
            Log.info(
                "TwitchChatService: Connection configuration changed, skipping stale reconnect",
                category: .twitchEvents)
            return
        }
        guard isNetworkReachable else {
            Log.info(
                "TwitchChatService: Network unavailable, skipping scheduled reconnect",
                category: .twitchEvents)
            return
        }
        guard let expected = TwitchCredentialStore.shared
            .connectionSnapshot(
                matchingAccessToken: token
            )?.accessExpectation else {
            Log.info(
                "TwitchChatService: Stored credential changed, skipping stale reconnect",
                category: .twitchEvents)
            return
        }
        guard let attemptNumber = Self.nextReconnectAttempt(
            after: reconnectionAttempts,
            maximum: maxReconnectionAttempts
        ) else {
            Log.error(
                "TwitchChatService: Reconnection cap reached before attempt start",
                category: .twitchEvents)
            return
        }
        reconnectionAttempts = attemptNumber
        let generation = beginConnectionAttempt()

        do {
            try await connectToChannel(
                channelName: channelName,
                token: token,
                clientID: clientID,
                attemptGeneration: generation)
            Log.info(
                "TwitchChatService: Reconnection transport started, awaiting session_welcome",
                category: .twitchEvents,
                fields: ["attempt": attemptNumber, "limit": maxReconnectionAttempts])
        } catch ConnectionError.authenticationFailed {
            guard !Task.isCancelled, connectionAttemptIsCurrent(generation) else { return }
            // A 401 means the stored token is dead. Retrying with the same token
            // only burns `maxReconnectionAttempts` and never succeeds, so stop the
            // loop and surface the re-auth banner. Try one reactive token refresh
            // first; only fall back to interactive re-auth when that fails.
            Log.error(
                "TwitchChatService: Reconnect failed with 401; token is invalid or expired",
                category: .twitchEvents)
            await handleAuthenticationFailureDuringReconnect(
                expected: expected,
                channelName: channelName,
                clientID: clientID,
                attemptGeneration: generation)
        } catch is CancellationError {
            // A leave or newer connection attempt deliberately superseded this one.
            return
        } catch {
            guard connectionAttemptIsCurrent(generation) else { return }
            Log.warn(
                "TwitchChatService: Reconnection attempt failed",
                category: .twitchEvents,
                fields: ["attempt": attemptNumber, "error": error.localizedDescription])
            if reconnectionAttempts < maxReconnectionAttempts && isNetworkReachable {
                scheduleReconnect()
            } else if !isNetworkReachable {
                Log.info(
                    "TwitchChatService: Network no longer reachable, stopping reconnection attempts",
                    category: .twitchEvents)
            }
        }
    }

    /// Handles a 401 during reconnect. Attempts exactly ONE reactive token
    /// refresh (no loop). A second 401 signals interactive re-auth; a non-auth
    /// connection failure resumes the existing bounded reconnect backoff.
    private func handleAuthenticationFailureDuringReconnect(
        expected: TwitchCredentialStore.AccessExpectation,
        channelName: String,
        clientID: String,
        attemptGeneration: UInt64
    ) async {
        guard reconnectCredentialIsCurrent(
            expected,
            channelName: channelName,
            clientID: clientID,
            generation: attemptGeneration
        ) else { return }

        let refreshResult: TwitchTokenRefresher.RefreshResult
        do {
            refreshResult = try await reactiveTokenRefresh(
                clientID,
                expected: expected
            )
        } catch is CancellationError {
            return
        } catch {
            refreshResult = .temporarilyUnavailable
        }

        switch refreshResult {
        case .refreshed(let refreshedToken):
            let refreshed = expected.replacingAccessToken(refreshedToken)
            guard !Task.isCancelled,
                  connectionAttemptIsCurrent(attemptGeneration),
                  reconnectChannelName == channelName,
                  reconnectToken == expected.accessToken,
                  reconnectClientID == clientID,
                  TwitchCredentialStore.shared.matches(refreshed),
                  adoptRefreshedAccessCredential(
                    refreshed,
                    replacing: expected,
                    restartPendingReconnect: false
                  ) else { return }

            Log.info(
                "TwitchChatService: Reactive token refresh succeeded; reconnecting",
                category: .twitchEvents)
            let refreshedGeneration = beginConnectionAttempt()
            do {
                try await connectToChannel(
                    channelName: channelName,
                    token: refreshedToken,
                    clientID: clientID,
                    attemptGeneration: refreshedGeneration)
                Log.info(
                    "TwitchChatService: Reconnection transport started after token refresh; awaiting session_welcome",
                    category: .twitchEvents)
                return
            } catch {
                guard reconnectCredentialIsCurrent(
                    refreshed,
                    channelName: channelName,
                    clientID: clientID,
                    generation: refreshedGeneration
                ) else { return }
                switch Self.refreshedReconnectFailureDisposition(for: error) {
                case .cancelled:
                    return
                case .authenticationFailure:
                    Log.error(
                        "TwitchChatService: Refreshed token was rejected with 401",
                        category: .twitchEvents)
                    signalReauthNeededAndStop()
                    return
                case .retryableFailure:
                    Log.warn(
                        "TwitchChatService: Reconnect after refresh failed transiently - "
                            + error.localizedDescription,
                        category: .twitchEvents)
                    if reconnectionAttempts < maxReconnectionAttempts && isNetworkReachable {
                        scheduleReconnect()
                    } else if !isNetworkReachable {
                        Log.info(
                            "TwitchChatService: Network no longer reachable, "
                                + "stopping reconnection attempts",
                            category: .twitchEvents)
                    }
                    return
                }
            }
        case .invalid:
            guard reconnectCredentialIsCurrent(
                expected,
                channelName: channelName,
                clientID: clientID,
                generation: attemptGeneration
            ) else { return }
            signalReauthNeededAndStop()
        case .temporarilyUnavailable:
            guard reconnectCredentialIsCurrent(
                expected,
                channelName: channelName,
                clientID: clientID,
                generation: attemptGeneration
            ) else { return }
            Log.warn(
                "TwitchChatService: Token refresh temporarily unavailable; keeping credentials",
                category: .twitchEvents
            )
            if reconnectionAttempts < maxReconnectionAttempts && isNetworkReachable {
                scheduleReconnect()
            }
        case .superseded:
            return
        }
    }

    // MARK: - WebSocket Management

    /// Default Twitch EventSub WebSocket endpoint.
    private static let defaultEventSubURL = "wss://eventsub.wss.twitch.tv/ws"

    /// Connects to a Twitch EventSub WebSocket endpoint.
    ///
    /// - Parameter urlString: Endpoint to connect to. Defaults to the standard
    ///   EventSub URL; a `session_reconnect` migration passes the server-provided
    ///   `reconnect_url` instead so subscriptions carry over to the new session.
    func connectToEventSub(urlString: String = TwitchChatService.defaultEventSubURL) {
        guard !eventSubTeardownQuiescing.value else { return }
        guard let url = URL(string: urlString) else {
            Log.error("TwitchChatService: Invalid EventSub URL", category: .twitchEvents)
            disconnectFromEventSub()
            return
        }

        // Defensively cancel any pre-existing task before reassigning. Call
        // paths currently route through `disconnectFromEventSub()` first, but a
        // direct double-connect would otherwise orphan a live task.
        webSocketTask?.cancel(with: .goingAway, reason: nil)

        let task = eventSubWebSocketFactory?(url) ?? urlSession.webSocketTask(with: url)
        webSocketTask = task

        Log.info("TwitchChatService: Starting EventSub WebSocket connection", category: .twitchEvents)
        eventSubWebSocketResume(task)

        startSessionWelcomeTimeout(
            receiveContext: EventSubReceiveContext(
                generation: connectionGeneration,
                webSocketTask: task
            )
        )
        startReceiveLoop()
    }

    /// Starts a timeout task that fires if `session_welcome` doesn't arrive in time.
    private func startSessionWelcomeTimeout(receiveContext: EventSubReceiveContext) {
        sessionWelcomeTask?.cancel()
        sessionWelcomeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AppConstants.Twitch.sessionWelcomeTimeout))
            if Task.isCancelled { return }
            await self?.handleSessionWelcomeTimeout(receiveContext: receiveContext)
        }
    }

    /// Cancels the session welcome timeout.
    func cancelSessionWelcomeTimeout() {
        sessionWelcomeTask?.cancel()
        sessionWelcomeTask = nil
    }

    // MARK: - Keepalive Watchdog

    /// Arms one watchdog for the EventSub session. Subsequent inbound frames move
    /// the monotonic activity timestamp; they do not cancel/recreate the task.
    func armKeepaliveWatchdog(deadlineSeconds: TimeInterval) {
        keepaliveDeadlineSeconds = Self.normalizedKeepaliveDeadline(deadlineSeconds)
        let clock = ContinuousClock()
        lastKeepaliveActivity = clock.now

        guard keepaliveWatchdogTask == nil else { return }
        keepaliveGeneration &+= 1
        let generation = keepaliveGeneration
        keepaliveWatchdogTaskStarts += 1
        keepaliveWatchdogTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                guard let snapshot = await self?.keepaliveSleepSnapshot(generation: generation) else {
                    return
                }
                do {
                    try await clock.sleep(
                        until: snapshot.deadline,
                        tolerance: .seconds(snapshot.tolerance))
                } catch {
                    return
                }
                if Task.isCancelled { return }

                // Validate the session generation and expiry in one actor hop.
                // Cancellation alone is cooperative: a superseded task may have
                // passed its local check just before a new socket was armed.
                guard let shouldStop = await self?.handleKeepaliveExpiry(
                    generation: generation,
                    at: clock.now
                ) else { return }
                if shouldStop { return }
            }
        }
    }

    /// Records proof of life in O(1). No-op until `session_welcome` arms the
    /// watchdog.
    func resetKeepaliveWatchdog() {
        guard keepaliveWatchdogTask != nil else { return }
        lastKeepaliveActivity = ContinuousClock().now
    }

    private func keepaliveSleepSnapshot(generation: UInt64) -> (
        deadline: ContinuousClock.Instant,
        tolerance: TimeInterval
    )? {
        guard generation == keepaliveGeneration,
              let lastKeepaliveActivity else { return nil }
        let deadlineSeconds = Self.normalizedKeepaliveDeadline(keepaliveDeadlineSeconds)
        return (
            lastKeepaliveActivity.advanced(by: .seconds(deadlineSeconds)),
            min(1, deadlineSeconds * 0.1)
        )
    }

    /// Cancels the keepalive watchdog.
    func cancelKeepaliveWatchdog() {
        keepaliveGeneration &+= 1
        keepaliveWatchdogTask?.cancel()
        keepaliveWatchdogTask = nil
        lastKeepaliveActivity = nil
    }

    /// Called when no frame arrived before the keepalive deadline. Treated like a
    /// transport error: tear down and reconnect fresh (which re-subscribes).
    /// Returns `true` when the calling watchdog must terminate. A stale
    /// generation terminates without touching the current socket.
    func handleKeepaliveExpiry(
        generation: UInt64,
        at now: ContinuousClock.Instant
    ) -> Bool {
        guard generation == keepaliveGeneration else { return true }
        guard let snapshot = keepaliveSleepSnapshot(generation: generation) else { return true }
        guard now >= snapshot.deadline else { return false }

        Log.warn(
            "TwitchChatService: Keepalive watchdog fired, reconnecting",
            category: .twitchEvents,
            fields: ["seconds": Int(keepaliveDeadlineSeconds)])
        disconnectFromEventSub()

        if let channelName = reconnectChannelName,
           let token = reconnectToken,
           let clientID = reconnectClientID,
           !channelName.isEmpty, !token.isEmpty, !clientID.isEmpty,
           isNetworkReachable {
            scheduleReconnect()
        }
        return true
    }

    /// Called when session_welcome timeout expires.
    private func handleSessionWelcomeTimeout(
        receiveContext: EventSubReceiveContext
    ) async {
        guard !eventSubTeardownQuiescing.value,
              receiveContextIsCurrent(receiveContext) else { return }
        guard welcomedWebSocketTask !== receiveContext.webSocketTask else { return }

        // A welcome that never arrived means the (possibly migration) socket is
        // dead and we fall back to a fresh reconnect. Clear the migration flag so
        // the next fresh `session_welcome` re-subscribes normally. (disconnectFromEventSub
        // below also clears it, but reset here too so the contract is explicit and
        // independent of teardown ordering.)
        isMigratingSession = false

        Log.error(
            "TwitchChatService: Session welcome timeout - WebSocket may not be responding",
            category: .twitchEvents)
        disconnectFromEventSub()

        if let channelName = reconnectChannelName,
           let token = reconnectToken,
           let clientID = reconnectClientID,
           !channelName.isEmpty, !token.isEmpty, !clientID.isEmpty,
           isNetworkReachable {
            Log.info(
                "TwitchChatService: Attempting reconnection after session welcome timeout",
                category: .twitchEvents)
            scheduleReconnect()
        }
    }

    /// Disconnects from the EventSub WebSocket and clears session state.
    func disconnectFromEventSub(
        error: String? = nil,
        allowDuringCredentialTeardown: Bool = false
    ) {
        guard allowDuringCredentialTeardown
                || !eventSubTeardownQuiescing.value else {
            Log.debug(
                "TwitchChatService: Deferring EventSub disconnect during credential teardown",
                category: .twitchEvents)
            return
        }
        invalidateSessionBoundChatWork()
        let task = webSocketTask
        let migrationSourceTask = migrationSourceWebSocketTask
        webSocketTask = nil
        migrationSourceWebSocketTask = nil
        sessionID = nil
        pollSubscriptionSessionID = nil
        pollSubscriptionAttemptSessionID = nil
        welcomedWebSocketTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        migrationSourceTask?.cancel(with: .goingAway, reason: nil)

        sessionWelcomeTask?.cancel()
        sessionWelcomeTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        migrationSourceReceiveTask?.cancel()
        migrationSourceReceiveTask = nil
        cancelKeepaliveWatchdog()
        isMigratingSession = false
        broadcastConnectionState(false, error: error)

        Log.debug("TwitchChatService: EventSub WebSocket disconnected", category: .twitchEvents)
    }

    /// Stops the socket at the receive boundary without cancelling a receive
    /// task that may already be waiting to enter this actor with a paid frame.
    /// Once both loops finish, every frame returned by `receive()` has either
    /// completed routing or been rejected before the teardown cutoff.
    func quiesceEventSubReceiveBeforeCredentialTeardown(
        expectedOwnershipGeneration: UInt64,
        expectedConnectionGeneration: UInt64,
        timeout: Duration = .seconds(5)
    ) async -> Bool {
        guard eventSubTeardownQuiescing.value,
              channelOwnershipGeneration == expectedOwnershipGeneration,
              connectionGeneration == expectedConnectionGeneration else {
            return false
        }
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        migrationSourceWebSocketTask?.cancel(with: .goingAway, reason: nil)

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while receiveTask != nil || migrationSourceReceiveTask != nil {
            guard eventSubTeardownQuiescing.value,
                  channelOwnershipGeneration == expectedOwnershipGeneration,
                  connectionGeneration == expectedConnectionGeneration else {
                return false
            }
            guard clock.now < deadline else {
                Log.error(
                    "TwitchChatService: Timed out quiescing EventSub paid-event intake before credential teardown",
                    category: .twitchEvents)
                return false
            }
            do {
                try await Task.sleep(for: .milliseconds(25))
            } catch {
                return false
            }
        }
        return true
    }

    /// Drives the WebSocket receive loop. Replaces the recursive
    /// `task.receive { ... }` callback chain with a structured async loop
    /// that keeps frame ordering and integrates cleanly with actor isolation.
    private func startReceiveLoop() {
        receiveTask?.cancel()
        let task = webSocketTask
        let generation = connectionGeneration
        let receive = eventSubWebSocketReceive
        receiveTask = Task { [weak self] in
            guard let task else { return }
            let context = EventSubReceiveContext(
                generation: generation,
                webSocketTask: task
            )
            while !Task.isCancelled {
                do {
                    let message = try await receive(task)
                    if Task.isCancelled { break }
                    switch message {
                    case .string(let text):
                        await self?.handleWebSocketMessage(text, receiveContext: context)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            await self?.handleWebSocketMessage(text, receiveContext: context)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    // A teardown path (session migration, leaveChannel, reconnect)
                    // is the only thing that cancels this task, and cancelling the
                    // socket makes the suspended receive() throw. Bail so the
                    // orphaned loop doesn't run handleReceiveError against a socket
                    // that is already being replaced: doing so would reset
                    // isMigratingSession, flip the UI to disconnected, and schedule
                    // a reconnect that tears down the healthy migrated session.
                    if Task.isCancelled
                        || self?.eventSubTeardownQuiescing.value == true {
                        break
                    }
                    await self?.handleReceiveError(error, receiveContext: context)
                    break
                }
            }
            await self?.finishEventSubReceiveLoop(context)
        }
    }

    private func finishEventSubReceiveLoop(
        _ context: EventSubReceiveContext
    ) {
        if webSocketTask === context.webSocketTask {
            receiveTask = nil
        }
        if migrationSourceWebSocketTask === context.webSocketTask {
            migrationSourceReceiveTask = nil
        }
    }

    /// Handles a WebSocket receive error: logs, updates state, and attempts reconnect.
    private func handleReceiveError(
        _ error: Error,
        receiveContext: EventSubReceiveContext
    ) async {
        // Checked here on the actor, not in the receive loop: a separate
        // pre-check before the `handleReceiveError` await would race with
        // `leaveChannel()` flipping the flag between the two suspension points.
        guard !eventSubTeardownQuiescing.value,
              receiveContextIsCurrent(receiveContext) else { return }

        // Twitch explicitly allows the source socket to close after it has sent
        // `session_reconnect`. The replacement remains authoritative; an error
        // from the retained source must not tear it down or flip UI state.
        if isMigratingSession,
           migrationSourceWebSocketTask === receiveContext.webSocketTask {
            migrationSourceWebSocketTask?.cancel(with: .goingAway, reason: nil)
            migrationSourceWebSocketTask = nil
            migrationSourceReceiveTask = nil
            Log.info(
                "TwitchChatService: Migration source socket closed; awaiting replacement welcome",
                category: .twitchEvents)
            return
        }

        // A receive error on a migration socket leads to a fresh `scheduleReconnect`
        // below, NOT a reconnect_url migration. Clear the migration flag so the
        // resulting fresh `session_welcome` runs the normal `subscribeTo*` path
        // instead of being mistaken for a carried-over migrated session.
        isMigratingSession = false

        let nsError = error as NSError
        let errorCode = nsError.code
        let errorDomain = nsError.domain

        if errorDomain == NSURLErrorDomain && errorCode == NSURLErrorTimedOut {
            Log.error(
                "TwitchChatService: WebSocket connection timed out. This may be due to network issues, firewall blocking, or Twitch service problems.",
                category: .twitchEvents)
        } else {
            Log.error(
                "TwitchChatService: WebSocket connection error",
                category: .twitchEvents,
                fields: [
                    "error": error.localizedDescription,
                    "domain": errorDomain,
                    "code": errorCode
                ])
        }

        disconnectFromEventSub(error: error.localizedDescription)

        if let channelName = reconnectChannelName,
           let token = reconnectToken,
           let clientID = reconnectClientID,
           !channelName.isEmpty, !token.isEmpty, !clientID.isEmpty,
           isNetworkReachable {
            Log.info("TwitchChatService: Attempting automatic reconnection", category: .twitchEvents)
            scheduleReconnect()
        }
    }

    #if DEBUG
    func handleQueuedReceiveErrorForTesting(
        webSocketTask: URLSessionWebSocketTask
    ) async {
        await handleReceiveError(
            URLError(.networkConnectionLost),
            receiveContext: EventSubReceiveContext(
                generation: connectionGeneration,
                webSocketTask: webSocketTask))
    }
    #endif
}
