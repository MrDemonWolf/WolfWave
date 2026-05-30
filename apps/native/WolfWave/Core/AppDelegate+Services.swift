//
//  AppDelegate+Services.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-03.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit
import Foundation
import UserNotifications

// MARK: - Service Initialization

extension AppDelegate {

    /// Creates the playback source manager and sets this as delegate.
    func setupMusicMonitor() {
        playbackSourceManager = PlaybackSourceManager()
        playbackSourceManager?.delegate = self
    }

    /// Creates the Twitch chat service and wires up song info callbacks.
    func setupTwitchService() {
        twitchService = TwitchChatService()

        if TwitchChatService.resolveClientID() == nil {
            Log.error("AppDelegate: No Twitch Client ID found. Copy Config.xcconfig.example to Config.xcconfig and set your Client ID.", category: "Twitch")
        }

        // Async providers — the actor hops to MainActor inside each closure
        // to read AppDelegate state. Replaces the prior Thread.isMainThread +
        // DispatchQueue.main.sync dance (G5).
        twitchService?.setCurrentSongInfoProvider { [weak self] in
            await MainActor.run { self?.getCurrentSongInfo() ?? "Nothing playing right now" }
        }
        twitchService?.setLastSongInfoProvider { [weak self] in
            await MainActor.run { self?.getLastSongInfo() ?? "No previous track yet" }
        }
        twitchService?.setStatsInfoProvider { [weak self] in
            await MainActor.run { self?.getStatsInfo() ?? "No listening stats yet" }
        }
    }

    /// Creates the Discord RPC service, consumes its state / artwork streams, and enables if configured.
    func setupDiscordService() {
        let service = DiscordRPCService()
        discordService = service

        if DiscordRPCService.resolveClientID() != nil {
            Log.debug("AppDelegate: Resolved Discord Client ID from Info.plist", category: "Discord")
        } else {
            Log.info("AppDelegate: No Discord Client ID found. Set DISCORD_CLIENT_ID in Config.xcconfig to enable Discord Status.", category: "Discord")
        }

        discordStateConsumer = Task { @MainActor [weak self] in
            for await newState in service.stateChanges {
                _ = self
                let stateString: String
                switch newState {
                case .connected: stateString = "connected"
                case .connecting: stateString = "connecting"
                case .disconnected: stateString = "disconnected"
                }
                NotificationCenter.default.postDiscordState(stateString)
            }
        }

        discordArtworkConsumer = Task { @MainActor [weak self] in
            for await resolution in service.artworkResolutions {
                if let server = self?.websocketServer {
                    await server.updateArtworkURL(resolution.url)
                }
            }
        }

        let enabled = FeatureFlags.discordEnabled
        if enabled {
            Task { await service.setEnabled(true) }
        }
    }

    /// Creates the WebSocket server on the configured port and enables if configured.
    func setupWebSocketServer() {
        // Warm the LAN IP cache on a background task so the Now-Playing Server settings
        // can render the Network Address row instantly on first open instead of waiting
        // on `getifaddrs`. Synchronous work runs off-main; cache becomes visible to the
        // next view init. Also schedule an async refresh that picks up later interface
        // changes.
        Task.detached(priority: .userInitiated) {
            NetworkInfoService.warmCache()
        }
        Task.detached(priority: .utility) {
            await NetworkInfoService.shared.refreshIPv4()
        }

        // Prime the system font registry on a background thread. The Widget Appearance card's
        // Font picker calls `NSFontManager.availableFontFamilies` (200–800+ entries on
        // design-heavy Macs). Warming here makes the first call in-view near-instant.
        Task.detached(priority: .utility) {
            _ = NSFontManager.shared.availableFontFamilies
        }

        let storedPort = Preferences.websocketServerPort
        let port: UInt16 = storedPort > 0 ? UInt16(clamping: storedPort) : AppConstants.WebSocketServer.defaultPort

        let token = WebSocketAuthToken.currentOrCreate()
        Log.info(
            "AppDelegate: WebSocket server initialized on port \(port) (token=\(WebSocketAuthToken.redact(token)))",
            category: "WebSocket"
        )
        let server = WebSocketServerService(port: port, authToken: token)
        websocketServer = server

        let stateChanges = server.stateChanges
        Task.detached {
            for await (newState, clientCount) in stateChanges {
                Log.debug("AppDelegate: WebSocket state changed to \(newState.rawValue) (\(clientCount) clients)", category: "WebSocket")
                MetricsService.shared.recordWebSocketClients(clientCount)
            }
        }

        let enabled = FeatureFlags.websocketEnabled
        if enabled {
            Task { await server.setEnabled(true) }
        }
    }

    /// Creates the Sparkle updater and starts automatic update checking.
    func setupSparkleUpdater() {
        sparkleUpdater = SparkleUpdaterService()
        Log.info("AppDelegate: Sparkle updater initialized", category: "Update")
    }

    /// Records the app launch and applies the on-device diagnostics opt-in.
    func setupDiagnostics() {
        DiagnosticsService.shared.recordAppLaunch()
        DiagnosticsService.shared.applyEnabledState()
    }

    /// Creates the song request service and wires up playback monitoring + chat replies.
    func setupSongRequestService() {
        SongRequestService.migrateAccessSettings()

        let queue = SongRequestQueue()
        let blocklist = SongBlocklist()
        let musicController = AppleMusicController()
        let searchResolver = SongSearchResolver(musicController: musicController)

        songRequestService = SongRequestService(
            queue: queue,
            blocklist: blocklist,
            musicController: musicController,
            searchResolver: searchResolver
        )

        // Wire chat message sending for auto-advance announcements
        songRequestService?.sendChatMessage = { [weak self] message in
            guard let service = self?.twitchService else { return }
            Task { await service.sendMessage(message) }
        }

        // Wire commands to the service via TwitchChatService passthroughs
        if let twitchService {
            Task { [weak self] in
                await twitchService.setSongRequestService { [weak self] in
                    MainActor.assumeIsolated { self?.songRequestService }
                }
                await twitchService.setSongRequestQueue { [weak self] in
                    MainActor.assumeIsolated { self?.songRequestService?.queue }
                }
                // Direct reference for the channel-point / bit redemption handlers
                let reference = await MainActor.run { self?.songRequestService }
                await twitchService.setSongRequestServiceReference(reference)
            }
        }

        // Start playback monitoring if song requests are enabled
        let enabled = FeatureFlags.songRequestEnabled
        if enabled {
            songRequestService?.startPlaybackMonitoring()
        }

        setupSkipVoteManager()

        Log.info("AppDelegate: Song request service initialized", category: "SongRequest")
    }

    /// Creates the chat vote-to-skip manager and wires its skip + chat callbacks.
    ///
    /// Must run after `setupTwitchService()` and `songRequestService` exist so the
    /// skip action and chat-message relay can reach the live services.
    func setupSkipVoteManager() {
        let voteManager = SkipVoteManager()
        skipVoteManager = voteManager

        let performSkip: @Sendable () async -> Void = { [weak self] in
            let service = await MainActor.run { self?.songRequestService }
            await service?.voteSkip()
        }
        let sendChatMessage: @Sendable (String) -> Void = { [weak self] message in
            Task { @MainActor [weak self] in
                guard let service = self?.twitchService else { return }
                await service.sendMessage(message)
            }
        }
        let createPoll: @Sendable (String, Int) async -> Bool = { [weak self] title, duration in
            let service = await MainActor.run { self?.twitchService }
            return await service?.createSkipPoll(title: title, durationSeconds: duration) ?? false
        }
        let onVoteEvent: @Sendable (SkipVoteManager.VoteEvent) -> Void = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleVoteEvent(event)
            }
        }

        Task {
            await voteManager.configure(
                performSkip: performSkip,
                sendChatMessage: sendChatMessage,
                createPoll: createPoll,
                onVoteEvent: onVoteEvent
            )
        }

        if let twitchService {
            Task { [weak self] in
                await twitchService.setSkipVoteManager { [weak self] in
                    MainActor.assumeIsolated { self?.skipVoteManager }
                }
            }

            // Route finished Twitch polls back into the vote manager via the
            // AsyncStream surface.
            skipPollObserverTask?.cancel()
            skipPollObserverTask = Task { [weak self] in
                for await result in twitchService.skipPollResults {
                    await self?.skipVoteManager?.handlePollEnded(
                        skipVotes: result.skipVotes, keepVotes: result.keepVotes)
                }
            }
        }
    }

    /// Creates the listening history service and loads existing history if the
    /// feature is enabled.
    func setupHistoryService() {
        let enabled = FeatureFlags.listeningHistoryEnabled
        historyService = ListeningHistoryService(enabled: enabled)
        historyService?.start()
        Log.info(
            "AppDelegate: Listening history service initialized (enabled: \(enabled))",
            category: AppConstants.History.logCategory
        )
    }
}

// MARK: - Power State

extension AppDelegate {

    /// Initializes the power state monitor and registers for power state change notifications.
    func setupPowerStateMonitor() {
        _ = PowerStateMonitor.shared

        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: Notification.Name.powerStateChanged,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                nonisolated(unsafe) let n = notification
                MainActor.assumeIsolated { self?.powerStateChanged(n) }
            }
        )
    }

    /// Adjusts service polling intervals when system power state changes.
    @objc func powerStateChanged(_ notification: Notification) {
        let reduced = PowerStateMonitor.shared.isReducedMode

        playbackSourceManager?.updateCheckInterval(
            reduced ? AppConstants.PowerManagement.reducedMusicCheckInterval : 5.0
        )
        if let discordService {
            let discordInterval = reduced
                ? AppConstants.PowerManagement.reducedDiscordPollInterval
                : AppConstants.Discord.availabilityPollInterval
            Task { await discordService.updatePollInterval(discordInterval) }
        }
        let wsInterval: TimeInterval = reduced
            ? AppConstants.PowerManagement.reducedProgressBroadcastInterval
            : AppConstants.WebSocketServer.progressBroadcastInterval
        Task { [weak self] in await self?.websocketServer?.updateProgressInterval(wsInterval) }

        Log.debug("AppDelegate: Power state changed: reduced=\(reduced)", category: "App")
    }
}

// MARK: - Notification Observers

extension AppDelegate {

    /// Registers all `NotificationCenter` observers for settings and system events.
    func setupNotificationObservers() {
        let nc = NotificationCenter.default

        notificationObservers.append(
            nc.addObserver(
                forName: Notification.Name.trackingSettingChanged,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                nonisolated(unsafe) let n = notification
                MainActor.assumeIsolated { self?.trackingSettingChanged(n) }
            }
        )

        notificationObservers.append(
            nc.addObserver(
                forName: Notification.Name.dockVisibilityChanged,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                nonisolated(unsafe) let n = notification
                MainActor.assumeIsolated { self?.dockVisibilityChanged(n) }
            }
        )

        notificationObservers.append(
            nc.addObserver(
                forName: NSWindow.willCloseNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                nonisolated(unsafe) let n = notification
                MainActor.assumeIsolated {
                    guard let self,
                          let window = n.object as? NSWindow,
                          window !== self.settingsWindow,
                          window !== self.onboardingWindow else { return }
                    self.restoreMenuOnlyIfNeeded()
                }
            }
        )

        notificationObservers.append(
            nc.addObserver(
                forName: Notification.Name.discordPresenceChanged,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                nonisolated(unsafe) let n = notification
                MainActor.assumeIsolated { self?.discordPresenceSettingChanged(n) }
            }
        )

        notificationObservers.append(
            nc.addObserver(
                forName: Notification.Name.websocketServerChanged,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                nonisolated(unsafe) let n = notification
                MainActor.assumeIsolated { self?.websocketServerSettingChanged(n) }
            }
        )

        notificationObservers.append(
            nc.addObserver(
                forName: Notification.Name.widgetHTTPServerChanged,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                nonisolated(unsafe) let n = notification
                MainActor.assumeIsolated { self?.widgetHTTPServerSettingChanged(n) }
            }
        )

        notificationObservers.append(
            nc.addObserver(
                forName: Notification.Name.updateStateChanged,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                nonisolated(unsafe) let n = notification
                MainActor.assumeIsolated { self?.handleUpdateStateChanged(n) }
            }
        )

        notificationObservers.append(
            nc.addObserver(
                forName: Notification.Name.songRequestSettingChanged,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                nonisolated(unsafe) let n = notification
                MainActor.assumeIsolated { self?.songRequestSettingChanged(n) }
            }
        )

        notificationObservers.append(
            nc.addObserver(
                forName: Notification.Name.listeningHistorySettingChanged,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                nonisolated(unsafe) let n = notification
                MainActor.assumeIsolated { self?.listeningHistorySettingChanged(n) }
            }
        )
    }
}

// MARK: - Notification Handlers

extension AppDelegate {

    /// Starts or stops the music monitor when the tracking toggle changes.
    @objc func trackingSettingChanged(_ notification: Notification) {
        guard let enabled = notification.enabledFlag else { return }
        if enabled {
            playbackSourceManager?.startTracking()
            // Guarantee the ON edge yields a fresh now-playing read even
            // when the monitor was already running.
            playbackSourceManager?.forceRefresh()
        } else {
            stopTrackingAndUpdate()
        }
    }

    /// Pokes the active playback source to broadcast a fresh now-playing
    /// snapshot. Safe to call from the UI; no-ops if tracking is disabled.
    @MainActor
    func refreshNowPlaying() {
        playbackSourceManager?.forceRefresh()
    }

    /// Stops the music monitor and clears the now-playing display.
    private func stopTrackingAndUpdate() {
        playbackSourceManager?.stopTracking()
        postNowPlayingUpdate(song: nil, artist: nil, album: nil)
    }

    /// Enables or disables the Discord IPC service and pushes current track if enabling.
    @objc func discordPresenceSettingChanged(_ notification: Notification) {
        guard let enabled = notification.enabledFlag else { return }
        guard let discordService else { return }

        let song = currentSong
        let artist = currentArtist
        let album = currentAlbum ?? ""
        let playlist = currentPlaylist ?? ""
        let duration = currentDuration
        let elapsed = currentElapsed

        Task {
            await discordService.setEnabled(enabled)
            if enabled, let song, let artist {
                await discordService.updatePresence(
                    track: song,
                    artist: artist,
                    album: album,
                    playlist: playlist,
                    duration: duration,
                    elapsed: elapsed
                )
            }
        }
    }

    /// Applies the new dock visibility mode from the notification payload.
    @objc func dockVisibilityChanged(_ notification: Notification) {
        guard let mode = notification.modeString else { return }
        applyDockVisibility(mode)
    }

    /// Toggles the WebSocket server and applies any port change from the notification.
    @objc func websocketServerSettingChanged(_ notification: Notification) {
        let enabled = notification.enabledFlag ?? FeatureFlags.websocketEnabled
        let portChange = notification.portValue
        Task { [weak self] in
            await self?.websocketServer?.setEnabled(enabled)
            if let portChange {
                await self?.websocketServer?.updatePort(portChange)
            }
        }
    }

    /// Toggles the widget HTTP server independently from the WebSocket server.
    @objc func widgetHTTPServerSettingChanged(_ notification: Notification) {
        let enabled = notification.enabledFlag ?? FeatureFlags.widgetHTTPEnabled
        Task { [weak self] in await self?.websocketServer?.setWidgetHTTPEnabled(enabled) }
    }

    /// Starts or stops the song request playback monitor when the setting changes.
    @objc func songRequestSettingChanged(_ notification: Notification) {
        guard let enabled = notification.enabledFlag else { return }
        if enabled {
            songRequestService?.startPlaybackMonitoring()
        } else {
            songRequestService?.stopPlaybackMonitoring()
        }
    }

    /// Enables or disables listening-history recording when the toggle changes.
    @objc func listeningHistorySettingChanged(_ notification: Notification) {
        guard let enabled = notification.enabledFlag else { return }
        if enabled {
            historyService?.enable()
        } else {
            // Capture the in-progress play before recording stops.
            flushCurrentPlayToHistory()
            historyService?.disable()
        }
    }

    /// Shows a notification if a new version is available (Sparkle handles this automatically).
    @objc func handleUpdateStateChanged(_ notification: Notification) {
        guard let update = notification.updateState, update.isUpdateAvailable else { return }
        let version = update.latestVersion

        Log.info("AppDelegate: Update available notification received — v\(version)", category: "Update")
    }
}

// MARK: - Tracking State

extension AppDelegate {

    /// Defaults tracking to enabled on first launch, then starts or stops the monitor.
    func initializeTrackingState() {
        Preferences.seedTrackingEnabledDefaultIfNeeded()

        if isTrackingEnabled() {
            playbackSourceManager?.startTracking()
        } else {
            postNowPlayingUpdate(song: nil, artist: nil, album: nil)
        }
    }

    private func isTrackingEnabled() -> Bool {
        FeatureFlags.trackingEnabled
    }
}

// MARK: - Widget Artwork

extension AppDelegate {

    /// Fetches album artwork via the shared ArtworkService and forwards it to the WebSocket server.
    func fetchArtworkForWidget(track: String, artist: String) {
        ArtworkService.shared.fetchArtworkURL(track: track, artist: artist) { [weak self] url in
            guard let url else { return }
            Task { [weak self] in await self?.websocketServer?.updateArtworkURL(url) }
        }
    }
}

// MARK: - Twitch Token Validation

extension AppDelegate {

    @MainActor
    private func setReauthNeeded(_ needed: Bool) {
        Preferences.setTwitchReauthNeeded(needed)
    }

    private func showTwitchAuthNotification(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

        Task {
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound])
                guard granted else { return }
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                Log.error(
                    "AppDelegate: Failed to send notification: \(error.localizedDescription)",
                    category: "App"
                )
            }
        }
    }

    private func openSettingsToTwitch() {
        Preferences.setSelectedSettingsSection(AppConstants.Twitch.settingsSection)
        openSettings()
    }

    /// Validates the stored Twitch token on launch; prompts for re-auth if expired.
    func validateTwitchTokenOnBoot() async {
        guard let token = KeychainService.loadTwitchToken(), !token.isEmpty else {
            await MainActor.run { setReauthNeeded(false) }
            return
        }

        let isValid = await twitchService?.validateToken(token) ?? false
        await MainActor.run {
            setReauthNeeded(!isValid)

            if !isValid {
                showTwitchAuthNotification(
                    title: "Twitch Authentication Expired",
                    message: "Your Twitch session has expired. Please re-authorize in Settings."
                )
                openSettingsToTwitch()
            }
        }

        if isValid {
            await autoReconnectTwitchIfPossible(token: token)
        }
    }

    /// Auto-reconnects EventSub on launch when a valid token + channel name exist.
    ///
    /// Suppresses the "I'm online" chat ping that fires on explicit user-driven
    /// connects — auto-reconnect is silent. Called only after the token has been
    /// validated against Twitch.
    func autoReconnectTwitchIfPossible(token: String) async {
        guard let service = twitchService else { return }
        guard let clientID = TwitchChatService.resolveClientID(), !clientID.isEmpty else {
            Log.debug("AppDelegate: Skipping Twitch auto-reconnect — no Client ID", category: "Twitch")
            return
        }
        guard let channel = KeychainService.loadTwitchChannelID(), !channel.isEmpty else {
            Log.debug("AppDelegate: Skipping Twitch auto-reconnect — no stored channel name", category: "Twitch")
            return
        }

        Log.info("AppDelegate: Auto-reconnecting Twitch to channel \(channel)", category: "Twitch")
        await service.setShouldSendConnectionMessageOnSubscribe(false)
        do {
            try await service.connectToChannel(
                channelName: channel,
                token: token,
                clientID: clientID
            )
        } catch {
            Log.error(
                "AppDelegate: Twitch auto-reconnect failed - \(error.localizedDescription)",
                category: "Twitch"
            )
        }
    }
}

// MARK: - Playback Source Delegate

extension AppDelegate: PlaybackSourceDelegate {

    /// Updates track history, broadcasts to all services, and fetches artwork.
    func playbackSource(
        didUpdateTrack track: String,
        artist: String,
        album: String,
        playlist: String,
        duration: TimeInterval,
        elapsed: TimeInterval,
        isPaused: Bool
    ) {
        let isSameTrack = currentSong == track
        if !isSameTrack {
            // The outgoing track's last polled playhead position (`currentElapsed`)
            // is how far it actually played — hand it to history before we
            // overwrite the now-playing state.
            if let outgoing = currentSong, let outgoingArtist = currentArtist {
                historyService?.recordTrackChange(
                    track: outgoing,
                    artist: outgoingArtist,
                    album: currentAlbum ?? "",
                    duration: currentDuration,
                    playedSeconds: currentElapsed
                )
            }
            lastSong = currentSong
            lastArtist = currentArtist

            // Push the incoming track onto the tray-menu recents buffer.
            // De-dup happens inside the buffer so Music.app's resume
            // re-broadcasts don't pollute the list.
            recentTracks.push(RecentTrack(title: track, artist: artist, playedAt: Date()))

            // Suppress the first track after launch (it was already playing);
            // notify on every genuine change thereafter. Pause/resume of the
            // same track is filtered above by the `isSameTrack` guard so
            // toggling play state never re-fires the banner.
            if hasSeenInitialTrack {
                maybePostSongChangeNotification(track: track, artist: artist, album: album)
            }
            hasSeenInitialTrack = true
        }

        currentSong = track
        currentArtist = artist
        currentAlbum = album
        currentPlaylist = playlist
        currentDuration = duration
        currentElapsed = elapsed
        currentIsPaused = isPaused

        postNowPlayingUpdate(song: track, artist: artist, album: album, playlist: playlist, isPaused: isPaused)

        Task { [weak self] in
            await self?.websocketServer?.updateNowPlaying(
                track: track,
                artist: artist,
                album: album,
                duration: duration,
                elapsed: elapsed,
                isPaused: isPaused
            )
        }

        fetchArtworkForWidget(track: track, artist: artist)

        if let discordService {
            Task {
                await discordService.updatePresence(
                    track: track,
                    artist: artist,
                    album: album,
                    playlist: playlist,
                    duration: duration,
                    elapsed: elapsed,
                    isPaused: isPaused
                )
            }
        }
    }

    /// Posts a macOS song-change notification when the user has enabled the
    /// setting. Called only on a genuine track change, never on the first
    /// track seen after launch.
    private func maybePostSongChangeNotification(track: String, artist: String, album: String) {
        guard FeatureFlags.songChangeNotificationsEnabled else { return }

        Task {
            await NotificationService.shared.postSongChange(track: track, artist: artist, album: album)
        }
    }

    /// Posts a macOS notification for a skip-vote lifecycle event when both the
    /// vote-skip feature and the matching notification toggle are on.
    ///
    /// Belt-and-braces gating: the settings UI already hides/disables these
    /// toggles when vote-skip is off, but we re-check `voteSkipEnabled` here so a
    /// stale persisted toggle can't fire a notification for an impossible event.
    @MainActor
    func handleVoteEvent(_ event: SkipVoteManager.VoteEvent) {
        guard FeatureFlags.voteSkipEnabled else { return }

        let track = currentSong ?? ""
        let artist = currentArtist ?? ""

        switch event {
        case .started(let needed):
            guard FeatureFlags.skipVoteStartedNotificationsEnabled else { return }
            Task {
                await NotificationService.shared.postSkipVoteStarted(
                    track: track, artist: artist, votesNeeded: needed, viaPoll: false)
            }
        case .pollStarted:
            guard FeatureFlags.skipVoteStartedNotificationsEnabled else { return }
            Task {
                await NotificationService.shared.postSkipVoteStarted(
                    track: track, artist: artist, votesNeeded: 0, viaPoll: true)
            }
        case .passed:
            guard FeatureFlags.skipVotePassedNotificationsEnabled else { return }
            Task {
                await NotificationService.shared.postSkipVotePassed(track: track, artist: artist)
            }
        }
    }

    /// Clears track state and notifies services when playback stops.
    func playbackSource(didUpdateStatus status: String) {
        Log.info("AppDelegate: Playback status = \(status)", category: "Music")

        // Any of these statuses mean "no track is reliably playing right now" —
        // flush in-progress history and blank the cached snapshot so Discord
        // Rich Presence and the WebSocket overlay don't keep broadcasting a
        // stale song after Music quits, permission is revoked, or SB errors out.
        let shouldClearPlayback = status == "No track playing"
            || status == "Music access denied"
            || status == "Music not running"
            || status == "No track info"
            || status == "Script error"

        if shouldClearPlayback {
            flushCurrentPlayToHistory()
            currentSong = nil
            currentArtist = nil
            currentAlbum = nil
            currentPlaylist = nil
            currentIsPaused = false
        }

        if status == "Music access denied" {
            // Tell the Music Monitor settings view to flip its banner now,
            // without waiting for the next AEDeterminePermissionToAutomateTarget
            // poll or the user clicking Recheck.
            NotificationCenter.default.post(name: .musicPermissionDenied, object: nil)
        }

        postNowPlayingUpdate(song: nil, artist: nil, album: nil)

        if shouldClearPlayback {
            if let discordService {
                Task { await discordService.clearPresence() }
            }
            Task { [weak self] in await self?.websocketServer?.clearNowPlaying() }
        }
    }
}
