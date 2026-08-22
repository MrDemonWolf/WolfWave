//
//  ComponentGallery+Cards.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

#if DEBUG
import SwiftUI

// MARK: - Cards & media

extension DebugComponentGalleryCard {

    /// Cards & media: `NowPlayingHeroCard`, `AlbumArtView`, `IntegrationDashboardView`,
    /// `QRCodeImage`, `ResponsiveRow`.
    @ViewBuilder var cardsSection: some View {
        GalleryEntry(typeName: "NowPlayingHeroCard", width: GalleryWidth.full) {
            // Invented track, wolf-species "artist": never real music metadata.
            VStack(spacing: DSSpace.s4) {
                NowPlayingHeroCard(
                    track: "Moonlit Howl",
                    artist: "Arctic Wolf",
                    album: "Tundra Sessions",
                    elapsed: 72,
                    duration: 218
                )
                NowPlayingHeroCard(
                    track: "Moonlit Howl",
                    artist: "Arctic Wolf",
                    album: "Tundra Sessions",
                    elapsed: 72,
                    duration: 218,
                    isPaused: true
                )
                NowPlayingHeroCard(track: nil, artist: nil, album: nil)
                NowPlayingHeroCard(track: nil, artist: nil, album: nil, trackingEnabled: false)
                NowPlayingHeroCard(track: nil, artist: nil, album: nil, musicNotRunning: true, onOpenMusic: {})
            }
        }

        GalleryEntry(typeName: "AlbumArtView", note: "branded fallback") {
            HStack(spacing: DSSpace.s4) {
                AlbumArtView(size: Metrics.artLarge)
                AlbumArtView(size: Metrics.artMedium)
                AlbumArtView(size: Metrics.artSmall)
            }
        }

        GalleryEntry(typeName: "IntegrationDashboardView", width: GalleryWidth.full) {
            VStack(spacing: DSSpace.s4) {
                IntegrationDashboardView(
                    twitchConnected: true,
                    twitchChannel: "nightowlstream",
                    twitchViewerCount: 12,
                    discordConnected: true,
                    widgetRunning: true,
                    widgetURL: "http://localhost:8766",
                    remoteSendingEnabled: false
                )
                IntegrationDashboardView(
                    twitchConnected: false,
                    twitchChannel: nil,
                    twitchViewerCount: nil,
                    discordConnected: false,
                    widgetRunning: false,
                    widgetURL: nil,
                    remoteSendingEnabled: false,
                    permissionPaused: true
                )
            }
        }

        GalleryEntry(typeName: "QRCodeImage", note: "white modules, needs a dark backing") {
            QRCodeImage(string: "https://mrdemonwolf.github.io/wolfwave", size: Metrics.qrSize)
                .padding()
                .background(Color.black)
        }

        GalleryEntry(typeName: "ResponsiveRow", width: GalleryWidth.full, note: "wide vs narrow container") {
            VStack(alignment: .leading, spacing: DSSpace.s4) {
                responsiveRowSample
                responsiveRowSample
                    .frame(maxWidth: GalleryWidth.narrow)
            }
        }
    }

    private var responsiveRowSample: some View {
        ResponsiveRow {
            RoundedRectangle(cornerRadius: DSRadius.lg2)
                .fill(DSColor.info.opacity(0.2))
                .frame(height: Metrics.rowSample)
                .overlay(Text("Left"))
        } right: {
            RoundedRectangle(cornerRadius: DSRadius.lg2)
                .fill(DSColor.success.opacity(0.2))
                .frame(height: Metrics.rowSample)
                .overlay(Text("Right"))
        }
    }

    /// Sample sizes lifted from the components' own previews. Gallery layout, not tokens.
    private enum Metrics {
        static let artLarge: CGFloat = 92
        static let artMedium: CGFloat = 64
        static let artSmall: CGFloat = 36
        static let qrSize: CGFloat = 120
        static let rowSample: CGFloat = 80
    }
}
#endif
