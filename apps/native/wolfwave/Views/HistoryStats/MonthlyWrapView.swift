//
//  MonthlyWrapView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 5/22/26.
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

    @Environment(\.dismiss) private var dismiss

    private let calendar = Calendar.current

    // MARK: - Derived

    private var wrap: MonthlyWrapData {
        service.monthlyWrap(for: month)
    }

    /// Whether the shown month is the current calendar month (can't go forward).
    private var isCurrentMonth: Bool {
        calendar.isDate(month, equalTo: Date(), toGranularity: .month)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            header

            MonthlyWrapCard(data: wrap)
                .frame(width: 380)

            footer
        }
        .padding(DSSpace.s7)
        .frame(width: 440)
        .background(Color(nsColor: .windowBackgroundColor))
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
            .accessibilityLabel("Previous month")

            Spacer()

            Text(wrap.monthLabel)
                .font(.system(size: DSFont.Size.x15, weight: .semibold))

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

            Button {
                exportImage()
            } label: {
                Label(didExport ? "Saved" : "Export as Image",
                      systemImage: didExport ? "checkmark" : "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .pointerCursor()
            .disabled(!wrap.hasData)
            .accessibilityLabel("Export monthly wrap as an image")
        }
    }

    // MARK: - Actions

    /// Moves the shown month, never past the current month.
    private func shiftMonth(by delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: month) else { return }
        if delta > 0, next > Date() { return }
        month = next
        didExport = false
    }

    /// Renders the wrap card to a PNG and prompts the user for a save location.
    @MainActor
    private func exportImage() {
        let renderer = ImageRenderer(content:
            MonthlyWrapCard(data: wrap)
                .frame(width: 380)
                .padding(DSSpace.s7)
                .background(Color(nsColor: .windowBackgroundColor))
        )
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            Log.warn("MonthlyWrapView: Failed to render wrap image", category: AppConstants.History.logCategory)
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "WolfWave-Wrap-\(wrap.monthLabel).png"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try png.write(to: url)
            withAnimation { didExport = true }
            Log.info("MonthlyWrapView: Exported monthly wrap image", category: AppConstants.History.logCategory)
        } catch {
            Log.error("MonthlyWrapView: Export failed — \(error.localizedDescription)", category: AppConstants.History.logCategory)
        }
    }
}

// MARK: - MonthlyWrapCard

/// The shareable wrap card — displayed in the sheet and rendered to a PNG.
struct MonthlyWrapCard: View {

    let data: MonthlyWrapData

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("WOLFWAVE · MONTHLY WRAP")
                    .font(.system(size: DSFont.Size.x9, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.7))
                Text(data.monthLabel)
                    .font(.system(size: DSFont.Size.x24, weight: .bold))
                    .foregroundStyle(.white)
            }

            if data.hasData {
                HStack(spacing: 24) {
                    statBlock(value: "\(data.totalPlays)", label: "plays")
                    statBlock(value: HistoryFormat.listeningTime(data.totalListeningSeconds), label: "listened")
                }

                Divider().overlay(.white.opacity(0.25))

                if let artist = data.topArtist {
                    wrapRow(caption: "TOP ARTIST", value: artist.name)
                }
                if let track = data.topTrack {
                    wrapRow(
                        caption: "TOP TRACK",
                        value: track.detail.map { "\(track.name) — \($0)" } ?? track.name
                    )
                }

                Text("\(data.uniqueArtists) artists · \(data.uniqueTracks) tracks")
                    .font(.system(size: DSFont.Size.sm, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                Text("No plays recorded in \(data.monthLabel).")
                    .font(.system(size: DSFont.Size.base))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.vertical, DSSpace.s4)
            }
        }
        .padding(DSSpace.s7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    AppConstants.Brand.appleMusicGradientStart,
                    AppConstants.Brand.appleMusicGradientEnd,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func statBlock(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: DSFont.Size.x28, weight: .bold))
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
                .font(.system(size: DSFont.Size.x9, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.6))
            Text(value)
                .font(.system(size: DSFont.Size.x15, weight: .semibold))
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
            id: "taylor swift",
            name: "Taylor Swift",
            detail: nil,
            count: 47
        ),
        topTrack: CountedItem(
            id: "anti-hero|taylor swift",
            name: "Anti-Hero",
            detail: "Taylor Swift",
            count: 22
        ),
        topAlbum: CountedItem(
            id: "midnights",
            name: "Midnights",
            detail: "Taylor Swift",
            count: 81
        ),
        busiestDay: nil
    )
    return MonthlyWrapCard(data: data)
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
    return MonthlyWrapCard(data: data)
        .frame(width: 380)
        .padding()
}
