//
//  TwitchChatService+Connection.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-01-08.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import Network

extension TwitchChatService {

    // MARK: - Network Monitoring

    /// Starts monitoring network connectivity and sets up automatic reconnection.
    func startNetworkMonitoring() {
        let monitor = NWPathMonitor()
        networkPathMonitor = monitor

        monitor.pathUpdateHandler = { [weak self] path in
            Task { await self?.handleNetworkPathChange(path) }
        }

        monitor.start(queue: networkMonitorQueue)
    }

    /// Handles network path changes and triggers reconnection if needed.
    ///
    /// Rate-limits network-triggered reconnects to prevent infinite loops when
    /// the network path flaps rapidly between available/unavailable states.
    private func handleNetworkPathChange(_ path: NWPath) async {
        let isReachable = path.status == .satisfied
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
            // Reset per-attempt counter for the new cycle
            reconnectionAttempts = 0
            scheduleReconnect()
        } else if wasReachable && !isReachable {
            Log.warn("TwitchChatService: Network unavailable, disconnecting", category: "Twitch")
            disconnectFromEventSub()
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
            // Reset attempts after hitting the limit to allow manual reconnection later
            reconnectionAttempts = 0
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
        do {
            try await connectToChannel(channelName: channelName, token: token, clientID: clientID)
            reconnectionAttempts = 0
            Log.info("TwitchChatService: Reconnection successful", category: "Twitch")
        } catch ConnectionError.authenticationFailed {
            // A 401 means the stored token is dead. Retrying with the same token
            // only burns `maxReconnectionAttempts` and never succeeds, so stop the
            // loop and surface the re-auth banner. Try one reactive token refresh
            // first; only fall back to interactive re-auth when that fails.
            Log.error(
                "TwitchChatService: Reconnect failed with 401; token is invalid or expired",
                category: "Twitch")
            await handleAuthenticationFailureDuringReconnect(
                channelName: channelName, clientID: clientID)
        } catch {
            reconnectionAttempts += 1
            Log.warn(
                "TwitchChatService: Reconnection attempt failed: \(error.localizedDescription)",
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
    /// refresh (no loop); on success it reconnects with the fresh token, and on
    /// any failure it signals interactive re-auth and stops the reconnect loop.
    private func handleAuthenticationFailureDuringReconnect(
        channelName: String, clientID: String
    ) async {
        if let refreshed = await TwitchTokenRefresher.attemptReactiveRefresh(clientID: clientID) {
            Log.info(
                "TwitchChatService: Reactive token refresh succeeded; reconnecting",
                category: "Twitch")
            reconnectToken = refreshed
            reconnectionAttempts = 0
            do {
                try await connectToChannel(
                    channelName: channelName, token: refreshed, clientID: clientID)
                Log.info(
                    "TwitchChatService: Reconnection successful after token refresh",
                    category: "Twitch")
                return
            } catch {
                Log.warn(
                    "TwitchChatService: Reconnect after refresh failed - \(error.localizedDescription)",
                    category: "Twitch")
            }
        }
        // Refresh unavailable or failed: stop looping and ask the user to re-auth.
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

    /// Arms (or re-arms) the keepalive watchdog for `deadlineSeconds`. Cancels any
    /// existing watchdog first so there is never more than one pending. On expiry
    /// it reuses the proven transport-error teardown: `disconnectFromEventSub()`
    /// then `scheduleReconnect()`.
    func armKeepaliveWatchdog(deadlineSeconds: TimeInterval) {
        keepaliveDeadlineSeconds = deadlineSeconds
        keepaliveWatchdogTask?.cancel()
        keepaliveWatchdogTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(deadlineSeconds))
            if Task.isCancelled { return }
            await self?.handleKeepaliveExpiry()
        }
    }

    /// Resets the keepalive watchdog to a full deadline. Called on every inbound
    /// frame. No-op until the watchdog has been armed by `session_welcome`.
    func resetKeepaliveWatchdog() {
        guard keepaliveWatchdogTask != nil else { return }
        armKeepaliveWatchdog(deadlineSeconds: keepaliveDeadlineSeconds)
    }

    /// Cancels the keepalive watchdog.
    private func cancelKeepaliveWatchdog() {
        keepaliveWatchdogTask?.cancel()
        keepaliveWatchdogTask = nil
    }

    /// Called when no frame arrived before the keepalive deadline. Treated like a
    /// transport error: tear down and reconnect fresh (which re-subscribes).
    private func handleKeepaliveExpiry() async {
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
        task?.cancel(with: .goingAway, reason: nil)

        sessionWelcomeTask?.cancel()
        sessionWelcomeTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        keepaliveWatchdogTask?.cancel()
        keepaliveWatchdogTask = nil
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
