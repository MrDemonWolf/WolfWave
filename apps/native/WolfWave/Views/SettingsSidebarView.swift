//
//  SettingsSidebarView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-03.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Native macOS settings sidebar: a plain `List(selection:)` of `Label` rows
/// grouped into `Section`s, rendered with `.listStyle(.sidebar)`.
///
/// This is deliberately stock SwiftUI — no custom row backgrounds, hover fills,
/// selection pills, or brand header. The system draws the standard sidebar
/// selection highlight (the rounded accent capsule), supplies the uppercase
/// secondary section headers, tints icons on selection, and handles keyboard
/// arrow navigation and VoiceOver semantics. The result matches Apple's own
/// sidebars (Finder, Notes, the Landmarks sample): the native look, with the
/// `NavigationSplitView` sidebar toggle owned by the title bar (see
/// `apps/native/docs/sidebar-toggle-glitch-research.md`).
///
/// Anything that overrides `listRowBackground` here will suppress the native
/// selection highlight — leave the rows stock.
struct SettingsSidebarView: View {
    // MARK: - Properties

    /// Currently selected section. Bound to the parent `NavigationSplitView`.
    @Binding var selection: SettingsView.SettingsSection

    /// Grouped sidebar layout (optional header + member sections). Supplied by
    /// `SettingsView.sidebarGroups` so the order/headers stay defined in one place.
    let groups: [(title: String?, sections: [SettingsView.SettingsSection])]

    // MARK: - Body

    var body: some View {
        List(selection: $selection) {
            ForEach(groups, id: \.sections) { group in
                // Named groups get the native uppercase/secondary section header
                // from `.sidebar`. The title-less group (General) renders as a
                // plain section so it sits flush at the top with no header gap.
                if let title = group.title {
                    Section(title) { rows(for: group.sections) }
                } else {
                    Section { rows(for: group.sections) }
                }
            }
        }
        .listStyle(.sidebar)
    }

    /// Selectable navigation rows for one group. Each row is a stock `Label`
    /// tagged with its section so `List(selection:)` drives the binding.
    private func rows(for sections: [SettingsView.SettingsSection]) -> some View {
        ForEach(sections) { section in
            SettingsSidebarRow(section: section)
                .tag(section)
        }
    }
}

// MARK: - Sidebar Row

/// One navigation row: a native `Label` pairing the section title with an icon.
/// SF Symbol sections use the symbol directly; brand sections (Twitch / Discord)
/// supply a template image so the system tints it like a symbol — monochrome at
/// rest, white on the selection capsule.
private struct SettingsSidebarRow: View {
    let section: SettingsView.SettingsSection

    var body: some View {
        Label {
            Text(section.rawValue)
        } icon: {
            if let brandIcon = section.brandIcon {
                Image(brandIcon)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: section.systemIcon)
            }
        }
        .accessibilityIdentifier(section.rawValue.replacingOccurrences(of: " ", with: "-").lowercased())
    }
}
