//
//  StreamDeckCommand.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-07-18.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

// MARK: - StreamDeckAction

/// An action a Stream Deck key can trigger over the control WebSocket.
///
/// Raw values are the wire tokens the plugin sends in a command envelope, so
/// renaming a case is a protocol change (bump `StreamDeckControl.protocolVersion`).
nonisolated enum StreamDeckAction: String, Codable, CaseIterable, Sendable {
    case playPause = "play_pause"
    case skip
    case holdQueue = "hold_queue"
    case resumeQueue = "resume_queue"
    case approveNext = "approve_next"
    case clearQueue = "clear_queue"
    case blockCurrent = "block_current"
    case overlayToggle = "overlay_toggle"
    case discordToggle = "discord_toggle"
    case musicSyncToggle = "music_sync_toggle"
    case cycleTheme = "cycle_theme"
}

// MARK: - StreamDeckCommand

/// A decoded, validated inbound command ready to run.
nonisolated struct StreamDeckCommand: Sendable, Equatable {
    let action: StreamDeckAction
    /// Optional string args from the envelope (unused by the v1 actions; carried
    /// so a future action can take a parameter without a protocol bump).
    let args: [String: String]
}

// MARK: - CommandAck

/// The reply sent back on the originating connection after a command is handled.
nonisolated struct CommandAck: Sendable, Equatable {
    let action: String
    let ok: Bool
    let error: String?

    /// JSON object form for `WebSocketServerService.sendJSON`.
    var jsonObject: [String: Any] {
        var obj: [String: Any] = ["type": "ack", "action": action, "ok": ok]
        if let error { obj["error"] = error }
        return obj
    }

    static func success(_ action: StreamDeckAction) -> CommandAck {
        CommandAck(action: action.rawValue, ok: true, error: nil)
    }

    static func failure(_ action: String, _ error: String) -> CommandAck {
        CommandAck(action: action, ok: false, error: error)
    }
}

// MARK: - StreamDeckControl

/// Pure decode of inbound control frames. No I/O, no state, so it is trivially
/// unit-testable and safe to call from the nonisolated Network.framework
/// receive callback.
nonisolated enum StreamDeckControl {

    /// Command protocol version. Bump on any breaking envelope change so an
    /// out-of-date plugin can detect the mismatch (ack `error:"protocol"`) and
    /// prompt for an update instead of silently misbehaving.
    static let protocolVersion = 1

    /// Outcome of decoding one inbound WebSocket text frame.
    enum InboundFrame: Equatable {
        /// A valid command to run; reply with the handler's ack.
        case command(StreamDeckCommand)
        /// A command frame we understood but refused; send this ack, don't run.
        case reject(CommandAck)
        /// Not a command frame (or unparseable) — do nothing, don't ack.
        case ignore
    }

    /// Decodes a raw text frame.
    ///
    /// Gates in order so an out-of-date plugin gets the clearest signal:
    /// 1. `type == "command"` (anything else → `.ignore`, no ack noise)
    /// 2. `protocol == protocolVersion` (mismatch → `.reject` `"protocol"`)
    /// 3. a known `action` (unknown → `.reject` `"unknown_action"`)
    static func parse(_ text: String) -> InboundFrame {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["type"] as? String) == "command" else {
            return .ignore
        }

        let actionToken = (obj["action"] as? String) ?? ""

        guard (obj["protocol"] as? Int) == protocolVersion else {
            return .reject(.failure(actionToken, "protocol"))
        }
        guard let action = StreamDeckAction(rawValue: actionToken) else {
            return .reject(.failure(actionToken, "unknown_action"))
        }

        let args = (obj["args"] as? [String: String]) ?? [:]
        return .command(StreamDeckCommand(action: action, args: args))
    }
}
