//
//  AppDelegate+StreamDeck.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-07-18.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit
import Foundation

// MARK: - Stream Deck Control

extension AppDelegate {

    /// Runs one inbound Stream Deck command against the live services and returns
    /// the ack to send back. Runs on the MainActor (every service the actions
    /// touch is MainActor-isolated). Wired to the WebSocket server's command
    /// handler in `setupWebSocketServer`. On success, re-broadcasts the queue +
    /// health snapshot so the sending key updates immediately.
    func handleStreamDeckCommand(_ command: StreamDeckCommand) async -> CommandAck {
        // The capability gate, checked before anything runs. Deliberately here in
        // the router rather than in the transport: the server keeps serving
        // overlays either way, so turning Stream Deck off has to disarm the
        // commands without touching the socket that OBS is reading from.
        //
        // A refusal still acks, with a reason the plugin can render. Dropping the
        // frame would leave a key spinning with no explanation, which reads as a
        // broken connection rather than a setting the user chose.
        guard FeatureFlags.streamDeckControlEnabled else {
            Log.debug(
                "StreamDeck: refused \(command.action.rawValue), control is turned off",
                category: .websocket
            )
            return .failure(command.action.rawValue, "disabled")
        }

        let ack = await performStreamDeckAction(command)
        if ack.ok { broadcastStreamDeckState() }
        return ack
    }

    /// Maps each action to an existing service seam. Trivial wiring; the
    /// non-trivial parse/validation lives in ``StreamDeckControl``.
    private func performStreamDeckAction(_ command: StreamDeckCommand) async -> CommandAck {
        let action = command.action
        switch action {
        case .playPause:
            guard let controller = songRequestService?.musicController else {
                return .failure(action.rawValue, "unavailable")
            }
            do { try await controller.playPause() } catch { return .failure(action.rawValue, "music") }
            return .success(action)

        case .skip:
            guard let controller = songRequestService?.musicController else {
                return .failure(action.rawValue, "unavailable")
            }
            do { try await controller.skipToNext() } catch { return .failure(action.rawValue, "music") }
            return .success(action)

        case .holdQueue:
            await songRequestService?.setHold(true)
            return .success(action)

        case .resumeQueue:
            await songRequestService?.setHold(false)
            return .success(action)

        case .approveNext:
            guard let service = songRequestService, let next = service.queue.pending.first else {
                return .failure(action.rawValue, "empty")
            }
            _ = await service.approve(id: next.id)
            return .success(action)

        case .clearQueue:
            songRequestService?.queue.clear()
            return .success(action)

        case .blockCurrent:
            guard let service = songRequestService, let title = currentSong, !title.isEmpty else {
                return .failure(action.rawValue, "empty")
            }
            await service.blocklist.add(BlocklistItem(value: title, type: .song))
            return .success(action)

        case .overlayToggle:
            // Hide/show playback cards without stopping the authenticated socket
            // that carries this command and its acknowledgement. The tray setting
            // remains the explicit control for shutting the server down entirely.
            guard let websocketServer else {
                return .failure(action.rawValue, "unavailable")
            }
            _ = await websocketServer.toggleOverlayVisibility()
            return .success(action)

        case .announceSong:
            // Same seam as the tray's "Share to Twitch": the message text is
            // built once in `getCurrentSongInfo()` so a key and the menu item
            // can never post differently-worded now-playing lines.
            guard let service = twitchService, service.currentlyConnected else {
                return .failure(action.rawValue, "twitch")
            }
            let message = getCurrentSongInfo()
            guard !message.isEmpty else { return .failure(action.rawValue, "empty") }
            await service.sendMessage(message)
            return .success(action)

        case .rejectCurrent:
            guard let service = songRequestService else {
                return .failure(action.rawValue, "unavailable")
            }
            guard await service.rejectCurrent() != nil else {
                return .failure(action.rawValue, "empty")
            }
            return .success(action)

        case .blockRequester:
            // Blocks the person who requested what is playing, not whoever
            // spoke last, so a busy chat cannot shift the target between the
            // streamer deciding and the key landing.
            guard let service = songRequestService,
                  let current = service.queue.nowPlaying else {
                return .failure(action.rawValue, "empty")
            }
            await service.blocklist.add(
                BlocklistItem(value: current.requesterUsername, type: .requester)
            )
            return .success(action)

        case .cycleAudience:
            guard let service = songRequestService else {
                return .failure(action.rawValue, "unavailable")
            }
            let next = service.chatAudience.next
            DefaultsStore.store.set(
                next.rawValue,
                forKey: AppConstants.UserDefaults.songRequestChatAudience
            )
            return .success(action)
        }
    }

    /// Gathers current queue counts + connection health and pushes the Stream
    /// Deck broadcasts plus the overlay's upcoming-queue ticker. Cheap; safe to
    /// call from any queue/connection change so a counter/status key or the
    /// overlay ticker reflects app state without polling.
    func broadcastStreamDeckState() {
        let count = songRequestService?.queue.count ?? 0
        let pending = songRequestService?.pendingApprovalCount ?? 0
        let held = songRequestService?.isHoldEnabled ?? false
        let audience = (songRequestService?.chatAudience ?? .everyone).rawValue
        let upcoming = (songRequestService?.queue.upcoming() ?? []).map {
            WebSocketServerService.QueueUpcomingItem(title: $0.title, requesterUsername: $0.requesterUsername)
        }
        let music = currentSong != nil
        let twitch = twitchService?.currentlyConnected ?? false
        // Real IPC state, not the preference. "off" means the streamer turned
        // it off; "disconnected"/"connecting" mean it is on but not working.
        let discordEnabled = FeatureFlags.discordEnabled
        let discordConnection = discordService?.stateSnapshot ?? .disconnected
        let discordState = discordEnabled ? discordConnection.rawValue : "off"
        let discord = discordEnabled && discordConnection == .connected
        let overlay = websocketServer?.state == .listening
            && websocketServer?.overlayVisible == true
        Task { [weak self] in
            await self?.websocketServer?.broadcastQueueState(
                count: count, pending: pending, held: held, audience: audience)
            await self?.websocketServer?.broadcastQueueUpcoming(items: upcoming)
            await self?.websocketServer?.broadcastHealth(
                music: music, twitch: twitch, discord: discord,
                discordState: discordState, overlay: overlay)
        }
    }
}
