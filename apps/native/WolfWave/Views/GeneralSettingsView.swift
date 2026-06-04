//
//  GeneralSettingsView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-03-18.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// General application settings interface: Music Sync (hero now-playing +
/// integrations dashboard), App Visibility, Appearance, and Notifications.
///
/// Laid out like the Debug tab: a fixed jump-nav rail on the left and one
/// always-mounted, scrollable column of sections on the right. The old in-pane
/// segmented tabs are gone. Clicking a rail row scrolls its section to the top
/// via `ScrollViewReader`, and the rail highlights wherever you are. Each
/// sub-view supplies its own section header, so no extra headings are layered on
/// top; the rail row title doubles as the `ScrollViewReader` anchor label.
struct GeneralSettingsView: View {

    var configure: (IntegrationDashboardView.Section) -> Void = { _ in }

    @AppStorage(AppConstants.UserDefaults.trackingEnabled)
    private var trackingEnabled = true

    /// Rail selection + scroll target. Drives the highlight and the jump.
    @State private var selected: GeneralSection = .music

    var body: some View {
        ScrollViewReader { proxy in
            HStack(alignment: .top, spacing: 0) {
                navRail(proxy: proxy)

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppConstants.SettingsUI.sectionSpacing) {
                        header

                        MusicMonitorSettingsView(configure: configure)

                        AppVisibilitySettingsView()
                            .id(GeneralSection.visibility)
                            .background(sectionAnchor(.visibility))

                        AppearanceSettingsView()
                            .id(GeneralSection.appearance)
                            .background(sectionAnchor(.appearance))

                        NotificationsSettingsView()
                            .id(GeneralSection.notifications)
                            .background(sectionAnchor(.notifications))
                    }
                    .frame(maxWidth: AppConstants.SettingsUI.maxContentWidth, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppConstants.SettingsUI.contentPaddingH)
                    .padding(.vertical, AppConstants.SettingsUI.contentPaddingV)
                }
                .coordinateSpace(name: Self.scrollSpace)
                .onPreferenceChange(SectionOffsetKey.self) { offsets in
                    syncSelection(from: offsets)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Scroll-position sync

    /// Named coordinate space the section anchors report their offset in.
    private static let scrollSpace = "generalScroll"

    /// Reports a section's top offset (relative to the scroll viewport) into
    /// `SectionOffsetKey`, so the rail can highlight whatever the user scrolled
    /// to manually, not just the last row they tapped.
    private func sectionAnchor(_ section: GeneralSection) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: SectionOffsetKey.self,
                value: [section: geo.frame(in: .named(Self.scrollSpace)).minY]
            )
        }
    }

    /// Picks the active rail row from live section offsets: the lowest section
    /// whose top has scrolled at or above the activation line near the viewport
    /// top. When nothing has crossed it yet (scrolled to the very top), Music
    /// (the header region, which carries no anchor) stays selected.
    private func syncSelection(from offsets: [GeneralSection: CGFloat]) {
        let activationLine = AppConstants.SettingsUI.contentPaddingV + DSSpace.s8
        let next = offsets
            .filter { $0.value <= activationLine }
            .max { $0.value < $1.value }?
            .key ?? .music
        if next != selected { selected = next }
    }

    // MARK: - Header

    private var header: some View {
        SectionHeaderWithStatus(
            title: "General",
            subtitle: "Manage how WolfWave tracks your music and where it shows up.",
            statusText: trackingEnabled ? "Music on" : "Music off",
            statusColor: trackingEnabled ? .green : .gray
        )
        .accessibilityIdentifier("generalSettings.header")
        .id(GeneralSection.music)
    }

    // MARK: - Nav Rail

    private func navRail(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpace.s1) {
                ForEach(GeneralSection.allCases) { section in
                    navRow(section, proxy: proxy)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DSSpace.s3)
            .padding(.vertical, DSSpace.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 184)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func navRow(_ section: GeneralSection, proxy: ScrollViewProxy) -> some View {
        let isSelected = selected == section
        return Button {
            selected = section
            withAnimation(.easeInOut(duration: DSMotion.Duration.base)) {
                proxy.scrollTo(section, anchor: .top)
            }
        } label: {
            HStack(spacing: DSSpace.s2) {
                Image(systemName: section.icon)
                    .frame(width: DSSpace.s6, alignment: .center)
                Text(section.title)
                    .font(.system(size: DSFont.Size.body, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, DSSpace.s1)
            .padding(.horizontal, DSSpace.s2)
            .foregroundStyle(isSelected ? DSColor.info : .primary)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? DSColor.info.opacity(0.14) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help("Jump to \(section.title)")
        .accessibilityIdentifier("generalNav.\(section.rawValue)")
    }
}

// MARK: - General Section

/// The General tab's jump-nav sections, in display order. `title` labels the
/// rail row; `id` (the enum case itself) doubles as the `ScrollViewReader`
/// anchor attached to each sub-view. The Music anchor sits on the page header so
/// jumping to Music scrolls all the way to the top.
private enum GeneralSection: String, CaseIterable, Identifiable {
    case music
    case visibility
    case appearance
    case notifications

    var id: String { rawValue }

    var title: String {
        switch self {
        case .music: return "Music"
        case .visibility: return "App Visibility"
        case .appearance: return "Appearance"
        case .notifications: return "Notifications"
        }
    }

    var icon: String {
        switch self {
        case .music: return "music.note"
        case .visibility: return "macwindow"
        case .appearance: return "circle.lefthalf.filled"
        case .notifications: return "bell"
        }
    }
}

// MARK: - Section Offset Key

/// Collects each anchored section's top offset (in the scroll coordinate space)
/// so the parent can resolve which section the user has scrolled to and keep the
/// rail highlight in sync. Later values win on merge, so the freshest geometry
/// read for a given section is the one that lands.
private struct SectionOffsetKey: PreferenceKey {
    static let defaultValue: [GeneralSection: CGFloat] = [:]

    static func reduce(
        value: inout [GeneralSection: CGFloat],
        nextValue: () -> [GeneralSection: CGFloat]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

#Preview("General Settings") {
    GeneralSettingsView()
        .frame(width: 820, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
}

#Preview("Dark Mode") {
    GeneralSettingsView()
        .frame(width: 820, height: 600)
        .preferredColorScheme(.dark)
        .background(Color(nsColor: .windowBackgroundColor))
}
