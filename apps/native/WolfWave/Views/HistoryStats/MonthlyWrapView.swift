//
//  MonthlyWrapView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - MonthlyWrapView

/// Sheet presenting a personal "wrapped"-style summary for one month, with
/// month navigation and a shareable PNG export.
struct MonthlyWrapView: View {

    // MARK: - Properties

    /// The history service supplying records. Observed for live updates.
    let service: ListeningHistoryService

    /// Any date inside the month currently being shown.
    @State private var month: Date = Date()

    /// Set briefly after a successful export to confirm to the user.
    @State private var didExport = false

    /// Color sampled from the top track's album art, blended into the card
    /// gradient. `nil` until artwork loads (or when there's no top track), in
    /// which case the card shows the plain WolfWave brand gradient.
    @State private var tint: Color?

    @Environment(\.dismiss) private var dismiss

    private let calendar = Calendar.current

    /// Shared width for the footer's Share and Export buttons so they match.
    /// Sized to fit the wider "Export as Image" label.
    private let footerButtonWidth: CGFloat = 150

    // MARK: - Derived

    private var wrap: MonthlyWrapData {
        service.monthlyWrap(for: month)
    }

    /// Whether the shown month is the current calendar month (can't go forward).
    private var isCurrentMonth: Bool {
        calendar.isDate(month, equalTo: Date(), toGranularity: .month)
    }

    /// Whether the shown month is the earliest month containing data (can't go back further).
    private var isEarliestMonth: Bool {
        guard let earliest = service.earliestRecordedMonth else { return true }
        return calendar.isDate(month, equalTo: earliest, toGranularity: .month)
    }

    /// Whether any plays have ever been recorded.
    private var hasAnyHistory: Bool {
        service.earliestRecordedMonth != nil
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: DSSpace.s6) {
            if hasAnyHistory {
                header
            }

            MonthlyWrapCard(data: wrap, hasAnyHistory: hasAnyHistory, tint: tint)
                .frame(width: 380)

            footer
        }
        .padding(DSSpace.s7)
        .frame(width: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: month) { await loadTint() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .pointerCursor()
            .disabled(isEarliestMonth)
            .accessibilityLabel("Previous month")

            Spacer()

            Text(wrap.monthLabel)
                .font(.system(size: DSFont.Size.md, weight: .semibold))

            Spacer()

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .pointerCursor()
            .disabled(isCurrentMonth)
            .accessibilityLabel("Next month")
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
                .pointerCursor()

            Spacer()

            if wrap.hasData {
                SharePickerButton(isProminent: true, makeItems: shareItems)
                    .frame(width: footerButtonWidth)
                    .accessibilityLabel("Share monthly wrap")
            }

            Button {
                exportImage()
            } label: {
                Label(didExport ? "Saved" : "Export as Image",
                      systemImage: didExport ? "checkmark" : "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .frame(width: footerButtonWidth)
            .buttonStyle(.borderedProminent)
            .pointerCursor()
            .disabled(!wrap.hasData)
            .accessibilityLabel("Export monthly wrap as an image")
        }
    }

    // MARK: - Actions

    /// Samples a tint color from the top track's album art and stores it for the
    /// card gradient. Re-runs whenever the shown month changes (via `.task(id:)`),
    /// which also cancels any in-flight fetch. No-op when the month has no top
    /// track; failures leave the plain brand gradient in place.
    @MainActor
    private func loadTint() async {
        tint = nil
        guard let track = wrap.topTrack else { return }
        let artist = track.detail ?? ""

        let urlString = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            ArtworkService.shared.fetchArtworkURL(track: track.name, artist: artist) { url in
                continuation.resume(returning: url)
            }
        }

        guard let urlString, let url = URL(string: urlString) else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        guard let image = NSImage(data: data),
              let color = ArtworkTint.dominantColor(from: image) else { return }
        tint = Color(nsColor: color)
    }

    /// Moves the shown month, clamped between the earliest recorded month and the current month.
    private func shiftMonth(by delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: month) else { return }
        if delta > 0, next > Date() { return }
        if delta < 0,
           let earliest = service.earliestRecordedMonth,
           next < earliest { return }
        month = next
        didExport = false
    }

    /// Renders the wrap card to PNG data at 2x scale. Returns nil on render failure.
    @MainActor
    private func renderPNG() -> Data? {
        let renderer = ImageRenderer(content:
            MonthlyWrapCard(data: wrap, hasAnyHistory: hasAnyHistory, tint: tint)
                .frame(width: 380)
                .padding(DSSpace.s7)
                .background(Color(nsColor: .windowBackgroundColor))
        )
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let png = image.pngData() else {
            Log.warn("MonthlyWrapView: Failed to render wrap image", category: AppConstants.History.logCategory)
            return nil
        }
        return png
    }

    /// Suggested file name for a wrap card of the given month label.
    /// Internal + static so it's unit-testable without a live service.
    static func exportFileName(forMonthLabel monthLabel: String) -> String {
        "WolfWave-Wrap-\(monthLabel).png"
    }

    /// Suggested file name for the current month's wrap card.
    private var exportFileName: String {
        Self.exportFileName(forMonthLabel: wrap.monthLabel)
    }

    /// Renders the wrap card to a PNG and prompts the user for a save location.
    @MainActor
    private func exportImage() {
        guard let png = renderPNG() else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = exportFileName
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try png.write(to: url)
            withAnimation { didExport = true }
            Log.info("MonthlyWrapView: Exported monthly wrap image", category: AppConstants.History.logCategory)
        } catch {
            Log.error("MonthlyWrapView: Export failed: \(error.localizedDescription)", category: AppConstants.History.logCategory)
        }
    }

    /// Renders the wrap card to a temp PNG and returns it as the share item for
    /// the macOS share sheet (Messages, Mail, AirDrop, etc.). Nil on failure.
    @MainActor
    private func shareItems() -> [Any]? {
        guard let png = renderPNG() else { return nil }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(exportFileName)
        do {
            try png.write(to: url)
        } catch {
            Log.error("MonthlyWrapView: Share render failed: \(error.localizedDescription)", category: AppConstants.History.logCategory)
            return nil
        }
        return [url]
    }
}

// MARK: - MonthlyWrapCard

/// The shareable wrap card, displayed in the sheet and rendered to a PNG.
struct MonthlyWrapCard: View {

    let data: MonthlyWrapData
    /// `false` when no plays have ever been recorded. Switches the empty branch
    /// from a per-month "no plays" message to a punchy onboarding CTA.
    var hasAnyHistory: Bool = true
    /// Color sampled from the top track's album art, blended as a corner accent
    /// over the brand gradient. `nil` shows the plain WolfWave gradient.
    var tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s5) {
            VStack(alignment: .leading, spacing: DSSpace.s0) {
                HStack(spacing: DSSpace.s2) {
                    if let mark = NSImage(named: "TrayIcon") {
                        Image(nsImage: mark)
                            .resizable()
                            .renderingMode(.template)
                            .interpolation(.high)
                            .frame(width: DSSpace.s6, height: DSSpace.s6)
                            .foregroundStyle(.white)
                    }
                    Text("WOLFWAVE · MONTHLY WRAP")
                        .font(.system(size: DSFont.Size.xs, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Text(data.monthLabel)
                    .font(.system(size: DSFont.Size.x2xl, weight: .bold))
                    .foregroundStyle(.white)
            }

            if data.hasData {
                if let milestone = data.milestone {
                    milestoneBadge(milestone)
                }

                // Hero: one big headline number, framed emotionally.
                VStack(alignment: .leading, spacing: DSSpace.s1) {
                    Text("TRACKS PLAYED")
                        .font(.system(size: DSFont.Size.xs, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.65))
                    Text("\(data.totalPlays)")
                        .font(.system(size: DSFont.Size.display, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.78)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .monospacedDigit()
                    if let framing = data.framingLine {
                        Text(framing)
                            .font(.system(size: DSFont.Size.base))
                            .foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider().overlay(.white.opacity(0.25))

                // Supporting stats, demoted below the hero.
                HStack(alignment: .top, spacing: DSSpace.s7) {
                    miniStat(value: HistoryFormat.listeningTime(data.totalListeningSeconds), label: "listened")
                    miniStat(value: "\(data.uniqueArtists)", label: "artists")
                    miniStat(value: "\(data.uniqueTracks)", label: "tracks")
                }

                if let artist = data.topArtist {
                    wrapRow(caption: "TOP ARTIST", value: artist.name)
                }
                if let track = data.topTrack {
                    wrapRow(
                        caption: "TOP TRACK",
                        value: track.detail.map { "\(track.name) · \($0)" } ?? track.name
                    )
                }
            } else if !hasAnyHistory {
                VStack(alignment: .leading, spacing: DSSpace.s2) {
                    Text("Nothing to wrap yet.")
                        .font(.system(size: DSFont.Size.lg, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Go rave it out. Your Monthly Wrap unlocks once you've logged some plays.")
                        .font(.system(size: DSFont.Size.base))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.vertical, DSSpace.s4)
            } else {
                Text("No plays recorded in \(data.monthLabel).")
                    .font(.system(size: DSFont.Size.base))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.vertical, DSSpace.s4)
            }

            HStack(alignment: .center) {
                Text("WolfWave by MrDemonWolf, Inc.")
                    .font(.system(size: DSFont.Size.xs, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                QRCodeImage(
                    string: AppConstants.URLs.docs,
                    size: DSDimension.Onboarding.brandTileSize
                )
            }
            .padding(.top, DSSpace.s2)
        }
        .padding(DSSpace.s7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.x2xl, style: .continuous))
    }

    /// The brand gradient, with an album-art-tinted radial accent layered into
    /// the top-trailing corner when a `tint` is available.
    private var cardBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AppConstants.Brand.wolfwaveGradientStart,
                    AppConstants.Brand.wolfwaveGradientEnd
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if let tint {
                RadialGradient(
                    gradient: Gradient(colors: [tint.opacity(0.6), .clear]),
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 360
                )
                .blendMode(.screen)
            }
        }
    }

    /// A small bragging-rights pill shown above the hero number.
    @ViewBuilder
    private func milestoneBadge(_ milestone: MonthlyMilestone) -> some View {
        HStack(spacing: DSSpace.s1) {
            Image(systemName: milestone == .bestMonthYet ? "star.fill" : "clock.fill")
            Text(milestone.label.uppercased())
        }
        .font(.system(size: DSFont.Size.xs, weight: .semibold))
        .tracking(0.8)
        .foregroundStyle(.black.opacity(0.82))
        .padding(.horizontal, DSSpace.s3)
        .padding(.vertical, DSSpace.s1)
        .background(
            Capsule().fill(
                LinearGradient(
                    colors: milestone == .bestMonthYet
                        ? [Color(red: 1.0, green: 0.84, blue: 0.42), Color(red: 1.0, green: 0.62, blue: 0.04)]
                        : [Color(red: 0.49, green: 1.0, blue: 0.70), Color(red: 0.0, green: 0.90, blue: 1.0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        )
    }

    /// A demoted supporting stat (listened / artists / tracks) under the hero.
    @ViewBuilder
    private func miniStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: DSFont.Size.lg, weight: .bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: DSFont.Size.sm, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    @ViewBuilder
    private func wrapRow(caption: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(caption)
                .font(.system(size: DSFont.Size.xs, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.6))
            Text(value)
                .font(.system(size: DSFont.Size.md, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
    }
}

// MARK: - Previews

// Note: MonthlyWrapView itself requires a live ListeningHistoryService.
// Previewing the visual card (MonthlyWrapCard) is enough for design iteration.

#Preview("With data") {
    let data = MonthlyWrapData(
        monthLabel: "May 2026",
        monthStart: Date(),
        totalPlays: 412,
        totalListeningSeconds: 76_320,
        uniqueArtists: 58,
        uniqueTracks: 184,
        topArtist: CountedItem(
            id: "arctic wolf",
            name: "Arctic Wolf",
            detail: nil,
            count: 47
        ),
        topTrack: CountedItem(
            id: "moonlit howl|arctic wolf",
            name: "Moonlit Howl",
            detail: "Arctic Wolf",
            count: 22
        ),
        topAlbum: CountedItem(
            id: "tundra sessions",
            name: "Tundra Sessions",
            detail: "Arctic Wolf",
            count: 81
        ),
        busiestDay: nil,
        framingLine: "Almost a full day lost in the music.",
        milestone: .bestMonthYet
    )
    return MonthlyWrapCard(data: data, tint: Color(red: 0.43, green: 0.29, blue: 1.0))
        .frame(width: 380)
        .padding()
}

#Preview("Empty month") {
    let data = MonthlyWrapData(
        monthLabel: "April 2026",
        monthStart: Date(),
        totalPlays: 0,
        totalListeningSeconds: 0,
        uniqueArtists: 0,
        uniqueTracks: 0,
        topArtist: nil,
        topTrack: nil,
        topAlbum: nil,
        busiestDay: nil
    )
    return MonthlyWrapCard(data: data, hasAnyHistory: true)
        .frame(width: 380)
        .padding()
}

#Preview("No history yet") {
    let data = MonthlyWrapData(
        monthLabel: "May 2026",
        monthStart: Date(),
        totalPlays: 0,
        totalListeningSeconds: 0,
        uniqueArtists: 0,
        uniqueTracks: 0,
        topArtist: nil,
        topTrack: nil,
        topAlbum: nil,
        busiestDay: nil
    )
    return MonthlyWrapCard(data: data, hasAnyHistory: false)
        .frame(width: 380)
        .padding()
}
