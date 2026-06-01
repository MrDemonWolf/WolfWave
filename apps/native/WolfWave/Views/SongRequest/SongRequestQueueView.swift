//
//  SongRequestQueueView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
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
    @State private var showingClearConfirm = false
    @State private var isMusicAppClosed = false
    @State private var isHeld = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            // Header
            HStack {
                Text("Song Request Queue")
                    .font(.system(size: DSFont.Size.base, weight: .semibold))

                Spacer()

                if isHeld {
                    Label("Hold. Curate, then tap Resume", systemImage: "pause.circle.fill")
                        .font(.system(size: DSFont.Size.xs, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, DSSpace.s2)
                        .padding(.vertical, DSSpace.s1)
                        .background(.orange.opacity(0.12))
                        .clipShape(Capsule())
                } else if isMusicAppClosed {
                    Label("Music is closed, requests are saved", systemImage: "pause.circle.fill")
                        .font(.system(size: DSFont.Size.xs, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, DSSpace.s2)
                        .padding(.vertical, DSSpace.s1)
                        .background(.orange.opacity(0.12))
                        .clipShape(Capsule())
                } else if !items.isEmpty {
                    Text("\(items.count) in queue")
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, DSSpace.s2)
                        .padding(.vertical, DSSpace.s1)
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
                Text("Queue is empty, this is the last requested song.")
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, DSSpace.s2)
            } else {
                queueList
            }

            // Actions
            if nowPlaying != nil || !items.isEmpty {
                actionButtons
            }
        }
        .cardStyle()
        .onAppear { refreshState() }
        .onReceive(NotificationCenter.default.publisher(for: .songRequestQueueChanged)) { _ in
            refreshState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .songRequestHoldChanged)) { _ in
            refreshState()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { note in
            if (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == AppConstants.Music.bundleIdentifier {
                isMusicAppClosed = false
            }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { note in
            if (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == AppConstants.Music.bundleIdentifier {
                isMusicAppClosed = true
            }
        }
    }

    // MARK: - Now Playing Row

    /// Builds the highlighted "Now Playing" row at the top of the queue list,
    /// showing the artwork placeholder, waveform icon, title, artist, and
    /// requester username.
    ///
    /// - Parameter item: The currently-playing song request.
    /// - Returns: A styled row view.
    private func nowPlayingRow(_ item: SongRequestItem) -> some View {
        HStack(spacing: DSSpace.s3) {
            artworkPlaceholder

            VStack(alignment: .leading, spacing: DSSpace.s0) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: DSFont.Size.xs))
                        .foregroundStyle(.green)
                    Text("Now Playing")
                        .font(.system(size: DSFont.Size.xs, weight: .semibold))
                        .foregroundStyle(.green)
                }
                Text(item.title)
                    .font(.system(size: DSFont.Size.body, weight: .medium))
                    .lineLimit(1)
                Text("\(item.artist) · requested by \(item.requesterUsername)")
                    .font(.system(size: DSFont.Size.xs))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(DSSpace.s2)
        .background(.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Queue List

    private var queueList: some View {
        VStack(spacing: DSSpace.s1) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: DSSpace.s3) {
                    Text("\(index + 1)")
                        .font(.system(size: DSFont.Size.sm, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 20)

                    smallArtworkPlaceholder

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.system(size: DSFont.Size.body))
                            .lineLimit(1)
                        Text("\(item.artist) · requested by \(item.requesterUsername)")
                            .font(.system(size: DSFont.Size.xs))
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
                            .font(.system(size: DSFont.Size.body))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(item.title) from queue")
                }
                .padding(.vertical, DSSpace.s1)
                .padding(.horizontal, DSSpace.s2)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DSSpace.s2) {
            Image(systemName: "music.note.list")
                .font(.system(size: DSFont.Size.x24))
                .foregroundStyle(.tertiary)
            Text("No song requests yet")
                .font(.system(size: DSFont.Size.body))
                .foregroundStyle(.secondary)
            Text("Viewers can request songs with `!sr` in Twitch chat")
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpace.s7)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: DSSpace.s2) {
            Button {
                Task {
                    _ = await service?.skip()
                    refreshState()
                }
            } label: {
                Label("Skip", systemImage: "forward.fill")
                    .font(.system(size: DSFont.Size.sm))
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
                    .font(.system(size: DSFont.Size.sm))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(isHeld ? .green : .orange)

            Button {
                showingClearConfirm = true
            } label: {
                Label("Clear Queue", systemImage: "trash")
                    .font(.system(size: DSFont.Size.sm))
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
                    .font(.system(size: DSFont.Size.x16))
                    .foregroundStyle(.tertiary)
            }
    }

    private var smallArtworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.quaternary)
            .frame(width: 30, height: 30)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: DSFont.Size.body))
                    .foregroundStyle(.tertiary)
            }
    }

    // MARK: - Refresh

    /// Snapshots the live queue + now-playing into the view's `@State`. Skips
    /// the assignment when the values are unchanged so a periodic refresh
    /// tick does not force a full SwiftUI diff.
    private func refreshState() {
        // Only mutate @State when the value actually changes — assigning the same
        // value still invalidates the view, so a 2-second tick would force a full
        // ForEach diff every cycle even when nothing changed.
        let newItems = queue?.items ?? []
        if newItems.map(\.id) != items.map(\.id) {
            items = newItems
        }
        let newNowPlaying = queue?.nowPlaying
        if newNowPlaying?.id != nowPlaying?.id {
            nowPlaying = newNowPlaying
        }
        let newMusicAppClosed = !(service?.musicController.isMusicAppRunning ?? true)
        if newMusicAppClosed != isMusicAppClosed {
            isMusicAppClosed = newMusicAppClosed
        }
        let newHeld = service?.isHoldEnabled ?? false
        if newHeld != isHeld {
            isHeld = newHeld
        }
    }
}

// MARK: - Preview

#Preview("Song Request Queue") {
    SongRequestQueueView()
        .padding()
        .frame(width: 500)
}
