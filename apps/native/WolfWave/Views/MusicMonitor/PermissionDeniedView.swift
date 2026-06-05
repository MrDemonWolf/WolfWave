//
//  PermissionDeniedView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-07.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
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

    /// Brief recheck feedback so "Try again" never feels like a dead button.
    /// If access is granted the parent unmounts this whole card, so a lingering
    /// hint only ever means "still off".
    @State private var isRechecking = false
    @State private var showStillDenied = false

    var body: some View {
        HStack(alignment: .top, spacing: DSSpace.s7) {
            iconStack

            VStack(alignment: .leading, spacing: DSSpace.s2) {
                HStack(spacing: DSSpace.s2) {
                    Text("Let WolfWave read what's playing.")
                        .font(.system(size: DSFont.Size.lg, weight: .bold))
                        .lineLimit(2)

                    Image(systemName: "lock.fill")
                        .font(.system(size: DSFont.Size.body, weight: .semibold))
                        .foregroundStyle(DSColor.warning)
                        .accessibilityHidden(true)
                }

                Text("Turn on Music access and WolfWave can show your current track on Twitch, Discord, and your overlay. We only read what's playing, never play, pause, skip, or change your library.")
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

                    Button("Show me how", action: onShowInstructions)
                        .buttonStyle(.bordered)
                        .controlSize(.regular)

                    tryAgainButton

                    Spacer(minLength: 0)
                }
                .padding(.top, DSSpace.s1)

                if showStillDenied {
                    Label(
                        "Still off. In Automation, turn on Music under WolfWave.",
                        systemImage: "info.circle"
                    )
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
                }
            }
        }
        .padding(DSSpace.s7)
        .cardStyleUnpadded()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Music access denied. Open System Settings to grant Automation access for the Music app.")
    }

    /// "Try again" recheck with an inline spinner plus a transient "still off"
    /// hint, so the button always acknowledges the tap even when nothing changed.
    @ViewBuilder
    private var tryAgainButton: some View {
        Button {
            guard !isRechecking else { return }
            withAnimation(.easeInOut(duration: DSMotion.Duration.fast)) {
                isRechecking = true
                showStillDenied = false
            }
            onTryAgain()
            Task {
                // Give the off-main permission probe a beat to resolve. A grant
                // unmounts this card; if we're still here afterwards it's denied.
                try? await Task.sleep(nanoseconds: 700_000_000)
                withAnimation(.easeInOut(duration: DSMotion.Duration.base)) {
                    isRechecking = false
                    showStillDenied = true
                }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                withAnimation(.easeInOut(duration: DSMotion.Duration.base)) {
                    showStillDenied = false
                }
            }
        } label: {
            HStack(spacing: DSSpace.s1) {
                if isRechecking {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                }
                Text("Try again")
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .disabled(isRechecking)
        .accessibilityLabel("Try again")
        .accessibilityHint("Rechecks whether Apple Music access is now on")
    }

    /// Flat tinted circle + SF Symbol, matching the macOS System Settings
    /// Privacy pane idiom. No gradient, drop shadow, or floating badge. The
    /// locked state is carried by the title-row glyph and the copy instead.
    @ViewBuilder
    private var iconStack: some View {
        ZStack {
            Circle()
                .fill(DSColor.warning.opacity(0.12))
            Image(systemName: "music.note")
                .font(.system(size: DSFont.Size.x2xl, weight: .semibold))
                .foregroundStyle(DSColor.warning)
        }
        .frame(width: 52, height: 52)
    }
}

// MARK: - Instruction sheet (State 2)

/// Modal sheet walking the user through Privacy & Security → Automation.
/// Reached from "Show me how" on the banner.
struct PermissionInstructionSheet: View {

    @Environment(\.dismiss) private var dismiss
    var onOpenSystemSettings: () -> Void
    var onTryAgain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: DSSpace.s4) {
                ZStack {
                    RoundedRectangle(cornerRadius: DSRadius.lg2, style: .continuous)
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
                Button("Try Again") {
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
                .sectionEyebrow()

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
        .cardStyleUnpadded()
    }

    @ViewBuilder
    private var wolfMark: some View {
        if let _ = NSImage(named: "AppIcon") {
            Image("AppIcon")
                .resizable()
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.xs))
        } else {
            RoundedRectangle(cornerRadius: DSRadius.xs)
                .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 20, height: 20)
        }
    }

    @ViewBuilder
    private var appleMusicMark: some View {
        RoundedRectangle(cornerRadius: DSRadius.xs)
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
                RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: DSFont.Size.x2xl, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: DSSpace.s0) {
                Text("Paused until Music access is on")
                    .font(.system(size: DSFont.Size.md, weight: .semibold))
                Text("Your current track lands here the moment you turn it on above.")
                    .font(.system(size: DSFont.Size.body))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            StatusChip(text: "Paused", color: .orange)
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
