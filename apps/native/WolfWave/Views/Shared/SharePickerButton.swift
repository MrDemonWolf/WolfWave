//
//  SharePickerButton.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-01.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI
import AppKit

// MARK: - SharePickerButton

/// AppKit-backed button that presents the macOS share sheet
/// (`NSSharingServicePicker`: Messages, Mail, AirDrop, Notes, etc.).
///
/// `NSSharingServicePicker.show(relativeTo:of:preferredEdge:)` must anchor to a
/// real `NSView`, which a SwiftUI `Button` can't hand back, so this wraps an
/// `NSButton` and anchors the picker to it.
struct SharePickerButton: NSViewRepresentable {

    // MARK: - Properties

    /// Visible button title. Defaults to "Share".
    var title: String = "Share"

    /// SF Symbol shown leading the title.
    var systemImage: String = "square.and.arrow.up"

    /// When `true`, fills the button with the accent color and white label.
    /// Matches SwiftUI's `.borderedProminent` so it can sit beside one.
    var isProminent: Bool = false

    /// Produces the items to share when the button is clicked. Runs on the main
    /// thread. Return `nil` (or an empty array) to suppress the picker. e.g.
    /// when a render step failed and there's nothing to share.
    let makeItems: () -> [Any]?

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .rounded
        button.imagePosition = .imageLeading
        button.target = context.coordinator
        button.action = #selector(Coordinator.share(_:))
        button.setContentHuggingPriority(.required, for: .horizontal)
        applyStyle(to: button)
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        applyStyle(to: nsView)
        context.coordinator.makeItems = makeItems
    }

    /// Applies title, icon, and prominent fill so make/update stay in sync.
    ///
    /// The icon color is baked into the symbol image via `SymbolConfiguration`
    /// rather than `contentTintColor`: a rounded bezel button with an explicit
    /// `bezelColor` ignores `contentTintColor` for its image, which left the
    /// prominent share glyph rendering in the default `labelColor` (dark on the
    /// accent fill, and flipping per light/dark appearance) while the title was
    /// forced white. Baking the color keeps glyph and label in sync.
    private func applyStyle(to button: NSButton) {
        let symbol = NSImage(systemSymbolName: systemImage,
                             accessibilityDescription: title)

        if isProminent {
            // Bake white into the glyph; the accent fill is colored in both
            // appearances, so white reads correctly without flipping.
            button.image = symbol?.withSymbolConfiguration(.init(paletteColors: [.white]))
            button.bezelColor = .controlAccentColor
            button.contentTintColor = .white
            button.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.foregroundColor: NSColor.white])
        } else {
            // Plain template image tints with the button's label color and
            // adapts to light/dark on its own.
            button.image = symbol
            button.bezelColor = nil
            button.contentTintColor = nil
            button.title = title
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(makeItems: makeItems)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        var makeItems: () -> [Any]?

        init(makeItems: @escaping () -> [Any]?) {
            self.makeItems = makeItems
        }

        @objc func share(_ sender: NSButton) {
            guard let items = makeItems(), !items.isEmpty else { return }
            let picker = NSSharingServicePicker(items: items)
            picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }
}
