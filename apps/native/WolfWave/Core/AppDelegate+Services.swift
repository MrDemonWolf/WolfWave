//
//  AppDelegate+Services.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-03.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit
import Foundation

// MARK: - Playback Flush Guards

// File-scope because `AppDelegate` extensions cannot add stored properties.
// The app has exactly one delegate instance, and the module's MainActor
// default isolates these globals to the main actor alongside the
// `PlaybackSourceDelegate` callbacks that touch them.

/// Consecutive `Script error` statuses received from the playback source.
/// ScriptingBridge reads are documented flaky on macOS 26, so one bad read
/// mid-track must not flush history and blank the now-playing snapshot.
private var consecutiveScriptErrorCount = 0

/// How many consecutive `Script error` statuses are required before playback
/// is treated as genuinely stopped.
private let scriptErrorStopThreshold = 3

/// `true` once the in-progress play has been written to listening history
/// (History toggle-off flush or a sustained playback stop). Blocks the same
/// play from being recorded a second time; resets when a new track starts.
private var currentPlayFlushedToHistory = false

// MARK: - Service Initialization

extension AppDelegate {

    /// Runs one service-setup closure, isolating a *synchronous* construction
    /// failure so a single bad service degrades instead of aborting the whole
    /// launch sequence. The setups' async bodies (`Task { … }`) still handle
    /// their own errors; a truly unforeseen ObjC exception is caught
    /// process-wide by `CrashReporter`. `name` labels the service in the log.
    func guardedStart(_ name: String, _ body: () throws -> Void) {
        do {
            try body()
        } catch {
            Log.error(
                "AppDelegate: service \(name) failed to start: \(error.localizedDescription)",
                category: "App"
            )
        }
    }

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

        // Async providers. The actor hops to MainActor inside each closure
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
        // Font picker calls `NSFontManager.availableFontFamilies` (200-800+ entries on
        // design-heavy Macs). Warming here makes the first call in-view near-instant.
        Task.detached(priority: .utility) {
            _ = NSFontManager.shared.availableFontFamilies
        }

        let port = Preferences.resolvedWebSocketServerPort

        let token = WebSocketAuthToken.currentOrCreate()
        Log.info(
            "AppDelegate: WebSocket server initialized on port \(port) (token=\(WebSocketAuthToken.redact(token)))",
            category: "WebSocket"
        )
        let server = WebSocketServerService(port: port, authToken: token)
        websocketServer = server

        // Handle inbound Stream Deck control commands. The connection is already
        // token-gated at the handshake, so commands from it are trusted.
        Task { [weak self] in
            await server.setCommandHandler { [weak self] command in
                await self?.handleStreamDeckCommand(command)
                    ?? CommandAck.failure(command.action.rawValue, "unavailable")
            }
        }

        let stateChanges = server.stateChanges
        Task.detached { [weak self] in
            for await (newState, clientCount) in stateChanges {
                Log.debug("AppDelegate: WebSocket state changed to \(newState.rawValue) (\(clientCount) clients)", category: "WebSocket")
                MetricsService.shared.recordWebSocketClients(clientCount)
                // Push a fresh queue/health snapshot so a newly connected Stream
                // Deck key shows correct state immediately instead of waiting for
                // the next change.
                if clientCount > 0 {
                    await MainActor.run { self?.broadcastStreamDeckState() }
                }
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
        SongRequestService.migrateSetupState()

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

        // Verify the requests playlist is still set up and shared. Catches a
        // playlist deleted or un-shared between launches and surfaces the "needs
        // setup again" banner; no-op until the guided setup has been finished.
        Task { [weak self] in
            await self?.songRequestService?.runSetupHealthCheck()
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

        observeOnMain(Notification.Name.powerStateChanged) { [weak self] n in
            self?.powerStateChanged(n)
        }
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

// MARK: - Overlay Toggle

extension AppDelegate {

    /// Applies the overlay on/off state shared by the tray toggle
    /// (`toggleWebSocket`) and the Stream Deck `.overlayToggle` action: flips the
    /// WebSocket and widget-HTTP prefs in lockstep and broadcasts the change.
    ///
    /// Synchronous by design so the pref write and notification post are not
    /// deferred into a `Task` (a synchronous observer would otherwise briefly
    /// read the stale value). Callers own the async
    /// `websocketServer.setWidgetHTTPEnabled(_:)` hop.
    func applyOverlayEnabled(_ newValue: Bool) {
        Preferences.setWebSocketEnabled(newValue)
        // Keep widgetHTTPEnabled in sync: OBS loads the widget page over HTTP,
        // so the overlay stays blank if the WebSocket channel comes up without it.
        Preferences.setWidgetHTTPEnabled(newValue)
        NotificationCenter.default.postWebSocketServerChanged(
            enabled: newValue,
            widgetHTTPEnabled: newValue
        )
    }
}

// MARK: - Notification Observers

extension AppDelegate {

    /// Registers a `NotificationCenter` observer that runs `handler` on the main
    /// actor and stores the token in `notificationObservers` for teardown.
    ///
    /// Collapses the repeated `queue: .main` + `nonisolated(unsafe) let n` +
    /// `MainActor.assumeIsolated` incantation shared by every settings/system
    /// observer. `queue: .main` guarantees the block runs on the main thread,
    /// which is what keeps `assumeIsolated` sound. Observers with custom bodies
    /// (window-close filtering, notifications dropped with `_`) stay inline.
    private func observeOnMain(
        _ name: NSNotification.Name,
        _ handler: @escaping @MainActor (Notification) -> Void
    ) {
        notificationObservers.append(
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { notification in
                nonisolated(unsafe) let n = notification
                MainActor.assumeIsolated { handler(n) }
            }
        )
    }

    /// Registers all `NotificationCenter` observers for settings and system
    /// events, and installs the user-notification center delegate.
    func setupNotificationObservers() {
        // Present WolfWave banners while the app is frontmost. Without a
        // `UNUserNotificationCenterDelegate`, macOS suppresses every banner
        // for the foreground app, exactly when the user is in Settings
        // flipping the notification toggles and expecting a preview.
        NotificationService.shared.installCenterDelegate()

        let nc = NotificationCenter.default

        observeOnMain(Notification.Name.trackingSettingChanged) { [weak self] n in
            self?.trackingSettingChanged(n)
        }
        observeOnMain(Notification.Name.dockVisibilityChanged) { [weak self] n in
            self?.dockVisibilityChanged(n)
        }

        // Custom body — kept inline. Onboarding and What's New are handled by
        // their own `windowWillClose` delegate. Every other closing window,
        // including SwiftUI's Settings scene window, falls through here to
        // restore menu-only mode.
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
                          window !== self.onboardingWindow,
                          window !== self.whatsNewWindow else { return }
                    self.restoreMenuOnlyIfNeeded()
                }
            }
        )

        observeOnMain(Notification.Name.discordPresenceChanged) { [weak self] n in
            self?.discordPresenceSettingChanged(n)
        }
        observeOnMain(Notification.Name.websocketServerChanged) { [weak self] n in
            self?.websocketServerSettingChanged(n)
        }
        observeOnMain(Notification.Name.widgetHTTPServerChanged) { [weak self] n in
            self?.widgetHTTPServerSettingChanged(n)
        }
        observeOnMain(Notification.Name.updateStateChanged) { [weak self] n in
            self?.handleUpdateStateChanged(n)
        }
        observeOnMain(Notification.Name.songRequestSettingChanged) { [weak self] n in
            self?.songRequestSettingChanged(n)
        }
        observeOnMain(Notification.Name.listeningHistorySettingChanged) { [weak self] n in
            self?.listeningHistorySettingChanged(n)
        }
        observeOnMain(Notification.Name.twitchConnectionStateChanged) { [weak self] n in
            self?.twitchConnectionStateChanged(n)
        }

        // Custom body (drops the notification payload) — kept inline. Refreshes
        // the Stream Deck queue-counter / health broadcasts whenever the request
        // queue changes so a counter key stays live without polling.
        notificationObservers.append(
            nc.addObserver(
                forName: Notification.Name.songRequestQueueChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.broadcastStreamDeckState() }
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
        // Channel-point / bit subscriptions are gated on the master toggle too,
        // so re-evaluate them whenever it flips (subscribe on enable, drop the
        // managed reward setup on disable).
        Task { [weak self] in await self?.twitchService?.refreshRedemptionSubscriptions() }
    }

    /// Enables or disables listening-history recording when the toggle changes.
    @objc func listeningHistorySettingChanged(_ notification: Notification) {
        guard let enabled = notification.enabledFlag else { return }
        if enabled {
            historyService?.enable()
        } else {
            // Capture the in-progress play before recording stops. Marks the
            // play consumed so it can't be recorded a second time when the
            // track later changes or playback stops.
            flushCurrentPlayToHistoryOnce()
            historyService?.disable()
        }
    }

    /// Flushes the in-progress play to history at most once per track.
    ///
    /// Wraps `flushCurrentPlayToHistory()` in a consumed flag so a single play
    /// can't be recorded twice (e.g. the History toggle flushing mid-track,
    /// then the track-change handler recording the same play again when the
    /// song ends). The flag resets when a new track starts playing.
    func flushCurrentPlayToHistoryOnce() {
        guard !currentPlayFlushedToHistory else { return }
        flushCurrentPlayToHistory()
        currentPlayFlushedToHistory = true
    }

    /// Clears skip-vote session state when the Twitch connection drops.
    /// EventSub does not replay missed `poll.end` events, so a poll left
    /// "active" across a disconnect would block every future vote session.
    @objc func twitchConnectionStateChanged(_ notification: Notification) {
        // Twitch connect/disconnect flips the Stream Deck health key.
        broadcastStreamDeckState()

        guard notification.isConnectedFlag == false else { return }
        Task { [weak self] in
            await self?.skipVoteManager?.reset()
        }
    }

    /// Shows a notification if a new version is available (Sparkle handles this automatically).
    @objc func handleUpdateStateChanged(_ notification: Notification) {
        guard let update = notification.updateState, update.isUpdateAvailable else { return }
        let version = update.latestVersion

        Log.info("AppDelegate: Update available notification received: v\(version)", category: "Update")
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

    /// Posts the "Twitch session expired" banner via `NotificationService`.
    ///
    /// Never requests notification authorization: this runs from the
    /// unattended boot-path token check, and prompting belongs only to the
    /// primed onboarding / settings buttons. `NotificationService` drops the
    /// banner unless authorization was already granted (`.notDetermined` is
    /// treated like `.denied`); the in-app re-auth banner covers that case.
    private func showTwitchAuthNotification() {
        Task {
            await NotificationService.shared.postTwitchReauthNeeded()
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
                showTwitchAuthNotification()
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
    /// connects. Auto-reconnect is silent. Called only after the token has been
    /// validated against Twitch.
    func autoReconnectTwitchIfPossible(token: String) async {
        guard let service = twitchService else { return }
        guard let clientID = TwitchChatService.resolveClientID(), !clientID.isEmpty else {
            Log.debug("AppDelegate: Skipping Twitch auto-reconnect: no Client ID", category: "Twitch")
            return
        }
        guard let channel = KeychainService.loadTwitchChannelID(), !channel.isEmpty else {
            Log.debug("AppDelegate: Skipping Twitch auto-reconnect: no stored channel name", category: "Twitch")
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
        // A good read ends any ScriptingBridge error streak.
        consecutiveScriptErrorCount = 0

        // Composite identity: title alone conflates distinct songs that share
        // a name (a cover, a live version, two songs called "Home"), silently
        // skipping history recording, the !last update, recents, and the
        // song-change banner on such transitions. Genuine re-emits of the same
        // track carry identical title + artist + album, so pause/resume
        // behavior is unchanged.
        let isSameTrack = currentSong == track
            && currentArtist == artist
            && (currentAlbum ?? "") == album
        if !isSameTrack {
            // The outgoing track's last polled playhead position (`currentElapsed`)
            // is how far it actually played. Hand it to history before we
            // overwrite the now-playing state, unless this play was already
            // flushed (History toggle-off): recording it again would double
            // count the track.
            if let outgoing = currentSong, let outgoingArtist = currentArtist,
               !currentPlayFlushedToHistory {
                historyService?.recordTrackChange(
                    track: outgoing,
                    artist: outgoingArtist,
                    album: currentAlbum ?? "",
                    duration: currentDuration,
                    playedSeconds: currentElapsed
                )
            }
            // The incoming track is a fresh play; it hasn't been flushed yet.
            currentPlayFlushedToHistory = false
            lastSong = currentSong
            lastArtist = currentArtist

            // Votes cast against the outgoing song must not carry over to the
            // incoming one. Ends any open chat-tally vote session without
            // starting the inter-session cooldown.
            Task { [weak self] in
                await self?.skipVoteManager?.trackDidChange()
            }

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

            // Artwork is keyed by track+artist, so only refetch on a genuine
            // track change. On a same-track re-emit (~every 5s) the previous
            // fetch already populated the cache; refetching triggered a
            // redundant full overlay rebroadcast per tick via updateArtworkURL.
            fetchArtworkForWidget(track: track, artist: artist)
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

        if let discordService {
            if isPaused && FeatureFlags.discordClearWhilePaused {
                // User opted to hide the track while paused: clear (or go idle)
                // instead of keeping the paused track on their profile.
                applyDiscordCleared()
            } else {
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
    }

    /// Applies the "no track" Discord state, honoring the idle-status
    /// preference: shows the opt-in idle activity, or clears the profile.
    private func applyDiscordCleared() {
        guard let discordService else { return }
        if FeatureFlags.discordShowIdleStatus {
            Task { await discordService.showIdleStatus() }
        } else {
            Task { await discordService.clearPresence() }
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

        // Debounce ScriptingBridge read errors. A single flaky read mid-track
        // (documented macOS 26 behavior) must not flush a partial play to
        // history (which double-counts the track when it later ends) or blank
        // Discord and the overlay. Only a sustained error streak clears
        // playback; any other status, or a good track read, resets the streak.
        if status == "Script error" {
            consecutiveScriptErrorCount += 1
            if consecutiveScriptErrorCount < scriptErrorStopThreshold {
                Log.debug(
                    "AppDelegate: transient script error (\(consecutiveScriptErrorCount)/\(scriptErrorStopThreshold)), keeping playback snapshot",
                    category: "Music"
                )
                return
            }
        } else {
            consecutiveScriptErrorCount = 0
        }

        // Any of these statuses mean "no track is reliably playing right now".
        // Flush in-progress history and blank the cached snapshot so Discord
        // Rich Presence and the WebSocket overlay don't keep broadcasting a
        // stale song after Music quits, permission is revoked, or SB errors out.
        let shouldClearPlayback = status == "No track playing"
            || status == "Music access denied"
            || status == "Music not running"
            || status == "No track info"
            || status == "Script error"

        if shouldClearPlayback {
            flushCurrentPlayToHistoryOnce()
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
            applyDiscordCleared()
            Task { [weak self] in await self?.websocketServer?.clearNowPlaying() }
        }
    }
}
