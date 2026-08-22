//
//  ComponentGallery+Status.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

#if DEBUG
import SwiftUI

// MARK: - Status & headers

extension DebugComponentGalleryCard {

    /// Status & headers: `StatusChip`, `SectionHeaderWithStatus`, `CardEyebrowHeader`,
    /// `StreamerModeBadge`, the `ViewModifiers` ramp, `TwitchGlitchShape`.
    @ViewBuilder var statusSection: some View {
        GalleryEntry(typeName: "StatusChip", width: GalleryWidth.wide) {
            // The four previews, plus the two remaining `StateGlyph` members.
            HStack(spacing: DSSpace.s2) {
                StatusChip(text: "Live", color: DSColor.success, systemImage: StatusChip.StateGlyph.on)
                StatusChip(text: "Off", color: DSColor.neutral, systemImage: StatusChip.StateGlyph.off)
                StatusChip(text: "Error", color: DSColor.error, systemImage: StatusChip.StateGlyph.error)
                StatusChip(text: "Paused", color: DSColor.warning, systemImage: StatusChip.StateGlyph.paused)
                StatusChip(text: "Starting", color: DSColor.info, systemImage: StatusChip.StateGlyph.starting)
                // Dot fallback: a category tag, not a status, so a raw color is allowed here.
                StatusChip(text: "Twitch", color: .purple)
            }
        }

        GalleryEntry(typeName: "SectionHeaderWithStatus", width: GalleryWidth.wide) {
            VStack(alignment: .leading, spacing: DSSpace.s6) {
                SectionHeaderWithStatus(
                    title: "Discord Status",
                    subtitle: "Show your music on your Discord profile.",
                    statusText: "Connected",
                    statusColor: DSColor.success
                )
                SectionHeaderWithStatus(
                    title: "About WolfWave",
                    subtitle: "Native macOS menu bar app for Apple Music streamers."
                )
                SectionHeaderWithStatus(
                    title: "Section prominence",
                    subtitle: "The in-pane variant, with a glyph.",
                    prominence: .section,
                    statusText: "Paused",
                    statusColor: DSColor.warning,
                    statusSymbol: StatusChip.StateGlyph.paused
                )
            }
        }

        GalleryEntry(typeName: "CardEyebrowHeader", width: GalleryWidth.narrow) {
            VStack(alignment: .leading, spacing: DSSpace.s4) {
                CardEyebrowHeader("Top artists", systemImage: "music.mic")
                CardEyebrowHeader("Listening time", systemImage: "clock")
            }
        }

        GalleryEntry(typeName: "StreamerModeBadge") {
            HStack {
                Text("Auth Token")
                    .font(.system(size: DSFont.Size.base, weight: .medium))
                StreamerModeBadge()
                Spacer()
            }
        }

        GalleryEntry(typeName: "ViewModifiers", width: GalleryWidth.wide) {
            VStack(alignment: .leading, spacing: DSSpace.s5) {
                // The type ramp, top to bottom: 22 → 17 → 11 headings + body + caption.
                Text("Pane Title (H1)")
                    .paneTitle()
                Text("Section Header (H2)")
                    .sectionHeader()
                Text("In-card eyebrow (H3)")
                    .sectionEyebrow()

                VStack(alignment: .leading, spacing: DSSpace.s2) {
                    Text("Card with .cardStyle()")
                        .sectionHeader()
                    Text("Opaque surface, internal padding, rounded corners.")
                        .fieldSubtitle()
                    Text("Caption / footnote level.")
                        .captionText()
                }
                .cardStyle()

                VStack(alignment: .leading, spacing: DSSpace.s2) {
                    Text("Shell with .subtleCardShell()")
                        .fieldSubtitle()
                }
                .padding(DSSpace.s4)
                .subtleCardShell()

                HStack(spacing: DSSpace.s4) {
                    Text("Loading row with .skeleton(true)")
                        .fieldSubtitle()
                        .skeleton(true)
                    Text("and without")
                        .fieldSubtitle()
                        .skeleton(false)
                }

                Text("Hover for pointer cursor")
                    .font(.system(size: DSFont.Size.body))
                    .padding(DSSpace.s3)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: DSRadius.sm))
                    .pointerCursor()
            }
        }

        GalleryEntry(typeName: "TwitchGlitchShape", note: "Shape, eoFill") {
            HStack(spacing: DSSpace.s8) {
                TwitchGlitchShape()
                    .fill(AppConstants.Brand.twitch, style: FillStyle(eoFill: true))
                    .frame(width: DSSpace.s6, height: DSSpace.s6)
                TwitchGlitchShape()
                    .fill(AppConstants.Brand.twitch, style: FillStyle(eoFill: true))
                    .frame(width: DSSpace.s10, height: DSSpace.s10)
                TwitchGlitchShape()
                    .fill(AppConstants.Brand.twitch, style: FillStyle(eoFill: true))
                    .frame(width: DSSpace.s10 * 2, height: DSSpace.s10 * 2)
            }
        }
    }
}
#endif
