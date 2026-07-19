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
            let newValue = !FeatureFlags.websocketEnabled
            Preferences.setWebSocketEnabled(newValue)
            // Keep widgetHTTPEnabled in sync, matching the tray toggleWebSocket
            // path, so the Stream Deck overlay key brings the widget HTTP server
            // up/down alongside the WebSocket channel (OBS loads the widget page
            // over HTTP; without this the overlay stays blank).
            Preferences.setWidgetHTTPEnabled(newValue)
            NotificationCenter.default.postWebSocketServerChanged(
                enabled: newValue,
                widgetHTTPEnabled: newValue
            )
            await websocketServer?.setWidgetHTTPEnabled(newValue)
            return .success(action)

        case .discordToggle:
            let newValue = !FeatureFlags.discordEnabled
            UserDefaults.standard.set(newValue, forKey: AppConstants.UserDefaults.discordPresenceEnabled)
            NotificationCenter.default.postEnabled(.discordPresenceChanged, enabled: newValue)
            return .success(action)

        case .musicSyncToggle:
            let newValue = !FeatureFlags.trackingEnabled
            UserDefaults.standard.set(newValue, forKey: AppConstants.UserDefaults.trackingEnabled)
            NotificationCenter.default.postEnabled(.trackingSettingChanged, enabled: newValue)
            return .success(action)

        case .cycleTheme:
            cycleWidgetTheme()
            await websocketServer?.broadcastWidgetConfig()
            return .success(action)
        }
    }

    /// Advances the widget theme to the next in `AppConstants.Widget.themes`,
    /// wrapping around. Persists so the settings picker stays in sync.
    private func cycleWidgetTheme() {
        let themes = AppConstants.Widget.themes
        guard !themes.isEmpty else { return }
        let key = AppConstants.UserDefaults.widgetTheme
        let current = UserDefaults.standard.string(forKey: key) ?? themes[0]
        let index = themes.firstIndex(of: current) ?? 0
        UserDefaults.standard.set(themes[(index + 1) % themes.count], forKey: key)
    }

    /// Gathers current queue counts + connection health and pushes both Stream
    /// Deck broadcasts. Cheap; safe to call from any queue/connection change so a
    /// counter or status key reflects app state without polling.
    func broadcastStreamDeckState() {
        let count = songRequestService?.queue.count ?? 0
        let pending = songRequestService?.pendingApprovalCount ?? 0
        let music = currentSong != nil
        let twitch = twitchService?.currentlyConnected ?? false
        // ponytail: discord health = is-enabled proxy; wire the live IPC
        // connection state in Phase B when a key actually consumes it.
        let discord = FeatureFlags.discordEnabled
        let overlay = websocketServer?.state == .listening
        Task { [weak self] in
            await self?.websocketServer?.broadcastQueueState(count: count, pending: pending)
            await self?.websocketServer?.broadcastHealth(
                music: music, twitch: twitch, discord: discord, overlay: overlay)
        }
    }
}
