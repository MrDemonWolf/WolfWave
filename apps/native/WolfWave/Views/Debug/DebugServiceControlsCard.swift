//
//  DebugServiceControlsCard.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-16.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

#if DEBUG
import SwiftUI

/// DEBUG-only card for poking live services: force reconnects, fake track events,
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
    @State private var musicSelfTestReport: String = ""
    @State private var musicSelfTestRunning: Bool = false
    @AppStorage(AppConstants.UserDefaults.debugTreatAllChattersAsViewers)
    private var treatAllChattersAsViewers = false
    @AppStorage(AppConstants.UserDefaults.debugViewerUsernames)
    private var viewerUsernames = ""

    private var appDelegate: AppDelegate? { AppDelegate.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            Text("Drive services directly without waiting on real events.")
                .font(.system(size: DSFont.Size.body))
                .foregroundStyle(.secondary)

            playbackSection
            Divider()
            musicAccessSection
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
            sectionLabel("Apple Music: Inject Track")
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

    // MARK: - Music Access Self-Test

    /// Exercises the real Apple Event path against the running Music.app.
    ///
    /// No unit test can cover this: the failure it catches only exists inside the
    /// sandboxed app talking to a live Music. 2.1.0 shipped with every Apple
    /// Event failing at runtime while CI stayed green, because the tests asserted
    /// the shape of an event descriptor instead of whether Music answered. This
    /// button is the check that would have caught it in seconds.
    ///
    /// The ScriptingBridge half needs no button: the now-playing card is already
    /// its live indicator. If music is playing and the card says otherwise, that
    /// read is broken.
    private var musicAccessSection: some View {
        VStack(alignment: .leading, spacing: DSSpace.s2) {
            sectionLabel("Apple Music: Access Self-Test")
            Text("Sends a real Apple Event to Music.app. Play a track first.")
                .font(.system(size: DSFont.Size.xs))
                .foregroundStyle(.secondary)

            Button {
                Task { await runMusicAccessSelfTest() }
            } label: {
                Label("Run Music Access Self-Test", systemImage: "stethoscope")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .pointerCursor()
            .disabled(musicSelfTestRunning)

            if !musicSelfTestReport.isEmpty {
                Text(musicSelfTestReport)
                    .font(.system(size: DSFont.Size.sm, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func runMusicAccessSelfTest() async {
        musicSelfTestRunning = true
        defer { musicSelfTestRunning = false }

        var lines: [String] = []
        let pid = MusicProcess.pid
        lines.append("MusicProcess.pid: \(pid.map(String.init) ?? "nil (Music not running)")")

        guard let controller = appDelegate?.songRequestService?.musicController else {
            lines.append("musicController: unavailable (Song Requests not started)")
            musicSelfTestReport = lines.joined(separator: "\n")
            return
        }
        lines.append("isMusicAppRunning: \(controller.isMusicAppRunning ? "yes" : "no")")

        if let snapshot = await controller.playbackSnapshot() {
            let key = snapshot.trackKey?.replacingOccurrences(of: "\t", with: " — ") ?? "nil"
            lines.append("playbackSnapshot: PASS")
            lines.append("  state: \(snapshot.state)")
            lines.append("  track: \(key)")
        } else {
            lines.append("playbackSnapshot: FAIL (nil)")
            lines.append("  Music unreachable, or nothing loaded.")
            lines.append("  Apple Event error number is in the Logs card.")
        }

        musicSelfTestReport = lines.joined(separator: "\n")
    }

    // MARK: - Twitch

    private var twitchSection: some View {
        VStack(alignment: .leading, spacing: DSSpace.s2) {
            sectionLabel("Twitch")
            Text("Connected: \(appDelegate?.twitchService?.currentlyConnected == true ? "yes" : "no")")
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.secondary)
            Toggle("Treat every chatter as a normal viewer", isOn: $treatAllChattersAsViewers)
                .font(.system(size: DSFont.Size.sm))
            TextField("Or test these usernames (comma-separated)", text: $viewerUsernames)
                .textFieldStyle(.roundedBorder)
                .disabled(treatAllChattersAsViewers)
            Text("Uses normal viewer permissions and cooldowns. Debug builds only.")
                .font(.system(size: DSFont.Size.xs))
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
                        Task { await service.sendMessage("WolfWave debug ping: \(Date())") }
                    }
                } label: {
                    Label("Send Test Chat", systemImage: "paperplane")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .pointerCursor()
                .disabled(appDelegate?.twitchService?.currentlyConnected != true)
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
                    DefaultsStore.store.removeObject(forKey: AppConstants.UserDefaults.updateSkippedVersion)
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
                let current = FeatureFlags.songRequestHoldEnabled
                Task {
                    await appDelegate?.songRequestService?.setHold(!current)
                    DefaultsStore.store.set(!current, forKey: AppConstants.UserDefaults.songRequestHoldEnabled)
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
                song: .debugPlaceholder(
                    id: "debug\(index + 1)",
                    title: "Debug Song \(index + 1)",
                    artist: "Debug Artist",
                    album: "Debug Album"
                ),
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
