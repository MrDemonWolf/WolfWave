//
//  ComponentGallery+Buttons.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

#if DEBUG
import SwiftUI

// MARK: - Buttons

extension DebugComponentGalleryCard {

    /// Buttons: `DSIconButton`, `CopyButton`, `OpenInBrowserButton`,
    /// `DestructiveButton`, `AsyncActionButton`, `SharePickerButton`, `ActionGrid`.
    @ViewBuilder var buttonsSection: some View {
        GalleryEntry(typeName: "DSIconButton") {
            // The CopyButton neighbour is part of the component's own preview:
            // matching its frame is the reason DSIconButton exists.
            HStack(spacing: DSSpace.s2) {
                DSIconButton(systemImage: "eye", action: {}, accessibilityLabel: "Reveal")
                DSIconButton(systemImage: "arrow.clockwise", action: {}, accessibilityLabel: "Refresh")
                DSIconButton(systemImage: "trash", action: {}, isDisabled: true, accessibilityLabel: "Disabled")
                CopyButton(text: "preview", label: "Copy", copiedLabel: "Copied", accessibilityLabel: "Copy")
            }
        }

        GalleryEntry(typeName: "CopyButton") {
            HStack(spacing: DSSpace.s4) {
                CopyButton(text: "ws://localhost:9090", accessibilityLabel: "Copy URL")
                CopyButton(
                    text: "http://localhost:9091/widget",
                    label: "Copy Link",
                    copiedLabel: "Copied",
                    accessibilityLabel: "Copy widget URL"
                )
                CopyButton(
                    text: "brew upgrade wolfwave",
                    buttonStyle: .borderless,
                    accessibilityLabel: "Copy brew command"
                )
                CopyButton(text: "disabled", isDisabled: true, accessibilityLabel: "Copy (disabled)")
            }
        }

        GalleryEntry(typeName: "OpenInBrowserButton", note: "opens the real browser") {
            HStack(spacing: DSSpace.s4) {
                OpenInBrowserButton(urlString: "http://localhost:8766", accessibilityLabel: "Open widget in browser")
                OpenInBrowserButton(
                    urlString: "http://192.168.1.20:8766",
                    isDisabled: true,
                    accessibilityLabel: "Open network widget in browser"
                )
            }
        }

        GalleryEntry(typeName: "DestructiveButton") {
            VStack(spacing: DSSpace.s4) {
                DestructiveButton(title: "Reset All Settings to Defaults", systemImage: "trash") {}
                DestructiveButton(title: "Clear Logs", systemImage: "trash") {}
                DestructiveButton(title: "Delete Account") {}
            }
        }

        GalleryEntry(typeName: "AsyncActionButton", width: GalleryWidth.narrow, note: "real 1-2s fake actions") {
            VStack(alignment: .leading, spacing: DSSpace.s4) {
                AsyncActionButton(title: "Join Channel", systemImage: "checkmark.circle.fill") {
                    try await Task.sleep(for: .seconds(2))
                }
                AsyncActionButton(title: "Fetch link", style: .borderedProminent) {
                    try await Task.sleep(for: .seconds(2))
                }
                AsyncActionButton(title: "Clear Queue", role: .destructive) {
                    try await Task.sleep(for: .seconds(1))
                }
                AsyncActionButton(title: "Always fails") {
                    try await Task.sleep(for: .seconds(1))
                    throw CocoaError(.fileNoSuchFile)
                }
                AsyncActionButton(title: "Blocked", isDisabled: true) {}
            }
        }

        GalleryEntry(typeName: "SharePickerButton", note: "opens the macOS share sheet") {
            HStack(spacing: DSSpace.s4) {
                SharePickerButton(makeItems: { ["WolfWave"] })
                SharePickerButton(
                    title: "Share card",
                    systemImage: "square.and.arrow.up",
                    isProminent: true,
                    makeItems: { ["WolfWave"] }
                )
            }
        }

        GalleryEntry(typeName: "ActionGrid") {
            ActionGrid(columns: 2) {
                GridRow {
                    ActionGridButton(title: "Check for Updates", systemImage: "arrow.down.circle", action: {})
                    ActionGridButton(title: "Release Notes", systemImage: "list.bullet.rectangle", action: {})
                }
                GridRow {
                    ActionGridButton(title: "Website", systemImage: "globe", action: {})
                    ActionGridButton(title: "Send Feedback", systemImage: "envelope", action: {})
                }
                GridRow {
                    ActionGridButton(title: "Sponsor on GitHub", systemImage: "heart.fill", action: {})
                        .gridCellColumns(2)
                }
            }
        }
    }
}
#endif
