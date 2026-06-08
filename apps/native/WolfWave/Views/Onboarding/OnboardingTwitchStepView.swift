//
//  OnboardingTwitchStepView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-02-06.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Twitch connection step with branded tile, pill CTA, and reused `DeviceCodeView`
/// for the OAuth Device Code flow. Optional, can be skipped from the nav bar.
struct OnboardingTwitchStepView: View {

    // MARK: - Properties

    @Bindable var twitchViewModel: TwitchViewModel

    @State private var hasStartedActivation = false

    // MARK: - Body

    var body: some View {
        OnboardingStepScaffold(
            title: "Connect WolfWave to Twitch",
            description: "So !song works in your chat automatically. We only listen, we never post unless you ask.",
            icon: {
                BrandTile(
                    background: AnyShapeStyle(AppConstants.Brand.twitch),
                    glowColor: AppConstants.Brand.twitch,
                    glyph:
                        Image("TwitchLogo")
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: BrandTileGlyph.assetSize, height: BrandTileGlyph.assetSize)
                            .foregroundStyle(.white)
                )
            },
            extras: {
                Group {
                    switch twitchViewModel.integrationState {
                    case .notConnected:
                        notConnectedContent
                    case .authorizing:
                        authorizingContent
                    case .connected:
                        connectedContent
                    case .error(let message):
                        errorContent(message: message)
                    }
                }
                .animation(.easeInOut(duration: DSMotion.Duration.base), value: stateKey)
            }
        )
        .onAppear {
            twitchViewModel.loadSavedCredentials()
            if twitchViewModel.twitchService == nil {
                if let appDelegate = AppDelegate.shared {
                    twitchViewModel.twitchService = appDelegate.twitchService
                }
            }
            prefillChannelIfNeeded()
        }
        .onChange(of: twitchViewModel.botUsername) { _, _ in
            prefillChannelIfNeeded()
        }
    }

    // MARK: - States

    private var notConnectedContent: some View {
        VStack(spacing: 10) {
            PillButton(
                background: AnyShapeStyle(AppConstants.Brand.twitch),
                action: {
                    hasStartedActivation = false
                    twitchViewModel.startOAuth()
                },
                label: {
                    HStack(spacing: 8) {
                        Image("TwitchLogo")
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                            .foregroundStyle(.white)
                        Text("Connect with Twitch")
                    }
                }
            )
            .accessibilityLabel("Connect with Twitch")
            .accessibilityHint("Opens Twitch in your browser to authorize WolfWave")

            Text("Opens twitch.tv/activate in your browser. Takes about 10 seconds.")
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.tertiary)
        }
    }

    private var authorizingContent: some View {
        VStack(spacing: 12) {
            if case .waitingForAuth(let code, let uri) = twitchViewModel.authState {
                DeviceCodeView(
                    userCode: code,
                    verificationURI: uri,
                    onCopy: {
                        twitchViewModel.statusMessage = "Code copied"
                        hasStartedActivation = true
                    },
                    onActivate: {
                        hasStartedActivation = true
                    }
                )
            }

            HStack(spacing: 12) {
                LoadingRow(text: "Waiting for Twitch\u{2026}")

                Spacer()

                Button("Cancel") {
                    hasStartedActivation = false
                    twitchViewModel.cancelOAuth()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .pointerCursor()
                .accessibilityLabel("Cancel authorization")
            }
        }
    }

    private var connectedContent: some View {
        VStack(spacing: DSSpace.s4) {
            accountCard
            channelCard
        }
    }

    /// The "Connected as @bot" identity card with a Sign Out action.
    private var accountCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(DSColor.success)
                    .frame(width: 36, height: 36)
                    .shadow(color: DSColor.success.opacity(0.40), radius: 8, x: 0, y: 4)

                Image(systemName: "checkmark")
                    .font(.system(size: DSFont.Size.lg, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Connected")
                    .sectionEyebrow()

                Text("@\(twitchViewModel.botUsername)")
                    .font(.system(size: DSFont.Size.base, weight: .semibold))
            }

            Spacer()

            Button("Sign Out") {
                twitchViewModel.cancelOAuth()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .pointerCursor()
        }
        .padding(DSSpace.s5)
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Twitch connected as \(twitchViewModel.botUsername).")
    }

    /// Channel name field + Join button so the bot actually joins a chat.
    /// Once joined, collapses to a green "In #channel" confirmation row.
    @ViewBuilder
    private var channelCard: some View {
        VStack(alignment: .leading, spacing: DSSpace.s3) {
            if twitchViewModel.channelConnected {
                HStack(spacing: DSSpace.s2) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DSColor.success)
                        .font(.system(size: DSFont.Size.md))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("In your chat")
                            .sectionEyebrow()
                        Text("#\(twitchViewModel.channelID)")
                            .font(.system(size: DSFont.Size.base, weight: .semibold))
                    }
                    Spacer()
                    Button("Change") {
                        twitchViewModel.leaveChannel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .pointerCursor()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("WolfWave is in channel \(twitchViewModel.channelID).")
            } else {
                Text("Which channel should WolfWave join?")
                    .sectionEyebrow()

                HStack(spacing: DSSpace.s2) {
                    TextField("yourchannel", text: $twitchViewModel.channelID)
                        .font(.system(size: DSFont.Size.base))
                        .textFieldStyle(.roundedBorder)
                        .disabled(twitchViewModel.isConnecting)
                        .accessibilityLabel("Twitch channel name")
                        .accessibilityHint("Enter the channel WolfWave should join")
                        .onSubmit(joinChannelIfPossible)
                        .onChange(of: twitchViewModel.channelID) { oldValue, newValue in
                            let sanitized = newValue.lowercased()
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            if sanitized != newValue {
                                twitchViewModel.channelID = sanitized
                            }
                            if oldValue.lowercased()
                                .trimmingCharacters(in: .whitespacesAndNewlines) != sanitized {
                                twitchViewModel.saveChannelID()
                            }
                        }

                    Button(action: joinChannelIfPossible) {
                        if twitchViewModel.isConnecting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.small)
                        } else {
                            Text("Join")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .pointerCursor()
                    .disabled(joinDisabled)
                }

                channelValidationIndicator
                    .animation(
                        .easeInOut(duration: DSMotion.Duration.base),
                        value: twitchViewModel.channelValidationState)
            }
        }
        .padding(DSSpace.s5)
        .cardStyle()
    }

    /// Inline feedback below the channel field mirroring the settings pane.
    @ViewBuilder
    private var channelValidationIndicator: some View {
        switch twitchViewModel.channelValidationState {
        case .idle, .valid:
            EmptyView()
        case .validating:
            HStack(spacing: DSSpace.s1) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
                Text("Verifying channel\u{2026}")
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.secondary)
            }
        case .invalid:
            HStack(spacing: DSSpace.s1) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: DSFont.Size.sm))
                Text("Channel not found")
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.red)
            }
        case .error(let message):
            HStack(spacing: DSSpace.s1) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: DSFont.Size.sm))
                Text("Couldn't check channel")
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.orange)
                    .help(message)
            }
        }
    }

    /// Error-state subview shown when the Twitch device-code flow fails.
    /// Displays a warning icon plus a wrap-friendly explanation message.
    ///
    /// - Parameter message: Localized error string from the auth flow.
    @ViewBuilder
    private func errorContent(message: String) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: DSFont.Size.base))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DSSpace.s4)
            .cardStyle()

            Button("Try Again") {
                twitchViewModel.startOAuth()
            }
            .buttonStyle(.bordered)
            .pointerCursor()
        }
    }

    // MARK: - Helpers

    /// Whether the Join button should be disabled (empty channel or busy).
    private var joinDisabled: Bool {
        twitchViewModel.isConnecting
            || twitchViewModel.channelID
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Joins the typed channel if it's non-empty and no join is in flight.
    private func joinChannelIfPossible() {
        guard !joinDisabled else { return }
        twitchViewModel.joinChannel()
    }

    /// Seeds the channel field with the bot's own login as a sensible default,
    /// so a streamer using one account just clicks Join. Only fills when empty.
    private func prefillChannelIfNeeded() {
        guard twitchViewModel.channelID
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !twitchViewModel.botUsername.isEmpty
        else { return }
        twitchViewModel.channelID = twitchViewModel.botUsername
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        twitchViewModel.saveChannelID()
    }

    private var stateKey: Int {
        switch twitchViewModel.integrationState {
        case .notConnected: return 0
        case .authorizing: return 1
        case .connected: return 2
        case .error: return 3
        }
    }
}

// MARK: - Previews

#Preview("Not connected") {
    OnboardingTwitchStepView(twitchViewModel: TwitchViewModel())
        .frame(
            width: AppConstants.OnboardingUI.windowWidth,
            height: AppConstants.OnboardingUI.windowHeight
        )
}
