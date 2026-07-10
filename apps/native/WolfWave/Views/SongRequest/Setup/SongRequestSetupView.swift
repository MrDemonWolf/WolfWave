//
//  SongRequestSetupView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-08.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import MusicKit
import SwiftUI

/// Guided Song Requests setup, shown as a sheet over the settings window.
///
/// A small analog of the first-launch `OnboardingView`: progress dots, one step
/// at a time through the shared `OnboardingStepScaffold`, and a Back / Next /
/// Done bar. It walks the three essentials (Twitch, Apple Music access, the
/// WolfWave Requests playlist) and an optional `!playlist` share step, then
/// flips the master toggle on. Lives in a sheet, not its own `NSWindow`, so it
/// stays anchored to the pane that launched it.
struct SongRequestSetupView: View {

    // MARK: - State

    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: SongRequestSetupViewModel

    @State private var musicAuthStatus: MusicAuthorization.Status = MusicAuthorization.currentStatus
    @State private var isRequestingMusicAuth = false

    @State private var libraryService = AppleMusicLibraryService()
    @State private var musicController = AppleMusicController()

    @State private var ensuringPlaylist = false
    @State private var playlistError: String?

    @State private var fetchingLink = false
    @State private var fetchStatus: String?

    @State private var navigationDirection: Edge = .trailing

    @AppStorage(AppConstants.UserDefaults.songRequestSongListURL)
    private var songListURL = ""
    @AppStorage(AppConstants.UserDefaults.songListCommandEnabled)
    private var songListCommandEnabled = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var appDelegate: AppDelegate? { AppDelegate.shared }

    // MARK: - Init

    /// - Parameter startAt: Step to open on. `.intro` for a fresh setup, or
    ///   `.shareLink` when launched from the "Re-share Playlist" banner.
    init(startAt: SongRequestSetupViewModel.Step = .intro) {
        _viewModel = State(initialValue: SongRequestSetupViewModel(startAt: startAt))
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            progressDots
                .padding(.top, DSSpace.s7)
                .padding(.bottom, DSSpace.s6)

            ScrollView(.vertical, showsIndicators: false) {
                stepContent
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, DSSpace.s6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(DSMotion.Spring.snappy, value: viewModel.currentStep)

            Divider()

            navigationBar
                .padding(.horizontal, DSSpace.s8)
                .padding(.vertical, DSSpace.s5)
                .background(.regularMaterial)
        }
        .frame(width: 580, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            refreshTwitchState()
            syncAuth(MusicAuthorization.currentStatus)
        }
        .onChange(of: musicAuthStatus) { _, new in syncAuth(new) }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.twitchConnectionStateChanged)) { note in
            if let connected = note.isConnectedFlag {
                viewModel.isTwitchConnected = connected
            }
        }
        .task(id: viewModel.currentStep) {
            if viewModel.currentStep == .playlist, !viewModel.playlistReady {
                await ensurePlaylist()
            }
        }
    }

    // MARK: - Progress Dots

    private var progressDots: some View {
        VStack(spacing: DSSpace.s2) {
            HStack(spacing: DSSpace.s2) {
                ForEach(SongRequestSetupViewModel.Step.allCases, id: \.rawValue) { step in
                    Circle()
                        .fill(step == viewModel.currentStep
                            ? Color.accentColor
                            : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .scaleEffect(step == viewModel.currentStep ? 1.3 : 1.0)
                        .animation(DSMotion.Spring.gentle, value: viewModel.currentStep)
                        .accessibilityHidden(true)
                }
            }

            Text("Step \(viewModel.currentStep.rawValue + 1) of \(viewModel.totalSteps) \u{00B7} \(viewModel.currentStep.progressTitle)")
                .font(.system(size: DSFont.Size.xs, weight: .medium))
                .foregroundStyle(.secondary)
                .animation(.none, value: viewModel.currentStep)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Setup progress")
        .accessibilityValue("Step \(viewModel.currentStep.rawValue + 1) of \(viewModel.totalSteps): \(viewModel.currentStep.accessibilityTitle)")
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        Group {
            switch viewModel.currentStep {
            case .intro: introStep
            case .appleMusic: appleMusicStep
            case .playlist: playlistStep
            case .shareLink: shareLinkStep
            case .done: doneStep
            }
        }
        .id(viewModel.currentStep)
        .transition(reduceMotion
            ? AnyTransition.opacity
            : .asymmetric(
                insertion: .move(edge: navigationDirection).combined(with: .opacity),
                removal: .move(edge: navigationDirection == .trailing ? .leading : .trailing).combined(with: .opacity)
            )
        )
    }

    // MARK: Step 1 - Intro

    private var introStep: some View {
        OnboardingStepScaffold(
            title: "Set up Song Requests",
            description: "A quick walk-through so viewers can request songs in your Twitch chat. You can change all of this later in settings.",
            icon: {
                BrandTile(
                    background: AnyShapeStyle(AppConstants.Brand.twitch),
                    glowColor: AppConstants.Brand.twitch,
                    glyph: Image(systemName: "music.note.list")
                        .font(BrandTileGlyph.font)
                        .foregroundStyle(.white)
                )
            },
            extras: {
                Group {
                    if viewModel.isTwitchConnected {
                        CalloutBanner("Twitch is connected. You're good to go.", style: .success)
                    } else {
                        CalloutBanner(
                            "Connect with Twitch first, then come back here. Song requests arrive through your chat.",
                            style: .info,
                            systemImage: "lock.fill"
                        )
                    }
                }
            }
        )
    }

    // MARK: Step 2 - Apple Music access

    private var appleMusicStep: some View {
        OnboardingStepScaffold(
            title: "Allow Apple Music access",
            description: "WolfWave searches Apple Music for requested songs and plays them in Music.app.",
            icon: { appleMusicTile },
            extras: {
                Group {
                    if musicAuthStatus == .authorized {
                        CalloutBanner("Apple Music access granted.", style: .success)
                    } else if musicAuthStatus == .denied {
                        CalloutBanner(
                            "Apple Music access was denied. Turn it on in System Settings, Privacy & Security, then Media & Apple Music.",
                            style: .warning
                        )
                    } else {
                        PillButton(
                            background: AnyShapeStyle(
                                LinearGradient(
                                    colors: [AppConstants.Brand.appleMusicGradientStart, AppConstants.Brand.appleMusicGradientEnd],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            ),
                            disabled: isRequestingMusicAuth,
                            action: { requestMusicAuth() },
                            label: {
                                HStack(spacing: DSSpace.s1h) {
                                    if isRequestingMusicAuth { ProgressView().controlSize(.small) }
                                    Text("Grant Apple Music Access")
                                }
                            }
                        )
                    }
                }
            }
        )
    }

    // MARK: Step 3 - Requests playlist

    private var playlistStep: some View {
        OnboardingStepScaffold(
            title: "Create your requests playlist",
            description: "Requested songs go into one playlist called \(AppConstants.Music.requestsPlaylistName) so your library stays tidy. WolfWave makes it for you.",
            icon: { appleMusicTile },
            extras: {
                VStack(spacing: DSSpace.s3) {
                    if ensuringPlaylist {
                        HStack(spacing: DSSpace.s2) {
                            ProgressView().controlSize(.small)
                            Text("Setting up \(AppConstants.Music.requestsPlaylistName)\u{2026}")
                                .font(.system(size: DSFont.Size.body))
                                .foregroundStyle(.secondary)
                        }
                    } else if viewModel.playlistReady {
                        CalloutBanner("\(AppConstants.Music.requestsPlaylistName) is ready.", style: .success)
                        Text("Made by WolfWave, with a description so chat knows what it is. Apple builds the cover from the songs as they come in.")
                            .font(.system(size: DSFont.Size.xs))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let playlistError {
                        VStack(spacing: DSSpace.s3) {
                            CalloutBanner(playlistError, style: .warning)
                            Button("Try Again") { Task { await ensurePlaylist() } }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            }
        )
    }

    // MARK: Step 4 - Optional share link

    private var shareLinkStep: some View {
        OnboardingStepScaffold(
            title: "Share your playlist",
            description: "Optional. Turn this on if you want !playlist to drop a link to your requests playlist in chat.",
            icon: {
                BrandTile(
                    background: AnyShapeStyle(AppConstants.Brand.twitch),
                    glowColor: AppConstants.Brand.twitch,
                    glyph: Image(systemName: "square.and.arrow.up")
                        .font(BrandTileGlyph.font)
                        .foregroundStyle(.white)
                )
            },
            extras: {
                VStack(alignment: .leading, spacing: DSSpace.s4) {
                    VStack(alignment: .leading, spacing: DSSpace.s3) {
                        setupStep(1, "Open your requests playlist") {
                            Button("Open in Music") { Task { await openPlaylistInMusic() } }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                        setupStep(2, "In Music: tap Share, then Show on Profile") { EmptyView() }
                        setupStep(3, "Grab the link") {
                            Button {
                                Task { await fetchSongListLink() }
                            } label: {
                                if fetchingLink { ProgressView().controlSize(.small) } else { Text("Fetch link") }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(fetchingLink)
                        }
                    }
                    .padding(DSSpace.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .subtleCardShell()

                    if let fetchStatus {
                        Text(fetchStatus)
                            .font(.system(size: DSFont.Size.xs))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    TextField("Link shows up here, or paste your own", text: $songListURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: DSFont.Size.body))

                    Text("Leave blank to skip. !playlist stays off until a link is set.")
                        .font(.system(size: DSFont.Size.xs))
                        .foregroundStyle(.secondary)
                }
            }
        )
    }

    // MARK: Step 5 - Done

    private var doneStep: some View {
        OnboardingStepScaffold(
            title: "You're all set",
            description: "Viewers can request songs with !sr. Fine-tune who can request, queue limits, and commands anytime in settings.",
            icon: {
                BrandTile(
                    background: AnyShapeStyle(DSColor.success),
                    glowColor: DSColor.success,
                    glyph: Image(systemName: "checkmark")
                        .font(BrandTileGlyph.font)
                        .foregroundStyle(.white)
                )
            },
            extras: {
                VStack(alignment: .leading, spacing: DSSpace.s4) {
                    VStack(alignment: .leading, spacing: DSSpace.s2) {
                        recapRow(viewModel.isTwitchConnected, "Twitch connected")
                        recapRow(viewModel.musicAuthorized, "Apple Music access granted")
                        recapRow(viewModel.playlistReady, "\(AppConstants.Music.requestsPlaylistName) created")
                        recapRow(hasSongListLink, hasSongListLink ? "!playlist link shared" : "Song list link (skipped)")
                    }
                    .padding(DSSpace.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .subtleCardShell()

                    Text("Turning this on enables song requests right away. You can switch it off whenever you like.")
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        )
    }

    /// Whether a `!playlist` share link is configured (drives the Done recap).
    private var hasSongListLink: Bool {
        !songListURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// One line in the Done-step recap: a filled check when done, a hollow circle
    /// when skipped or not yet satisfied.
    @ViewBuilder
    private func recapRow(_ done: Bool, _ text: String) -> some View {
        HStack(spacing: DSSpace.s2) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: DSFont.Size.body))
                .foregroundStyle(done ? DSColor.success : Color.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: DSFont.Size.body))
                .foregroundStyle(done ? .primary : .secondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(text), \(done ? "done" : "skipped")")
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack(spacing: DSSpace.s2) {
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .pointerCursor()
                .accessibilityIdentifier("songRequestSetup.cancel")

            Spacer()

            Button("Back") {
                navigationDirection = .leading
                viewModel.goToPreviousStep()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .pointerCursor()
            .opacity(viewModel.isFirstStep ? 0 : 1)
            .disabled(viewModel.isFirstStep)
            .accessibilityHidden(viewModel.isFirstStep)
            .accessibilityIdentifier("songRequestSetup.back")

            if viewModel.isLastStep {
                Button("Turn On Song Requests") {
                    viewModel.complete()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .pointerCursor()
                .accessibilityIdentifier("songRequestSetup.finish")
            } else {
                Button(nextButtonTitle) {
                    navigationDirection = .trailing
                    viewModel.goToNextStep()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .pointerCursor()
                .disabled(!viewModel.canAdvance)
                .accessibilityIdentifier("songRequestSetup.next")
            }
        }
        .transaction { $0.animation = nil }
    }

    /// On the optional share step the forward button reads "Skip" until a link
    /// is present, so it's obvious the step can be passed over.
    private var nextButtonTitle: String {
        if viewModel.currentStep == .shareLink {
            return songListURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Skip" : "Next"
        }
        return "Next"
    }

    // MARK: - Shared bits

    private var appleMusicTile: some View {
        BrandTile(
            background: AnyShapeStyle(
                LinearGradient(
                    colors: [AppConstants.Brand.appleMusicGradientStart, AppConstants.Brand.appleMusicGradientEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            ),
            glowColor: AppConstants.Brand.appleMusicGradientEnd,
            glyph: Image(systemName: "music.note")
                .font(BrandTileGlyph.font)
                .foregroundStyle(.white)
        )
    }

    /// One numbered step in the share flow: glyph, instruction, trailing action.
    @ViewBuilder
    private func setupStep<Trailing: View>(
        _ number: Int,
        _ text: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: DSSpace.s3) {
            Image(systemName: "\(number).circle.fill")
                .font(.system(size: DSFont.Size.lg))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: DSFont.Size.body))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DSSpace.s2)
            trailing()
        }
    }

    // MARK: - Actions

    private func refreshTwitchState() {
        viewModel.isTwitchConnected = appDelegate?.twitchService?.currentlyConnected ?? false
    }

    private func syncAuth(_ status: MusicAuthorization.Status) {
        musicAuthStatus = status
        viewModel.musicAuthorized = status == .authorized
    }

    private func requestMusicAuth() {
        isRequestingMusicAuth = true
        Task {
            _ = await MusicAuthorization.request()
            syncAuth(MusicAuthorization.currentStatus)
            isRequestingMusicAuth = false
        }
    }

    /// Ensures the WolfWave Requests playlist exists, flipping `playlistReady`
    /// so the step's Next button unlocks. Surfaces a retry on failure.
    @MainActor
    private func ensurePlaylist() async {
        ensuringPlaylist = true
        playlistError = nil
        defer { ensuringPlaylist = false }
        do {
            _ = try await libraryService.ensureRequestsPlaylist()
            viewModel.playlistReady = true
        } catch {
            viewModel.playlistReady = false
            playlistError = "Couldn't create the playlist. Check your Apple Music subscription, then try again."
        }
    }

    /// Resolves the playlist's public share link, fills the field, and turns
    /// `!playlist` on. A not-yet-public playlist resolves to a clear "do steps 1
    /// and 2 first" message. Same flow that used to live in the Commands card.
    @MainActor
    private func fetchSongListLink() async {
        fetchingLink = true
        fetchStatus = nil
        defer { fetchingLink = false }
        do {
            if let url = try await libraryService.resolveRequestsPlaylistShareURL() {
                songListURL = url
                songListCommandEnabled = true
                fetchStatus = "Got it. !playlist is on and shares this link."
            } else {
                fetchStatus = "Not public yet. Do steps 1 and 2, then Fetch again."
            }
        } catch {
            fetchStatus = "Couldn't fetch. Make sure you're signed in to Apple Music."
        }
    }

    /// Ensures the playlist exists, then reveals it in Music so the streamer can
    /// Share it (the one manual step macOS can't automate).
    @MainActor
    private func openPlaylistInMusic() async {
        _ = try? await libraryService.ensureRequestsPlaylist()
        musicController.revealRequestsPlaylist()
    }
}

// MARK: - Preview

#Preview("Intro") {
    SongRequestSetupView(startAt: .intro)
}

#Preview("Share link") {
    SongRequestSetupView(startAt: .shareLink)
}
