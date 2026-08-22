//
//  ComponentGallery+Chrome.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

#if DEBUG
import SwiftUI

extension DebugComponentGalleryCard {

    /// Chrome: `WhatsNewView`, `SettingsNavRail`.
    @ViewBuilder var chromeSection: some View {
        GalleryEntry(
            typeName: "WhatsNewView",
            width: GalleryWidth.full,
            note: "static; Get Started would dismiss the window"
        ) {
            // Its "Get Started" calls `dismiss`, which in a Settings window can
            // close the window, so hit testing is off. Use the trigger in UI
            // Previews for the live sheet.
            WhatsNewView()
                .frame(width: DSDimension.WhatsNew.windowWidth, height: DSDimension.WhatsNew.windowHeight)
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .allowsHitTesting(false)
        }

        GalleryEntry(typeName: "SettingsNavRail", width: GalleryWidth.wide, note: "hosts this pane") {
            Text("""
                The jump-nav rail on the left of this pane is the live instance. \
                It owns its own scroll view, so it is not nested here.
                """)
                .fieldSubtitle()
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
