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
/// (`NSSharingServicePicker` — Messages, Mail, AirDrop, Notes, etc.).
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

    /// Produces the items to share when the button is clicked. Runs on the main
    /// thread. Return `nil` (or an empty array) to suppress the picker — e.g.
    /// when a render step failed and there's nothing to share.
    let makeItems: () -> [Any]?

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .rounded
        button.title = title
        button.image = NSImage(systemSymbolName: systemImage,
                               accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.target = context.coordinator
        button.action = #selector(Coordinator.share(_:))
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        nsView.title = title
        nsView.image = NSImage(systemSymbolName: systemImage,
                               accessibilityDescription: title)
        context.coordinator.makeItems = makeItems
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
