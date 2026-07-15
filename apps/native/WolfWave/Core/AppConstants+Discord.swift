//
//  AppConstants+Discord.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-07-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

extension AppConstants {
    /// Discord Rich Presence constants.
    nonisolated enum Discord {
        /// Settings section identifier for Discord configuration
        static let settingsSection = "discordPresence"

        /// IPC socket filename prefix (append 0-9 to find active socket)
        static let ipcSocketPrefix = "discord-ipc-"

        /// Number of IPC socket slots to try (0 through 9)
        static let ipcSocketSlots = 10

        /// Discord RPC protocol version
        static let rpcVersion = 1

        /// Activity type for "Listening" (shows "Listening to …" on profile)
        static let listeningActivityType = 2

        /// Title line (line 1) for the opt-in idle activity.
        static let idleDetails = "Apple Music is idle"

        /// Sub-line (line 2) for the opt-in idle activity.
        static let idleState = "Nothing playing right now"

        // MARK: Rich Presence art-asset keys
        //
        // Each value is a key that MUST be uploaded to the Discord developer
        // portal (Rich Presence > Art Assets) under this exact name, otherwise
        // Discord renders no image. Source PNGs live in `discord-assets/`.

        /// WolfWave logo. Large image on the idle activity so idle reads as a
        /// WolfWave state, visually distinct from active Apple Music playback.
        static let artAssetWolfWave = "wolfwave"

        /// Apple Music mark. Large image fallback + small source badge.
        static let artAssetAppleMusic = "apple_music"

        /// Pause badge swapped onto `small_image` while playback is paused.
        static let artAssetPause = "pause"

        /// Small-badge tooltip (`small_text`) shown on the idle activity.
        static let idleSmallText = "Apple Music"

        /// Reconnect base delay in seconds (doubled on each consecutive failure)
        static let reconnectBaseDelay: TimeInterval = 5.0

        /// Maximum reconnect delay cap in seconds
        static let reconnectMaxDelay: TimeInterval = 60.0

        /// Interval in seconds for polling Discord availability when not connected
        static let availabilityPollInterval: TimeInterval = 15.0

        /// Send/receive timeout (seconds) on the IPC socket. A stalled Discord
        /// peer can't block the service's actor executor longer than this: a
        /// timed-out blocking read/write fails fast into reconnect handling.
        static let socketTimeoutSeconds = 5

        /// Upper bound (exclusive) on an inbound IPC frame body, in bytes. A frame
        /// claiming a length at or above this is treated as malformed and dropped
        /// rather than allocated, bounding a hostile or garbled peer.
        static let maxIPCFrameBytes: UInt32 = 65536

        /// Default label for the first presence button (links to Apple Music track page).
        static let defaultButton1Label = "Listen on Apple Music"

        /// Default label for the second presence button (links to song.link cross-service page).
        static let defaultButton2Label = "Find on Other Services"

        /// Discord hard cap on button label length (characters).
        static let buttonLabelMaxLength = 32

        /// Discord hard cap on number of buttons per activity.
        static let maxButtons = 2

        /// Discord hard cap on activity `details` / `state` text length (characters).
        static let activityTextMaxLength = 128

        /// Separator between the artist and the playlist on the activity state line.
        static let playlistSeparator = " · "

        /// Generic state-line label shown when the playlist name is hidden.
        static let playlistAnonymousLabel = "From a playlist"

        /// Generic small-icon tooltip shown when the playlist name is hidden.
        static let playlistAnonymousTooltip = "Playing from a playlist"

        /// Prefix for the small-icon tooltip when the playlist name is shown.
        static let playlistTooltipPrefix = "Playlist"

        /// Playlist container names that are too generic to surface as a playlist.
        static let genericPlaylistNames: Set<String> = ["library", "music", "apple music"]
    }
}
