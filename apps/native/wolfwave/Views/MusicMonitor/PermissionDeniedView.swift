//
//  PermissionDeniedView.swift
//  wolfwave
//

import SwiftUI
import AppKit

// MARK: - Inline banner (State 1)

/// Inline "Music access denied" banner shown at the top of the General tab.
/// Hosts the primary "Open System Settings" CTA and a "Try again" recheck.
struct PermissionDeniedBanner: View {

    var onOpenSystemSettings: () -> Void
    var onTryAgain: () -> Void
    var onShowInstructions: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            iconStack

            VStack(alignment: .leading, spacing: DSSpace.s2) {
                Text("Let WolfWave read what's playing.")
                    .font(.system(size: DSFont.Size.x18, weight: .bold))
                    .lineLimit(2)

                Text("We need permission to read from the Music app so we can see the current track, artist, and album. We never play, pause, skip, or change your library.")
                    .font(.system(size: DSFont.Size.body))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: DSSpace.s2) {
                    Button(action: onOpenSystemSettings) {
                        HStack(spacing: DSSpace.s1) {
                            Text("Open System Settings")
                            Image(systemName: "chevron.right")
                                .font(.system(size: DSFont.Size.xs, weight: .semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)

                    Button("Try again", action: onTryAgain)
                        .buttonStyle(.bordered)
                        .controlSize(.regular)

                    Button("Show instructions", action: onShowInstructions)
                        .buttonStyle(.borderless)
                        .controlSize(.small)

                    Spacer(minLength: 0)

                    StatusChip(text: "Music access denied", color: .red)
                }
                .padding(.top, DSSpace.s1)
            }
        }
        .padding(DSSpace.s7)
        .cardStyleUnpadded()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Music access denied. Open System Settings to grant Automation access for the Music app.")
    }

    @ViewBuilder
    private var iconStack: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(
                        colors: [
                            AppConstants.Brand.appleMusicSurfaceEnd,
                            AppConstants.Brand.appleMusicSurfaceStart
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                Image(systemName: "music.note")
                    .font(.system(size: DSFont.Size.x36, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 80, height: 80)
            .shadow(color: AppConstants.Brand.appleMusicSurfaceEnd.opacity(0.30), radius: 14, x: 0, y: 12)

            Circle()
                .fill(Color.red)
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "lock.fill")
                        .font(.system(size: DSFont.Size.md, weight: .bold))
                        .foregroundStyle(.white)
                )
                .overlay(Circle().stroke(.background, lineWidth: 2.5))
                .offset(x: 6, y: 6)
        }
        .frame(width: 86, height: 86)
    }
}

// MARK: - Instruction sheet (State 2)

/// Modal sheet walking the user through Privacy & Security → Automation.
/// Reached from "Show instructions" on the banner.
struct PermissionInstructionSheet: View {

    @Environment(\.dismiss) private var dismiss
    var onOpenSystemSettings: () -> Void
    var onTryAgain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: DSSpace.s4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(
                            colors: [
                                AppConstants.Brand.appleMusicSurfaceEnd,
                                AppConstants.Brand.appleMusicSurfaceStart
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    Image(systemName: "music.note")
                        .font(.system(size: DSFont.Size.x2xl, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: DSSpace.s0) {
                    Text("Grant access to Music")
                        .font(.system(size: DSFont.Size.lg, weight: .bold))
                    Text("Three steps · takes about ten seconds")
                        .font(.system(size: DSFont.Size.body))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: DSSpace.s4) {
                step(n: 1) {
                    Text("Click \(Text("Open System Settings").bold()) below.")
                }
                step(n: 2) {
                    Text("In \(Text("Privacy & Security → Automation").bold()), find \(Text("WolfWave").bold()) and turn on \(Text("Music").bold()).")
                }
                step(n: 3) {
                    Text("Come back here. WolfWave will pick up the next track automatically.")
                }
            }

            AutomationRowPreview()

            Spacer()

            HStack(spacing: DSSpace.s2) {
                Button("Not now") { dismiss() }
                    .buttonStyle(.borderless)
                Spacer()
                Button("Try again") {
                    onTryAgain()
                }
                .buttonStyle(.bordered)

                Button {
                    onOpenSystemSettings()
                } label: {
                    Text("Open System Settings")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, DSSpace.s2)
        }
        .padding(DSSpace.s9)
        .frame(width: 480, height: 520)
    }

    /// Builds a single numbered "step" row: a circled index plus instruction text.
    ///
    /// - Parameters:
    ///   - n: 1-based step number shown inside the circle.
    ///   - content: ViewBuilder closure returning the instruction `Text`.
    /// - Returns: A horizontally-aligned step row.
    private func step(n: Int, @ViewBuilder content: () -> Text) -> some View {
        HStack(alignment: .top, spacing: DSSpace.s4) {
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                Text("\(n)")
                    .font(.system(size: DSFont.Size.sm, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 22, height: 22)

            content()
                .font(.system(size: DSFont.Size.base))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Automation row preview

/// Mini visual of the System Settings → Automation row the user is told to flip.
/// Helps them recognize it once they get there.
struct AutomationRowPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s2) {
            Text("System Settings → Privacy & Security → Automation")
                .font(.system(size: DSFont.Size.xs, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(0.6)

            HStack(spacing: DSSpace.s3) {
                wolfMark
                Text("WolfWave").font(.system(size: DSFont.Size.base, weight: .semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: DSFont.Size.xs, weight: .semibold))
                    .foregroundStyle(.tertiary)
                appleMusicMark
                Text("Music").font(.system(size: DSFont.Size.base))
                Spacer()
                Capsule()
                    .fill(.quaternary)
                    .frame(width: 36, height: 20)
                    .overlay(alignment: .leading) {
                        Circle()
                            .fill(.white)
                            .frame(width: 16, height: 16)
                            .padding(DSSpace.s0)
                            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    }
            }
        }
        .padding(DSSpace.s4)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
    }

    @ViewBuilder
    private var wolfMark: some View {
        if let _ = NSImage(named: "AppIcon") {
            Image("AppIcon")
                .resizable()
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 20, height: 20)
        }
    }

    @ViewBuilder
    private var appleMusicMark: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(LinearGradient(
                colors: [AppConstants.Brand.appleMusicPulseStart, AppConstants.Brand.appleMusicPulseEnd],
                startPoint: .top, endPoint: .bottom
            ))
            .frame(width: 20, height: 20)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: DSFont.Size.xs, weight: .bold))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - Empty Now Playing card (State 3)

/// Empty/disabled Now Playing card shown while permission is missing.
struct PermissionPausedNowPlayingCard: View {
    var body: some View {
        HStack(spacing: DSSpace.s5) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                            .foregroundStyle(.tertiary)
                    )
                Image(systemName: "lock.fill")
                    .font(.system(size: DSFont.Size.x2xl, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: DSSpace.s0) {
                Text("Waiting for Music permission")
                    .font(.system(size: DSFont.Size.md, weight: .semibold))
                Text("We can't see what's playing until you turn on Music in Automation.")
                    .font(.system(size: DSFont.Size.body))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            StatusChip(text: "Denied", color: .red)
        }
        .padding(DSSpace.s6)
        .cardStyleUnpadded()
    }
}

#Preview("Banner") {
    PermissionDeniedBanner(
        onOpenSystemSettings: {},
        onTryAgain: {},
        onShowInstructions: {}
    )
    .padding()
    .frame(width: 720)
    .background(Color(nsColor: .underPageBackgroundColor))
}

#Preview("Instruction sheet") {
    PermissionInstructionSheet(
        onOpenSystemSettings: {},
        onTryAgain: {}
    )
}

#Preview("Paused now playing") {
    PermissionPausedNowPlayingCard()
        .padding()
        .frame(width: 720)
}
