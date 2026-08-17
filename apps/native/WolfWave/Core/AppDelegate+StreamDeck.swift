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
        let upcoming = (songRequestService?.queue.upcoming() ?? []).map {
            WebSocketServerService.QueueUpcomingItem(title: $0.title, requesterUsername: $0.requesterUsername)
        }
        let music = currentSong != nil
        let twitch = twitchService?.currentlyConnected ?? false
        // ponytail: discord health = is-enabled proxy; wire the live IPC
        // connection state in Phase B when a key actually consumes it.
        let discord = FeatureFlags.discordEnabled
        let overlay = websocketServer?.state == .listening
            && websocketServer?.overlayVisible == true
        Task { [weak self] in
            await self?.websocketServer?.broadcastQueueState(count: count, pending: pending, held: held)
            await self?.websocketServer?.broadcastQueueUpcoming(items: upcoming)
            await self?.websocketServer?.broadcastHealth(
                music: music, twitch: twitch, discord: discord, overlay: overlay)
        }
    }
}
