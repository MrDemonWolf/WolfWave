//
//  DebugServiceControlsCard.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-16.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

#if DEBUG
import SwiftUI

/// DEBUG-only card for poking live services — force reconnects, fake track events,
/// queue injection, and Sparkle / WebSocket broadcasts.
struct DebugServiceControlsCard: View {
    @State private var fakeTitle: String = "Test Track"
    @State private var fakeArtist: String = "Test Artist"
    @State private var fakeAlbum: String = "Test Album"
    @State private var fakePlaylist: String = "Test Playlist"
    @State private var fakeDuration: Double = 180
    @State private var fakeIsPaused: Bool = false
    @State private var queueRequester: String = "tester"
    @State private var queueCount: Int = 3
    @State private var wsTestTitle: String = "WS Test"
    @State private var wsTestArtist: String = "Debug"

    private var appDelegate: AppDelegate? { AppDelegate.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            Text("Drive services directly without waiting on real events.")
                .font(.system(size: DSFont.Size.body))
                .foregroundStyle(.secondary)

            playbackSection
            Divider()
            twitchSection
            Divider()
            discordSection
            Divider()
            webSocketSection
            Divider()
            sparkleSection
            Divider()
            songRequestSection
        }
        .cardStyle()
    }

    // MARK: - Playback

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: DSSpace.s2) {
            sectionLabel("Apple Music — Inject Track")
            TextField("Title", text: $fakeTitle).textFieldStyle(.roundedBorder)
            TextField("Artist", text: $fakeArtist).textFieldStyle(.roundedBorder)
            TextField("Album", text: $fakeAlbum).textFieldStyle(.roundedBorder)
            TextField("Playlist", text: $fakePlaylist).textFieldStyle(.roundedBorder)
            HStack {
                Text("Duration: \(Int(fakeDuration))s")
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.secondary)
                Slider(value: $fakeDuration, in: 30...600, step: 15)
            }
            Toggle("Inject as paused", isOn: $fakeIsPaused)
                .font(.system(size: DSFont.Size.sm))
            HStack {
                Button {
                    appDelegate?.playbackSource(
                        didUpdateTrack: fakeTitle,
                        artist: fakeArtist,
                        album: fakeAlbum,
                        playlist: fakePlaylist,
                        duration: fakeDuration,
                        elapsed: 0,
                        isPaused: fakeIsPaused
                    )
                } label: {
                    Label("Inject Track", systemImage: "music.note")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .pointerCursor()

                Button {
                    appDelegate?.playbackSource(didUpdateStatus: "No track playing")
                } label: {
                    Label("Simulate Stop", systemImage: "stop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .pointerCursor()
            }
        }
    }

    // MARK: - Twitch

    private var twitchSection: some View {
        VStack(alignment: .leading, spacing: DSSpace.s2) {
            sectionLabel("Twitch")
            Text("Connected: \(appDelegate?.twitchService?.isConnectedSnapshot.value == true ? "yes" : "no")")
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.secondary)
            HStack {
                Button {
                    if let service = appDelegate?.twitchService {
                        Task { await service.leaveChannel() }
                    }
                } label: {
                    Label("Force Disconnect", systemImage: "wifi.slash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .pointerCursor()

                Button {
                    if let service = appDelegate?.twitchService {
                        Task { await service.sendMessage("WolfWave debug ping — \(Date())") }
                    }
                } label: {
                    Label("Send Test Chat", systemImage: "paperplane")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .pointerCursor()
                .disabled(appDelegate?.twitchService?.isConnectedSnapshot.value != true)
            }
        }
    }

    // MARK: - Discord

    private var discordSection: some View {
        VStack(alignment: .leading, spacing: DSSpace.s2) {
            sectionLabel("Discord RPC")
            HStack {
                Button {
                    if let service = appDelegate?.discordService {
                        Task { await service.clearPresence() }
                    }
                } label: {
                    Label("Clear Presence", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .pointerCursor()

                Button {
                    // Disable + re-enable cycle = full reconnect
                    if let service = appDelegate?.discordService {
                        Task {
                            await service.setEnabled(false)
                            try? await Task.sleep(for: .milliseconds(500))
                            await service.setEnabled(true)
                        }
                    }
                } label: {
                    Label("Force Reconnect", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .pointerCursor()
            }
        }
    }

    // MARK: - WebSocket

    private var webSocketSection: some View {
        VStack(alignment: .leading, spacing: DSSpace.s2) {
            sectionLabel("WebSocket Server")
            TextField("Track title", text: $wsTestTitle).textFieldStyle(.roundedBorder)
            TextField("Artist", text: $wsTestArtist).textFieldStyle(.roundedBorder)
            HStack {
                Button {
                    let server = appDelegate?.websocketServer
                    let title = wsTestTitle
                    let artist = wsTestArtist
                    Task {
                        await server?.updateNowPlaying(
                            track: title,
                            artist: artist,
                            album: "Debug",
                            duration: 180,
                            elapsed: 0
                        )
                    }
                } label: {
                    Label("Broadcast Test", systemImage: "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .pointerCursor()

                Button {
                    let server = appDelegate?.websocketServer
                    Task { await server?.clearNowPlaying() }
                } label: {
                    Label("Clear", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .pointerCursor()
            }
        }
    }

    // MARK: - Sparkle

    private var sparkleSection: some View {
        VStack(alignment: .leading, spacing: DSSpace.s2) {
            sectionLabel("Sparkle Updater")
            HStack {
                Button {
                    appDelegate?.sparkleUpdater?.checkForUpdates()
                } label: {
                    Label("Check for Updates", systemImage: "arrow.down.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .pointerCursor()

                Button {
                    UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.updateSkippedVersion)
                    Log.info("Cleared updateSkippedVersion (dev)", category: "Update")
                } label: {
                    Label("Clear Skipped Version", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .pointerCursor()
            }
        }
    }

    // MARK: - Song Request

    private var songRequestSection: some View {
        VStack(alignment: .leading, spacing: DSSpace.s2) {
            sectionLabel("Song Request Queue")
            HStack {
                TextField("Requester", text: $queueRequester).textFieldStyle(.roundedBorder)
                Stepper("Count: \(queueCount)", value: $queueCount, in: 1...20)
                    .controlSize(.small)
            }
            HStack {
                Button {
                    injectFakeRequests()
                } label: {
                    Label("Inject Fake Requests", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .pointerCursor()

                Button {
                    Task {
                        _ = await appDelegate?.songRequestService?.clearQueue()
                    }
                } label: {
                    Label("Clear Queue", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .pointerCursor()
            }

            Button {
                let current = UserDefaults.standard.bool(forKey: AppConstants.UserDefaults.songRequestHoldEnabled)
                Task {
                    await appDelegate?.songRequestService?.setHold(!current)
                    UserDefaults.standard.set(!current, forKey: AppConstants.UserDefaults.songRequestHoldEnabled)
                }
            } label: {
                Label("Toggle Hold Mode", systemImage: "pause.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .pointerCursor()
        }
    }

    private func injectFakeRequests() {
        guard let queue = appDelegate?.songRequestService?.queue else { return }
        for index in 0..<queueCount {
            let item = SongRequestItem(
                title: "Debug Song \(index + 1)",
                artist: "Debug Artist",
                requesterUsername: queueRequester.isEmpty ? "tester" : queueRequester
            )
            _ = queue.add(item)
        }
        Log.info("Injected \(queueCount) fake requests (dev)", category: "SongRequest")
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .sectionEyebrow()
    }
}

#Preview {
    DebugServiceControlsCard()
        .padding()
        .frame(width: 600)
}
#endif
