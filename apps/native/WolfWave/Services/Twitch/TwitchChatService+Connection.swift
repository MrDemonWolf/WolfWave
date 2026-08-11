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
                    category: "Twitch")
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
            Log.warn("TwitchChatService: Network unavailable, disconnecting", category: "Twitch")
            // Do this before tearing down the socket so a delayed backoff task
            // cannot wake and consume an attempt while the machine is offline.
            reconnectTask?.cancel()
            reconnectTask = nil
            connectionGeneration &+= 1
            disconnectFromEventSub()
            broadcastConnectionState(false)
        }
    }

    // MARK: - Reconnection

    /// Schedules a reconnection attempt with exponential backoff. Cancels any
    /// existing scheduled attempt so we never have two pending at once.
    func scheduleReconnect() {
        guard let channelName = reconnectChannelName,
              let token = reconnectToken,
              let clientID = reconnectClientID else {
            Log.debug("TwitchChatService: Cannot reconnect - missing credentials", category: "Twitch")
            return
        }

        let attempts = reconnectionAttempts

        if attempts >= maxReconnectionAttempts {
            Log.error(
                "TwitchChatService: Max reconnection attempts reached (\(maxReconnectionAttempts))",
                category: "Twitch")
            // Keep the exhausted count intact. A manual connection may still
            // start, and an accepted network-recovery cycle gets a fresh bounded
            // budget; otherwise only session_welcome proves transport success.
            return
        }

        // Exponential backoff: 1s, 2s, 4s, 8s, 16s
        let delaySeconds = min(pow(2.0, Double(attempts)), 16.0)

        Log.info(
            "TwitchChatService: Scheduling reconnection attempt \(attempts + 1)/\(maxReconnectionAttempts) in \(String(format: "%.1f", delaySeconds))s",
            category: "Twitch")

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
                category: "Twitch")
            return
        }
        guard !isProcessingDisconnect else {
            Log.debug(
                "TwitchChatService: Disconnect in progress, skipping scheduled reconnect",
                category: "Twitch")
            return
        }
        guard reconnectChannelName == channelName,
              reconnectToken == token,
              reconnectClientID == clientID else {
            Log.info(
                "TwitchChatService: Connection configuration changed, skipping stale reconnect",
                category: "Twitch")
            return
        }
        guard isNetworkReachable else {
            Log.info(
                "TwitchChatService: Network unavailable, skipping scheduled reconnect",
                category: "Twitch")
            return
        }
        guard let attemptNumber = Self.nextReconnectAttempt(
            after: reconnectionAttempts,
            maximum: maxReconnectionAttempts
        ) else {
            Log.error(
                "TwitchChatService: Reconnection cap reached before attempt start",
                category: "Twitch")
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
                "TwitchChatService: Reconnection transport started "
                    + "(attempt \(attemptNumber)/\(maxReconnectionAttempts)); "
                    + "awaiting session_welcome",
                category: "Twitch")
        } catch ConnectionError.authenticationFailed {
            guard !Task.isCancelled, connectionAttemptIsCurrent(generation) else { return }
            // A 401 means the stored token is dead. Retrying with the same token
            // only burns `maxReconnectionAttempts` and never succeeds, so stop the
            // loop and surface the re-auth banner. Try one reactive token refresh
            // first; only fall back to interactive re-auth when that fails.
            Log.error(
                "TwitchChatService: Reconnect failed with 401; token is invalid or expired",
                category: "Twitch")
            await handleAuthenticationFailureDuringReconnect(
                channelName: channelName,
                clientID: clientID,
                attemptGeneration: generation)
        } catch is CancellationError {
            // A leave or newer connection attempt deliberately superseded this one.
            return
        } catch {
            guard connectionAttemptIsCurrent(generation) else { return }
            Log.warn(
                "TwitchChatService: Reconnection attempt \(attemptNumber) failed: \(error.localizedDescription)",
                category: "Twitch")
            if reconnectionAttempts < maxReconnectionAttempts && isNetworkReachable {
                scheduleReconnect()
            } else if !isNetworkReachable {
                Log.info(
                    "TwitchChatService: Network no longer reachable, stopping reconnection attempts",
                    category: "Twitch")
            }
        }
    }

    /// Handles a 401 during reconnect. Attempts exactly ONE reactive token
    /// refresh (no loop). A second 401 signals interactive re-auth; a non-auth
    /// connection failure resumes the existing bounded reconnect backoff.
    private func handleAuthenticationFailureDuringReconnect(
        channelName: String,
        clientID: String,
        attemptGeneration: UInt64
    ) async {
        var terminalGeneration = attemptGeneration
        if let refreshed = await TwitchTokenRefresher.attemptReactiveRefresh(clientID: clientID) {
            guard !Task.isCancelled,
                  connectionAttemptIsCurrent(attemptGeneration),
                  reconnectChannelName == channelName,
                  reconnectClientID == clientID else { return }
            Log.info(
                "TwitchChatService: Reactive token refresh succeeded; reconnecting",
                category: "Twitch")
            reconnectToken = refreshed
            let refreshedGeneration = beginConnectionAttempt()
            terminalGeneration = refreshedGeneration
            do {
                try await connectToChannel(
                    channelName: channelName,
                    token: refreshed,
                    clientID: clientID,
                    attemptGeneration: refreshedGeneration)
                Log.info(
                    "TwitchChatService: Reconnection transport started after token refresh; awaiting session_welcome",
                    category: "Twitch")
                return
            } catch {
                guard connectionAttemptIsCurrent(refreshedGeneration) else { return }
                switch Self.refreshedReconnectFailureDisposition(for: error) {
                case .cancelled:
                    return
                case .authenticationFailure:
                    Log.error(
                        "TwitchChatService: Refreshed token was rejected with 401",
                        category: "Twitch")
                case .retryableFailure:
                    Log.warn(
                        "TwitchChatService: Reconnect after refresh failed transiently - "
                            + error.localizedDescription,
                        category: "Twitch")
                    if reconnectionAttempts < maxReconnectionAttempts && isNetworkReachable {
                        scheduleReconnect()
                    } else if !isNetworkReachable {
                        Log.info(
                            "TwitchChatService: Network no longer reachable, "
                                + "stopping reconnection attempts",
                            category: "Twitch")
                    }
                    return
                }
            }
        }
        // Refresh unavailable or failed: stop looping and ask the user to re-auth.
        guard connectionAttemptIsCurrent(terminalGeneration) else { return }
        signalReauthNeededAndStop()
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
        guard let url = URL(string: urlString) else {
            Log.error("TwitchChatService: Invalid EventSub URL", category: "Twitch")
            broadcastConnectionState(false)
            return
        }

        // Defensively cancel any pre-existing task before reassigning. Call
        // paths currently route through `disconnectFromEventSub()` first, but a
        // direct double-connect would otherwise orphan a live task.
        webSocketTask?.cancel(with: .goingAway, reason: nil)

        let task = urlSession.webSocketTask(with: url)
        webSocketTask = task

        Log.info("TwitchChatService: Starting EventSub WebSocket connection", category: "Twitch")
        task.resume()

        startSessionWelcomeTimeout()
        startReceiveLoop()
    }

    /// Starts a timeout task that fires if `session_welcome` doesn't arrive in time.
    private func startSessionWelcomeTimeout() {
        sessionWelcomeTask?.cancel()
        sessionWelcomeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AppConstants.Twitch.sessionWelcomeTimeout))
            if Task.isCancelled { return }
            await self?.handleSessionWelcomeTimeout()
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
        keepaliveDeadlineSeconds = max(1, deadlineSeconds)
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
        return (
            lastKeepaliveActivity.advanced(by: .seconds(keepaliveDeadlineSeconds)),
            min(1, keepaliveDeadlineSeconds * 0.1)
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
            "TwitchChatService: Keepalive watchdog fired (no frame within \(Int(keepaliveDeadlineSeconds))s); reconnecting",
            category: "Twitch")
        broadcastConnectionState(false)

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
    private func handleSessionWelcomeTimeout() async {
        guard sessionID == nil else { return } // If we already got a welcome, ignore

        // A welcome that never arrived means the (possibly migration) socket is
        // dead and we fall back to a fresh reconnect. Clear the migration flag so
        // the next fresh `session_welcome` re-subscribes normally. (disconnectFromEventSub
        // below also clears it, but reset here too so the contract is explicit and
        // independent of teardown ordering.)
        isMigratingSession = false

        Log.error(
            "TwitchChatService: Session welcome timeout - WebSocket may not be responding",
            category: "Twitch")
        broadcastConnectionState(false)

        disconnectFromEventSub()

        if let channelName = reconnectChannelName,
           let token = reconnectToken,
           let clientID = reconnectClientID,
           !channelName.isEmpty, !token.isEmpty, !clientID.isEmpty,
           isNetworkReachable {
            Log.info(
                "TwitchChatService: Attempting reconnection after session welcome timeout",
                category: "Twitch")
            scheduleReconnect()
        }
    }

    /// Disconnects from the EventSub WebSocket and clears session state.
    func disconnectFromEventSub() {
        setConnected(false)
        let task = webSocketTask
        webSocketTask = nil
        sessionID = nil
        pollSubscriptionSessionID = nil
        pollSubscriptionAttemptSessionID = nil
        task?.cancel(with: .goingAway, reason: nil)

        sessionWelcomeTask?.cancel()
        sessionWelcomeTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        cancelKeepaliveWatchdog()
        isMigratingSession = false

        Log.debug("TwitchChatService: EventSub WebSocket disconnected", category: "Twitch")
    }

    /// Drives the WebSocket receive loop. Replaces the recursive
    /// `task.receive { ... }` callback chain with a structured async loop
    /// that keeps frame ordering and integrates cleanly with actor isolation.
    private func startReceiveLoop() {
        receiveTask?.cancel()
        let task = webSocketTask
        receiveTask = Task { [weak self] in
            guard let task else { return }
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    switch message {
                    case .string(let text):
                        await self?.handleWebSocketMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            await self?.handleWebSocketMessage(text)
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
                    if Task.isCancelled { return }
                    await self?.handleReceiveError(error)
                    return
                }
            }
        }
    }

    /// Handles a WebSocket receive error: logs, updates state, and attempts reconnect.
    private func handleReceiveError(_ error: Error) async {
        // Checked here on the actor, not in the receive loop: a separate
        // pre-check before the `handleReceiveError` await would race with
        // `leaveChannel()` flipping the flag between the two suspension points.
        if isProcessingDisconnect { return }

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
                category: "Twitch")
        } else {
            Log.error(
                "TwitchChatService: WebSocket connection error: \(error.localizedDescription) (Domain: \(errorDomain), Code: \(errorCode))",
                category: "Twitch")
        }

        broadcastConnectionState(false, error: error.localizedDescription)

        if let channelName = reconnectChannelName,
           let token = reconnectToken,
           let clientID = reconnectClientID,
           !channelName.isEmpty, !token.isEmpty, !clientID.isEmpty,
           isNetworkReachable {
            Log.info("TwitchChatService: Attempting automatic reconnection", category: "Twitch")
            scheduleReconnect()
        }
    }
}
