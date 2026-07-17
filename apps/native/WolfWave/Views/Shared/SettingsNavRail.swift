//
//  SettingsNavRail.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-04.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit
import SwiftUI

// MARK: - Rail Section

/// A section that can appear as a row in a ``SettingsNavRail``.
///
/// Conformers are `String`-raw enums: the raw value seeds the accessibility
/// identifier and the `ScrollViewReader` anchor, while `title` labels the row and
/// `icon` is its leading SF Symbol. `DebugSection` conforms with no extra members
/// because it already exposes `title` + `icon`.
protocol SettingsRailSection: Hashable, RawRepresentable where RawValue == String {
    /// Row label. Also used as the rail tooltip ("Jump to <title>").
    var title: String { get }
    /// Leading SF Symbol name for the row.
    var icon: String { get }
}

// MARK: - Rail Group

/// One labelled cluster of rail rows. Flat rails pass a single group with a
/// `nil` title; grouped rails (e.g. the Debug tab) pass several titled groups,
/// each introduced by a `.sectionEyebrow()` header in the rail.
struct SettingsRailGroup<Section: SettingsRailSection> {
    let title: String?
    let sections: [Section]

    init(title: String? = nil, sections: [Section]) {
        self.title = title
        self.sections = sections
    }
}

// MARK: - Scroll-Sync Plumbing

/// Coordinate space the section anchors report their offset in. A single name is
/// fine: only one settings pane is on screen at a time.
private let settingsRailSpace = "settingsRailScroll"

/// Collects each anchored section's top offset (in the rail scroll space) so the
/// highlight can follow manual scrolling, not just taps. Later values win on
/// merge, so the freshest geometry read for a given section is the one that lands.
struct SectionOffsetPreferenceKey<Section: Hashable>: PreferenceKey {
    static var defaultValue: [Section: CGFloat] { [:] }

    static func reduce(
        value: inout [Section: CGFloat],
        nextValue: () -> [Section: CGFloat]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Tags this view as the scroll target **and** offset anchor for `section`.
    ///
    /// Applies `.id(section)` (so `ScrollViewReader.scrollTo(section)` lands here)
    /// and reports the view's top offset into `SectionOffsetPreferenceKey` so the
    /// rail highlight tracks where the user scrolled. Apply once per rail section,
    /// on the view that should sit at the top when its rail row is tapped.
    func railSection<Section: SettingsRailSection>(_ section: Section) -> some View {
        self
            .id(section)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: SectionOffsetPreferenceKey<Section>.self,
                        value: [section: geo.frame(in: .named(settingsRailSpace)).minY]
                    )
                }
            )
    }
}

// MARK: - Settings Nav Rail

/// Two-column settings layout: a fixed jump-nav rail on the left and one
/// always-mounted, scrollable content column on the right. Tapping a rail row
/// scrolls its section to the top; scrolling manually moves the highlight to
/// whatever section you land on. Shared by General, Debug, Song Requests, and
/// History & Stats so the rail reads and behaves identically across panes.
///
/// Callers supply the stacked section views in `content` and tag each one with
/// ``SwiftUICore/View/railSection(_:)`` to wire up the scroll anchor + highlight.
struct SettingsNavRail<Section: SettingsRailSection, Content: View>: View {

    @Binding var selection: Section
    let groups: [SettingsRailGroup<Section>]
    /// Prefix for each row's accessibility identifier, e.g. `"generalNav"` →
    /// `"generalNav.music"`.
    let accessibilityIDPrefix: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollViewReader { proxy in
            HStack(alignment: .top, spacing: 0) {
                navRail(proxy: proxy)

                Divider()

                ScrollView {
                    // Plain VStack, not Lazy: every section must stay mounted so
                    // `proxy.scrollTo(section)` lands on off-screen anchors and the
                    // scroll-sync highlight reads every section's offset. A
                    // LazyVStack defers off-screen children, so jumping to a
                    // section below the fold (e.g. Appearance under a tall Music
                    // section) silently no-ops. Matches the "always-mounted" intent.
                    VStack(alignment: .leading, spacing: AppConstants.SettingsUI.sectionSpacing) {
                        content()
                    }
                    .frame(maxWidth: AppConstants.SettingsUI.maxContentWidth, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppConstants.SettingsUI.contentPaddingH)
                    .padding(.vertical, AppConstants.SettingsUI.contentPaddingV)
                }
                // Claim the full proposed height explicitly, matching `navRail`.
                // Without this the content ScrollView, as a greedy view inside an
                // `HStack(alignment: .top)` sized by an ancestor frame, can resolve
                // to its natural content height instead of the viewport height,
                // so a long pane (e.g. Debug) overflows the window with no scroll
                // and `proxy.scrollTo` lands on an anchor that never moves.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .coordinateSpace(name: settingsRailSpace)
                .onPreferenceChange(SectionOffsetPreferenceKey<Section>.self) { offsets in
                    syncSelection(from: offsets)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Nav Rail

    private func navRail(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpace.s1) {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    if let title = group.title {
                        Text(title)
                            .sectionEyebrow()
                            .padding(.top, DSSpace.s3)
                            .padding(.horizontal, DSSpace.s2)
                    }
                    ForEach(group.sections, id: \.self) { section in
                        navRow(section, proxy: proxy)
                    }
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

    private func navRow(_ section: Section, proxy: ScrollViewProxy) -> some View {
        let isSelected = selection == section
        return Button {
            selection = section
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
                RoundedRectangle(cornerRadius: DSRadius.sm)
                    .fill(isSelected ? DSColor.info.opacity(0.14) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help("Jump to \(section.title)")
        .accessibilityIdentifier("\(accessibilityIDPrefix).\(section.rawValue)")
    }

    // MARK: - Scroll-position sync

    /// Picks the active rail row from live section offsets: the lowest section
    /// whose top has scrolled at or above the activation line near the viewport
    /// top. When nothing has crossed it yet (scrolled to the very top), the first
    /// section stays selected.
    private func syncSelection(from offsets: [Section: CGFloat]) {
        let activationLine = AppConstants.SettingsUI.contentPaddingV + DSSpace.s8
        let fallback = groups.first?.sections.first
        let next = offsets
            .filter { $0.value <= activationLine }
            .max { $0.value < $1.value }?
            .key ?? fallback
        if let next, next != selection { selection = next }
    }
}

// MARK: - Preview

#if DEBUG
private enum SettingsNavRailPreviewSection: String, CaseIterable, SettingsRailSection {
    case alpha, bravo, charlie

    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .alpha: return "1.circle"
        case .bravo: return "2.circle"
        case .charlie: return "3.circle"
        }
    }
}

#Preview("SettingsNavRail") {
    struct Demo: View {
        @State private var selected: SettingsNavRailPreviewSection = .alpha
        var body: some View {
            SettingsNavRail(
                selection: $selected,
                groups: [SettingsRailGroup(sections: SettingsNavRailPreviewSection.allCases)],
                accessibilityIDPrefix: "previewNav"
            ) {
                ForEach(SettingsNavRailPreviewSection.allCases, id: \.self) { section in
                    VStack(alignment: .leading, spacing: DSSpace.s2) {
                        Text(section.title).sectionHeader()
                        Text("Content for \(section.title).")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 320, alignment: .topLeading)
                    .railSection(section)
                }
            }
        }
    }
    return Demo()
        .frame(width: 820, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
}
#endif
