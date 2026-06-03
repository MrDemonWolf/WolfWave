//
//  SettingsSidebarView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-03.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// VoiceInk-style settings sidebar: a brand header on top, grouped navigation
/// rows with circular icon chips, and a solid accent-color selection pill.
///
/// Rendered inside `NavigationSplitView`'s sidebar column (see `SettingsView`).
/// Selection stays a native `List(selection:)` so keyboard arrow navigation,
/// click selection, and VoiceOver semantics keep working. The visuals are
/// custom: each row clears its `listRowBackground` and draws its own pill /
/// hover fill, so the system's translucent capsule never competes with the
/// solid accent highlight.
struct SettingsSidebarView: View {
    // MARK: - Properties

    /// Currently selected section. Bound to the parent `NavigationSplitView`.
    @Binding var selection: SettingsView.SettingsSection

    /// Grouped sidebar layout (optional header + member sections). Supplied by
    /// `SettingsView.sidebarGroups` so the order/headers stay defined in one place.
    let groups: [(title: String?, sections: [SettingsView.SettingsSection])]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            SettingsBrandHeader()

            List(selection: $selection) {
                ForEach(groups, id: \.sections) { group in
                    // Title-less groups (e.g. General) render as a plain section so
                    // they sit flush under the brand header with no empty header gap.
                    // `Section(title)` lets `.sidebar` supply the native uppercase /
                    // secondary header treatment for the named groups.
                    if let title = group.title {
                        Section(title) { rows(for: group.sections) }
                    } else {
                        Section { rows(for: group.sections) }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }

    /// Selectable navigation rows for one group. Each row clears its system
    /// background so `SettingsSidebarRow` owns the selection pill / hover fill.
    @ViewBuilder
    private func rows(for sections: [SettingsView.SettingsSection]) -> some View {
        ForEach(sections) { section in
            SettingsSidebarRow(section: section, isSelected: selection == section)
                .tag(section)
                .listRowInsets(EdgeInsets(
                    top: DSSpace.s0,
                    leading: DSSpace.s2,
                    bottom: DSSpace.s0,
                    trailing: DSSpace.s2
                ))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }
}

// MARK: - Brand Header

/// App identity block pinned above the navigation list: the WolfWave mark in a
/// gradient tile, the app name, and the running version. Mirrors VoiceInk's
/// branded sidebar header.
private struct SettingsBrandHeader: View {
    var body: some View {
        HStack(spacing: DSSpace.s3) {
            RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [DSColor.partnerWolfwaveGradientStart, DSColor.partnerWolfwaveGradientEnd],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)
                .overlay {
                    Image("WolfMark")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 0) {
                Text(AboutCopy.appName)
                    .font(.system(size: DSFont.Size.md, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("v\(AboutCopy.version)")
                    .font(.system(size: DSFont.Size.xs, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DSSpace.s4)
        .padding(.top, DSSpace.s5)
        .padding(.bottom, DSSpace.s4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(AboutCopy.appName), version \(AboutCopy.version)"))
    }
}

// MARK: - Sidebar Row

/// One navigation row: a circular icon chip plus the section title, wrapped in a
/// rounded background that becomes a solid accent pill when selected and a faint
/// fill on hover.
private struct SettingsSidebarRow: View {
    let section: SettingsView.SettingsSection
    let isSelected: Bool

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: DSSpace.s3) {
            iconChip
            Text(section.rawValue)
                .font(.system(size: DSFont.Size.base, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DSSpace.s2)
        .padding(.vertical, DSSpace.s1h)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(DSMotion.Spring.snappy, value: isSelected)
        .animation(.easeOut(duration: DSMotion.Duration.fast), value: isHovering)
        .accessibilityLabel(Text(section.rawValue))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(section.rawValue.replacingOccurrences(of: " ", with: "-").lowercased())
    }

    // MARK: Row Background

    @ViewBuilder
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
            .fill(backgroundFill)
            .shadow(
                color: isSelected ? Color.accentColor.opacity(0.30) : .clear,
                radius: isSelected ? 4 : 0,
                y: isSelected ? 1 : 0
            )
    }

    private var backgroundFill: Color {
        if isSelected { return Color.accentColor }
        if isHovering { return Color.primary.opacity(0.06) }
        return .clear
    }

    // MARK: Icon Chip

    @ViewBuilder
    private var iconChip: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.white.opacity(0.22) : Color.primary.opacity(0.06))
            icon
        }
        .frame(width: 26, height: 26)
    }

    @ViewBuilder
    private var icon: some View {
        if let brandIcon = section.brandIcon {
            Image(brandIcon)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
                .foregroundStyle(iconColor)
        } else {
            Image(systemName: section.systemIcon)
                .font(.system(size: DSFont.Size.base, weight: .semibold))
                .foregroundStyle(iconColor)
        }
    }

    /// Icon tint: white on the selection pill, brand color for partner icons
    /// (Twitch / Discord) at rest, and a muted secondary tone otherwise.
    private var iconColor: Color {
        if isSelected { return .white }
        switch section {
        case .twitchIntegration: return DSColor.partnerTwitch
        case .discord: return DSColor.partnerDiscord
        default: return .secondary
        }
    }
}
