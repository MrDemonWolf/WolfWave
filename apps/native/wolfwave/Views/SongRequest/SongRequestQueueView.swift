//
//  SongRequestQueueView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 4/8/26.
//

import MusicKit
import SwiftUI

/// Displays the song request queue with drag-to-reorder and remove actions.
///
/// Shows the currently playing request (if any) and the upcoming queue.
/// Provides skip and clear actions for the streamer.
struct SongRequestQueueView: View {
    // MARK: - Properties

    private var appDelegate: AppDelegate? {
        AppDelegate.shared
    }

    private var queue: SongRequestQueue? {
        appDelegate?.songRequestService?.queue
    }

    private var service: SongRequestService? {
        appDelegate?.songRequestService
    }

    @State private var items: [SongRequestItem] = []
    @State private var nowPlaying: SongRequestItem?
    @State private var refreshTimer: Timer?
    @State private var showingClearConfirm = false
    @State private var isMusicAppClosed = false
    @State private var isHeld = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Song Request Queue")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                if isHeld {
                    Label("Hold — curate then tap Resume", systemImage: "pause.circle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.orange.opacity(0.12))
                        .clipShape(Capsule())
                } else if isMusicAppClosed {
                    Label("Music.app closed — requests are saved", systemImage: "pause.circle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.orange.opacity(0.12))
                        .clipShape(Capsule())
                } else if !items.isEmpty {
                    Text("\(items.count) in queue")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
            }

            // Now Playing
            if let nowPlaying {
                nowPlayingRow(nowPlaying)
            }

            // Queue
            if items.isEmpty && nowPlaying == nil {
                emptyState
            } else if items.isEmpty {
                Text("Queue is empty — this is the last requested song.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                queueList
            }

            // Actions
            if nowPlaying != nil || !items.isEmpty {
                actionButtons
            }
        }
        .padding(AppConstants.SettingsUI.cardPadding)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))
        .onAppear { startRefresh() }
        .onDisappear { stopRefresh() }
    }

    // MARK: - Now Playing Row

    private func nowPlayingRow(_ item: SongRequestItem) -> some View {
        HStack(spacing: 10) {
            artworkPlaceholder

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                    Text("Now Playing")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                }
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text("\(item.artist) — requested by \(item.requesterUsername)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(8)
        .background(.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Queue List

    private var queueList: some View {
        VStack(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 20)

                    smallArtworkPlaceholder

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Text("\(item.artist) — \(item.requesterUsername)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        queue?.remove(id: item.id)
                        let remainingSongs = queue?.items.compactMap { $0.song } ?? []
                        Task {
                            try? await service?.musicController.rebuildPlayerQueue(from: remainingSongs)
                        }
                        refreshState()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(item.title) from queue")
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("No song requests yet")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Viewers can request songs with !sr in Twitch chat")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    _ = await service?.skip()
                    refreshState()
                }
            } label: {
                Label("Skip", systemImage: "forward.fill")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(nowPlaying == nil)

            Button {
                Task {
                    await service?.setHold(!isHeld)
                    refreshState()
                }
            } label: {
                Label(isHeld ? "Resume" : "Hold", systemImage: isHeld ? "play.fill" : "pause.fill")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(isHeld ? .green : .orange)

            Button {
                showingClearConfirm = true
            } label: {
                Label("Clear Queue", systemImage: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(items.isEmpty && nowPlaying == nil)
            .confirmationDialog(
                "Clear all song requests?",
                isPresented: $showingClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear Queue", role: .destructive) {
                    Task { _ = await service?.clearQueue(); refreshState() }
                }
            }

            Spacer()
        }
    }

    // MARK: - Artwork Placeholders

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(.quaternary)
            .frame(width: 40, height: 40)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
            }
    }

    private var smallArtworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.quaternary)
            .frame(width: 30, height: 30)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
    }

    // MARK: - Refresh

    private func startRefresh() {
        refreshState()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            DispatchQueue.main.async { refreshState() }
        }
    }

    private func stopRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func refreshState() {
        items = queue?.items ?? []
        nowPlaying = queue?.nowPlaying
        isMusicAppClosed = !(service?.musicController.isMusicAppRunning ?? true)
        isHeld = service?.isHoldEnabled ?? false
    }
}

// MARK: - Preview

#Preview("Song Request Queue") {
    SongRequestQueueView()
        .padding()
        .frame(width: 500)
}
