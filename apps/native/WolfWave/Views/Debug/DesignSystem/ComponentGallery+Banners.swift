//
//  ComponentGallery+Banners.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

#if DEBUG
import SwiftUI

// MARK: - Banners & callouts

extension DebugComponentGalleryCard {

    /// Banners & callouts: `CalloutBanner`, `ErrorCallout`, `MusicPermissionBanner`,
    /// `TwitchConnectionNotice`, `UpdateBannerView`.
    @ViewBuilder var bannersSection: some View {
        GalleryEntry(typeName: "CalloutBanner", width: GalleryWidth.wide) {
            VStack(spacing: DSSpace.s4) {
                CalloutBanner(
                    "Viewers type **!sr song name** in chat and WolfWave adds it to the queue.",
                    title: "How it works",
                    style: .info
                )
                CalloutBanner("Updates are managed by Homebrew. Run brew upgrade to update.", style: .info)
                CalloutBanner("Diagnostics build. Sparkle points at the bundled dev-appcast.", style: .warning)
                CalloutBanner("You're on the latest version.", style: .success)
                CalloutBanner(
                    "These tools mutate live state. Use at your own risk.",
                    style: .warning,
                    strokeVisible: true
                )
                CalloutBanner("Deleting the queue cannot be undone.", style: .error)
                CalloutBanner("Nothing is uploaded. Everything stays on this Mac.", style: .neutral)
            }
        }

        GalleryEntry(typeName: "ErrorCallout", width: GalleryWidth.wide, note: "actions are no-ops here") {
            VStack(alignment: .leading, spacing: DSSpace.s6) {
                ErrorCallout(error: UserFacingError(
                    id: "twitch.signInExpired",
                    title: "Twitch sign-in expired",
                    cause: "Chat commands stopped working.",
                    fix: "Reconnect and WolfWave picks up where it left off.",
                    severity: .warning,
                    actions: [.reconnectTwitch]
                ))
                ErrorCallout(error: UserFacingError(
                    id: "twitch.rateLimited",
                    title: "Your sign-in is fine, we're being rate limited",
                    cause: "Twitch is throttling requests.",
                    fix: "Try again in **30 seconds**.",
                    severity: .warning,
                    actions: [.retryAfter(seconds: 30)]
                ))
                ErrorCallout(error: UserFacingError(
                    id: "settings.resetAborted",
                    title: "Reset stopped partway",
                    cause: "Your saved Twitch sign-in couldn't be removed, so **nothing was erased**.",
                    fix: "Try again, or send a bug report if it keeps failing.",
                    severity: .error,
                    actions: [.retry, .reportBug]
                ))
                ErrorCallout(error: UserFacingError(
                    id: "music.automationDenied",
                    title: "Let WolfWave read what's playing",
                    cause: "WolfWave only reads the current track. It never plays, pauses, or edits your library.",
                    severity: .warning,
                    actions: [.openAutomationSettings, .openDocs(anchor: "music-permission")]
                ))
            }
        }

        GalleryEntry(typeName: "MusicPermissionBanner", width: GalleryWidth.wide) {
            // The default closure opens System Settings; the gallery passes a no-op.
            MusicPermissionBanner(
                message: """
                    WolfWave can't read the currently playing track. \
                    Enable Apple Music automation in System Settings → Privacy & Security → Automation.
                    """,
                onOpenSettings: {}
            )
        }

        GalleryEntry(typeName: "TwitchConnectionNotice", width: GalleryWidth.wide, note: ".ready renders nothing") {
            VStack(spacing: DSSpace.s4) {
                TwitchConnectionNotice(
                    isConnected: false,
                    reauthNeeded: true,
                    expiredMessage: "Your Twitch sign-in expired. Reconnect to keep song requests working.",
                    disconnectedMessage: "Connect with Twitch to enable song requests."
                )
                TwitchConnectionNotice(
                    isConnected: false,
                    reauthNeeded: false,
                    expiredMessage: "Your Twitch sign-in expired. Reconnect to keep song requests working.",
                    disconnectedMessage: "Connect with Twitch to enable song requests."
                )
                TwitchConnectionNotice(
                    isConnected: true,
                    reauthNeeded: false,
                    expiredMessage: "Your Twitch sign-in expired. Reconnect to keep song requests working.",
                    disconnectedMessage: "Connect with Twitch to enable song requests."
                )
            }
        }

        GalleryEntry(
            typeName: "UpdateBannerView",
            width: GalleryWidth.full,
            note: "appears after Simulate Update Available in UI Previews"
        ) {
            // Renders only on the app-wide update notification; the existing
            // trigger in `DebugUIPreviewsCard` posts it, so this instance lights
            // up alongside the real banner.
            UpdateBannerView().listening()
        }
    }
}
#endif
