//
//  DebugUIPreviewsCard.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-16.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

#if DEBUG
import SwiftUI

/// DEBUG-only card for previewing in-app UI surfaces without normal triggers.
///
/// Includes shortcuts to the What's New popup, the onboarding wizard, and a
/// simulated update banner so designers can iterate without bumping versions.
struct DebugUIPreviewsCard: View {

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            Text("Trigger popups, banners, and onboarding without the usual gating.")
                .font(.system(size: DSFont.Size.body))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                AppDelegate.shared?.showWhatsNew()
            } label: {
                Label("Preview What's New Popup", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .pointerCursor()

            Button {
                UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.lastSeenWhatsNewVersion)
                Log.info("Reset lastSeenWhatsNewVersion (dev)", category: "WhatsNew")
            } label: {
                Label("Reset 'Seen' Flag (next launch shows popup)", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .pointerCursor()

            Divider().padding(.vertical, DSSpace.s1)

            Button {
                AppDelegate.shared?.showOnboarding()
            } label: {
                Label("Open Onboarding Wizard", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .pointerCursor()

            Button {
                UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.hasCompletedOnboarding)
                Log.info("Reset hasCompletedOnboarding (dev)", category: "Onboarding")
            } label: {
                Label("Reset Onboarding Completion Flag", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .pointerCursor()

            Divider().padding(.vertical, DSSpace.s1)

            Button {
                NotificationCenter.default.postUpdateState(
                    isUpdateAvailable: true,
                    latestVersion: "99.0.0"
                )
            } label: {
                Label("Simulate Update Available", systemImage: "arrow.down.app")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .pointerCursor()

            Divider().padding(.vertical, DSSpace.s1)

            MotionGallerySection()
        }
        .cardStyle()
    }
}

// MARK: - Motion Gallery

/// Visual gallery for the polished SwiftUI transitions added in the
/// Apple/SwiftUI modernization pass. Designers can verify `contentTransition`,
/// `symbolEffect`, `TimelineView`, and the `AsyncImage` phased loading without
/// triggering real Twitch/Discord state.
///
/// To validate Reduce Motion: flip System Settings → Accessibility → Reduce
/// Motion. The "Reduce Motion" chip in the section header mirrors the system
/// value, and every demo here respects it.
private struct MotionGallerySection: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var chipState: ChipDemoState = .off
    @State private var trackIndex: Int = 0
    @State private var elapsed: TimeInterval = 0
    // Neutral placeholder image (not real album art) so the AsyncImage phased
    // load is exercisable without shipping a third-party music artwork URL.
    @State private var artURL: URL? = URL(string: "https://picsum.photos/seed/wolfwave/512")
    @State private var cacheBuster: Int = 0
    @State private var isExpanded: Bool = false

    private enum ChipDemoState: CaseIterable {
        case off, connecting, live, error

        var text: String {
            switch self {
            case .off:        return "Off"
            case .connecting: return "Connecting…"
            case .live:       return "Live"
            case .error:      return "Error"
            }
        }

        var color: Color {
            switch self {
            case .off:        return .secondary
            case .connecting: return DSColor.warning
            case .live:       return DSColor.success
            case .error:      return DSColor.error
            }
        }

        func next() -> ChipDemoState {
            let all = ChipDemoState.allCases
            let i = all.firstIndex(of: self) ?? 0
            return all[(i + 1) % all.count]
        }
    }

    private struct DemoTrack {
        let title: String
        let artist: String
        let album: String
        let duration: TimeInterval
    }

    // Invented demo tracks: made-up titles/albums with real wolf species as the
    // "artist". Mirrors the marketing house style in
    // `apps/docs/app/(home)/_widgets/sample-tracks.ts` so no real recording
    // artist, song, or album ever ships in a preview.
    private static let demoTracks: [DemoTrack] = [
        DemoTrack(title: "Moonlit Howl",   artist: "Arctic Wolf",  album: "Tundra Sessions", duration: 218),
        DemoTrack(title: "Lone Runner",     artist: "Timber Wolf",  album: "Northern Pines",  duration: 247),
        DemoTrack(title: "Silver Pelt",     artist: "Gray Wolf",    album: "Den of Echoes",   duration: 191),
        DemoTrack(title: "Pack Mentality",  artist: "Maned Wolf",   album: "Wild Frontier",   duration: 263)
    ]

    private var currentTrack: DemoTrack {
        Self.demoTracks[trackIndex % Self.demoTracks.count]
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: DSSpace.s5) {
                reduceMotionMirror
                Divider()
                chipCycleDemo
                Divider()
                trackSwapDemo
                Divider()
                albumArtPhasedDemo
            }
            .padding(.top, DSSpace.s3)
        } label: {
            HStack(spacing: DSSpace.s1h) {
                Image(systemName: "wand.and.rays")
                    .foregroundStyle(.purple)
                Text("Motion Gallery")
                    .sectionHeader()
                Spacer()
            }
        }
    }

    // MARK: Reduce-motion mirror

    private var reduceMotionMirror: some View {
        HStack(spacing: DSSpace.s2) {
            Text("System setting:")
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.secondary)
            StatusChip(
                text: reduceMotion ? "Reduce Motion: On" : "Reduce Motion: Off",
                color: reduceMotion ? DSColor.warning : DSColor.success
            )
            Spacer()
        }
    }

    // MARK: Chip cycle

    private var chipCycleDemo: some View {
        VStack(alignment: .leading, spacing: DSSpace.s2) {
            Text("StatusChip: auto-cycles every 1.2s")
                .font(.system(size: DSFont.Size.sm, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: DSSpace.s4) {
                StatusChip(text: chipState.text, color: chipState.color)
                Button("Advance") {
                    chipState = chipState.next()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            // Structured .task loop advances the chip state every 1.2s and
            // auto-cancels when the card disappears (matches the other Debug
            // cards). A stored onAppear task would outlive the view and keep
            // mutating state for the process lifetime on every pane revisit.
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(1200))
                    guard !Task.isCancelled else { return }
                    chipState = chipState.next()
                }
            }
        }
    }

    // MARK: Track swap

    private var trackSwapDemo: some View {
        VStack(alignment: .leading, spacing: DSSpace.s2) {
            Text("NowPlayingHeroCard: title contentTransition + TimelineView scrubber")
                .font(.system(size: DSFont.Size.sm, weight: .semibold))
                .foregroundStyle(.secondary)

            NowPlayingHeroCard(
                track: currentTrack.title,
                artist: currentTrack.artist,
                album: currentTrack.album,
                elapsed: elapsed,
                duration: currentTrack.duration
            )

            HStack(spacing: DSSpace.s2) {
                Button("Next track") {
                    trackIndex += 1
                    elapsed = 0
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("+5s") {
                    elapsed = min(elapsed + 5, currentTrack.duration)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("-5s") {
                    elapsed = max(elapsed - 5, 0)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()
            }
        }
    }

    // MARK: AlbumArt phased load

    private var albumArtPhasedDemo: some View {
        VStack(alignment: .leading, spacing: DSSpace.s2) {
            Text("AlbumArtView: direct image vs URL phased load")
                .font(.system(size: DSFont.Size.sm, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: DSSpace.s5) {
                VStack(spacing: DSSpace.s1) {
                    AlbumArtView(size: 92)
                    Text("Branded fallback")
                        .font(.system(size: DSFont.Size.xs))
                        .foregroundStyle(.tertiary)
                }

                VStack(spacing: DSSpace.s1) {
                    AlbumArtView(url: bustedURL, size: 92)
                    Text("AsyncImage(url:)")
                        .font(.system(size: DSFont.Size.xs))
                        .foregroundStyle(.tertiary)
                }

                VStack(spacing: DSSpace.s2) {
                    Button("Bust cache & reload") {
                        cacheBuster += 1
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Text("Force a fresh AsyncImage request by changing the URL query.")
                        .font(.system(size: DSFont.Size.xs))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var bustedURL: URL? {
        guard let base = artURL,
              var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return artURL }
        comps.queryItems = [URLQueryItem(name: "v", value: String(cacheBuster))]
        return comps.url
    }
}

#Preview {
    DebugUIPreviewsCard()
        .padding()
        .frame(width: 600)
}
#endif
