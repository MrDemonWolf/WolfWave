//
//  TwitchSettingsView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-01-08.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

// MARK: - Twitch Settings View

/// Settings panel for Twitch bot auth, channel connection, and account management.
///
/// Switches between sign-in, authorizing, connected, and error states
/// driven by ``TwitchViewModel/integrationState``.
struct TwitchSettingsView: View {
    /// The shared Twitch state manager driving this view.
    @Bindable var viewModel: TwitchViewModel
    /// Tracks whether the user has copied/opened the device code at least once.
    @State private var hasStartedActivation = false
    /// Whether the one-time keychain + service wiring has run for this view model instance.
    @State private var didLoadCredentials = false
    /// Global "commands only while live" switch. Applies to every chat command.
    @AppStorage(AppConstants.UserDefaults.commandsLiveOnly)
    private var commandsLiveOnly = false

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            headerView

            authCard
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(
                    DSMotion.Spring.snappy,
                    value: (viewModel.credentialsSaved || viewModel.channelConnected
                        || viewModel.authState.isInProgress))

            chatCommandsCard
        }
        .onAppear {
            // Keychain reads + AppDelegate wiring run once per view model instance.
            // Re-entering the Twitch settings pane shouldn't repeat them. TwitchViewModel
            // is owned by the parent SettingsView and survives section switches.
            guard !didLoadCredentials else { return }
            didLoadCredentials = true

            // Defer the @Observable mutations past the current SwiftUI view-update
            // tick. Mutating `botUsername`, `oauthToken`, `credentialsSaved`,
            // `channelID`, `reauthNeeded`, `channelConnected` inline during
            // `onAppear` re-invalidates the header + auth-card body that already
            // depend on them, which races AppKit layout and triggers the
            // `layoutSubtreeIfNeeded on a view which is already being laid out`
            // recursion that has been associated with the post-onboarding hang.
            Task { @MainActor in
                Log.debug("TwitchSettingsView: onAppear first-mount, loading credentials", category: "Twitch")
                viewModel.loadSavedCredentials()

                if viewModel.twitchService == nil {
                    if let appDelegate = AppDelegate.shared {
                        viewModel.twitchService = appDelegate.twitchService
                        if viewModel.twitchService == nil {
                            Log.error(
                                "TwitchSettingsView: AppDelegate.twitchService is nil!",
                                category: "Twitch")
                        }
                    } else {
                        Log.error("TwitchSettingsView: AppDelegate.shared is nil", category: "Twitch")
                    }
                }

                if let svc = viewModel.twitchService {
                    viewModel.channelConnected = svc.isConnectedSnapshot.value
                }

                if viewModel.reauthNeeded && viewModel.channelConnected {
                    viewModel.leaveChannel()
                }
            }
        }
    }

    // MARK: - Subviews

    /// Section header showing "Twitch" title, subtitle, and a colored status chip.
    private var headerView: some View {
        SectionHeaderWithStatus(
            title: "Twitch",
            subtitle: "Let people use chat commands to see what's playing.",
            statusText: viewModel.statusChipText,
            statusColor: viewModel.statusChipColor
        )
    }

    /// Global "commands only while live" switch. Applies to every chat command
    /// (`!song`, `!last`, `!stats`, `!sr`, `!queue`, …) in one place.
    private var chatCommandsCard: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            CardEyebrowHeader("Chat commands", systemImage: "bubble.left.and.bubble.right")

            ToggleSettingRow(
                title: "Only reply while live",
                subtitle: commandsLiveOnly
                    ? "Every chat command stays quiet until you go live."
                    : "Chat commands reply anytime, live or not.",
                isOn: $commandsLiveOnly,
                accessibilityLabel: "Toggle replying to chat commands only while live",
                accessibilityIdentifier: "commandsLiveOnlyToggle"
            )
        }
        .padding(AppConstants.SettingsUI.cardPadding)
        .cardStyleUnpadded()
    }

    /// Title text for the auth card header, adapts to reauth/signed-in/signed-out states.
    private var authCardHeaderTitle: String {
        if viewModel.reauthNeeded {
            return "Sign in again"
        } else if viewModel.credentialsSaved && viewModel.botUsername != "" {
            return "All set"
        } else if viewModel.authState.isInProgress {
            return "Authorize WolfWave with Twitch"
        } else {
            return "Connect WolfWave to your Twitch account"
        }
    }

    /// Subtitle text for the auth card header with a short call-to-action.
    private var authCardHeaderSubtitle: String {
        if viewModel.reauthNeeded {
            return "Your sign-in expired. Reconnect to keep chat commands working."
        } else if viewModel.credentialsSaved && viewModel.botUsername != "" {
            return ""
        } else if viewModel.authState.isInProgress {
            return "Enter the code below at twitch.tv/activate to finish signing in."
        } else {
            return "Sign in so WolfWave can post chat commands and read redemptions."
        }
    }

    /// Main card that switches content based on integration state.
    ///
    /// Shows one of: sign-in button, device-code flow, connected controls, or error retry.
    @ViewBuilder
    private var authCard: some View {
        switch viewModel.integrationState {
        case .connected:
            // `SignedInView` is already a full card (own header rows + single
            // border). Wrapping it in the outer `.cardStyle()` shell would draw
            // a second outline around it, so the connected state stands alone
            // with one outline, matching the Bot Commands cards below.
            connectedContent
                .animation(.easeInOut(duration: DSMotion.Duration.base), value: viewModel.integrationState)
        default:
            VStack(spacing: DSSpace.s5) {
                // Card header is always present for non-connected states so the
                // card never collapses its top section mid-transition.
                VStack(alignment: .leading, spacing: DSSpace.s0) {
                    Text(authCardHeaderTitle)
                        .font(.system(size: DSFont.Size.base, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)

                    Text(authCardHeaderSubtitle)
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)

                // Main content switches by integration state. Card sizes to fit
                // each state. The outer `.animation` interpolates height when the
                // device-code panel drops in or back out.
                Group {
                    switch viewModel.integrationState {
                    case .notConnected:
                        notConnectedContent
                    case .authorizing:
                        authorizingContent
                    case .error(let message):
                        errorContent(message: message)
                    case .connected:
                        EmptyView()  // Handled by the standalone branch above.
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .cardStyle()
            .animation(.easeInOut(duration: DSMotion.Duration.base), value: viewModel.integrationState)
        }
    }

    // MARK: - State Content Subviews

    /// Sign-in CTA shown when no token is stored.
    private var notConnectedContent: some View {
        VStack(spacing: DSSpace.s4) {
            Button(action: {
                hasStartedActivation = false
                viewModel.startOAuth()
            }) {
                HStack(spacing: DSSpace.s2) {
                    Image("TwitchLogo")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                        .foregroundStyle(.white)
                    Text("Connect with Twitch")
                        .font(.system(size: DSFont.Size.base, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .pointerCursor()
            .scaleEffect(viewModel.authState.isInProgress ? 0.995 : 1.0)
            .animation(
                .easeInOut(duration: DSMotion.Duration.fast),
                value: viewModel.authState.isInProgress
            )
            .accessibilityLabel("Connect with Twitch")
            .accessibilityHint("Starts the Twitch authorization flow")
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Device-code flow with copy + cancel affordances.
    private var authorizingContent: some View {
        VStack(spacing: DSSpace.s4) {
            if case .waitingForAuth(let code, let uri) = viewModel.authState {
                DeviceCodeView(
                    userCode: code, verificationURI: uri,
                    onCopy: {
                        viewModel.statusMessage = "Code copied"
                        hasStartedActivation = true
                    },
                    onActivate: {
                        hasStartedActivation = true
                    }
                )
                // Symmetric transition (same shape in and out) so the card
                // doesn't snap on dismissal.
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(DSMotion.Spring.snappy, value: viewModel.authState.userCode)
            }

            // Always-visible spinner + cancel row once device code is shown
            HStack(spacing: DSSpace.s2) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)

                Text("Waiting for you to approve on Twitch\u{2026}")
                    .font(.system(size: DSFont.Size.base))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel") {
                    viewModel.cancelOAuth()
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
                .pointerCursor()
                .accessibilityLabel("Cancel authorization")
                .accessibilityHint("Stops the Twitch sign-in process")
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Signed-in dashboard with bot + channel + actions.
    private var connectedContent: some View {
        SignedInView(
            botUsername: viewModel.botUsername,
            channelID: $viewModel.channelID,
            isChannelConnected: viewModel.channelConnected,
            isConnecting: viewModel.isConnecting,
            reauthNeeded: viewModel.reauthNeeded,
            credentialsSaved: viewModel.credentialsSaved,
            channelValidationState: viewModel.channelValidationState,
            testAuthResult: viewModel.testAuthResult,
            onReauth: { viewModel.clearAuthOnly(); viewModel.startOAuth() },
            onClearCredentials: { viewModel.clearCredentials() },
            onJoinChannel: { viewModel.joinChannel() },
            onLeaveChannel: { viewModel.leaveChannel() },
            onChannelIDChanged: { viewModel.saveChannelID() },
            onTestConnection: { viewModel.testConnection() }
        )
        .transition(.opacity)
    }

    /// Error message + retry CTA.
    private func errorContent(message: String) -> some View {
        VStack(spacing: DSSpace.s2) {
            Text(message)
                .font(.system(size: DSFont.Size.base))
                .foregroundStyle(.red)
            HStack {
                Button("Retry") { viewModel.startOAuth() }
                    .buttonStyle(.bordered)
                    .pointerCursor()
                    .accessibilityLabel("Retry Twitch authorization")
                    .accessibilityHint("Tries the Twitch sign-in process again")
                Spacer()
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - Sub-Views

/// View displayed when the user is signed in, showing bot info and channel controls.
private struct SignedInView: View {
    @AppStorage(AppConstants.UserDefaults.streamerModeEnabled)
    private var streamerMode = false

    let botUsername: String
    @Binding var channelID: String
    let isChannelConnected: Bool
    let isConnecting: Bool
    let reauthNeeded: Bool
    let credentialsSaved: Bool
    let channelValidationState: TwitchViewModel.ChannelValidationState
    let testAuthResult: TwitchViewModel.TestAuthResult
    var onReauth: () -> Void
    var onClearCredentials: () -> Void
    var onJoinChannel: () -> Void
    var onLeaveChannel: () -> Void
    var onChannelIDChanged: () -> Void
    var onTestConnection: () -> Void
    @State private var showingDisconnectConfirmation = false

    /// Shared height for every button in the action row. Pinning all of them to
    /// one value keeps Join/Leave, Test Login, and Log Out visually aligned.
    /// without it, the taller `checkmark.circle.fill` glyph makes the connect
    /// button a hair taller than its neighbors.
    private static let actionButtonHeight: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            botAccountSection
            Divider()
                .padding(.leading, AppConstants.SettingsUI.cardPadding)
            channelSection
            Divider()
                .padding(.leading, AppConstants.SettingsUI.cardPadding)
            actionButtonsSection
            Divider()
                .padding(.leading, AppConstants.SettingsUI.cardPadding)
            logOutSection
        }
        .cardStyleUnpadded()
    }

    // MARK: - Sections

    /// Signed-in Twitch username, masked under Streamer Mode so it is safe on
    /// camera. Empty stays "Not set" so the empty state still reads clearly.
    private var displayUsername: String {
        guard !botUsername.isEmpty else { return "Not set" }
        return StreamerMode.mask(botUsername, style: .channel, isOn: streamerMode)
    }

    /// Row showing the signed-in Twitch username and a status icon.
    private var botAccountSection: some View {
        HStack(alignment: .center, spacing: DSSpace.s4) {
            VStack(alignment: .leading, spacing: DSSpace.s0) {
                Text("Twitch Account")
                    .font(.system(size: DSFont.Size.sm, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(displayUsername)
                    .font(.system(size: DSFont.Size.base, weight: .semibold))
            }
            Spacer()
            statusIcon(reauthNeeded: reauthNeeded)
        }
        .padding(.horizontal, AppConstants.SettingsUI.cardPadding)
        .padding(.vertical, DSSpace.s4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Twitch account: \(displayUsername)")
        .accessibilityValue(reauthNeeded ? "Sign-in expired" : "Signed in")
    }

    /// Row with the channel name input field (or label when connected) and validation indicator.
    private var channelSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: DSSpace.s4) {
                VStack(alignment: .leading, spacing: DSSpace.s0) {
                    Text("Channel")
                        .font(.system(size: DSFont.Size.sm, weight: .medium))
                        .foregroundStyle(.secondary)
                    channelInputView
                }
                Spacer()
                connectionIcon
            }

            channelValidationIndicator
                .animation(.easeInOut(duration: DSMotion.Duration.base), value: channelValidationState)
        }
        .padding(.horizontal, AppConstants.SettingsUI.cardPadding)
        .padding(.vertical, DSSpace.s4)
    }

    /// Small inline indicator below the channel field showing validation progress or result.
    @ViewBuilder
    private var channelValidationIndicator: some View {
        switch channelValidationState {
        case .idle:
            EmptyView()
        case .validating:
            HStack(spacing: DSSpace.s1h) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
                Text("Verifying channel...")
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, DSSpace.s2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Verifying channel")
        case .valid:
            HStack(spacing: DSSpace.s1) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: DSFont.Size.sm))
                Text("Channel verified")
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.green)
            }
            .padding(.top, DSSpace.s2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Channel verified successfully")
        case .invalid:
            HStack(spacing: DSSpace.s1) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: DSFont.Size.sm))
                Text("Channel not found")
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.red)
            }
            .padding(.top, DSSpace.s2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Channel not found")
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
            .padding(.top, DSSpace.s2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Couldn't check channel: \(message)")
        }
    }

    /// Either a read-only label (when connected or reauth needed) or an editable text field.
    @ViewBuilder
    private var channelInputView: some View {
        switch (isChannelConnected, reauthNeeded) {
        case (true, _):
            HStack(spacing: DSSpace.s2) {
                Text(channelID.isEmpty ? "Not set" : StreamerMode.mask(channelID, style: .channel, isOn: streamerMode))
                    .font(.system(size: DSFont.Size.base, weight: .semibold))
                if !channelID.isEmpty {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.blue)
                        .font(.system(size: DSFont.Size.base))
                        .accessibilityLabel("Verified channel")
                }
                if streamerMode { StreamerModeBadge() }
            }
        case (false, true):
            HStack(spacing: DSSpace.s2) {
                Text(channelID.isEmpty ? "Not set" : StreamerMode.mask(channelID, style: .channel, isOn: streamerMode))
                    .font(.system(size: DSFont.Size.base, weight: .semibold))
                    .foregroundStyle(.secondary)
                if streamerMode { StreamerModeBadge() }
            }
        case (false, false):
            if streamerMode {
                HStack(spacing: DSSpace.s2) {
                    Text(channelID.isEmpty ? "Not set" : StreamerMode.mask(channelID, style: .channel, isOn: true))
                        .font(.system(size: DSFont.Size.base, weight: .semibold))
                        .foregroundStyle(.secondary)
                    StreamerModeBadge()
                }
            } else {
                TextField("Channel Name", text: $channelID)
                    .font(.system(size: DSFont.Size.base))
                    .textFieldStyle(.plain)
                    .disabled(isConnecting)
                    .accessibilityLabel("Twitch channel name")
                    .accessibilityHint("Enter your Twitch channel name")
                    .accessibilityIdentifier("twitchChannelTextField")
                    .onSubmit {
                        if !shouldDisableConnectButton {
                            onJoinChannel()
                        }
                    }
                    .onChange(of: channelID) { oldValue, newValue in
                        let sanitized = newValue.lowercased().trimmingCharacters(
                            in: CharacterSet.whitespacesAndNewlines)
                        if sanitized != newValue {
                            channelID = sanitized
                        }
                        if oldValue.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                            != sanitized
                        {
                            onChannelIDChanged()
                        }
                    }
            }
        }
    }

    /// Wi-Fi icon reflecting current channel connection state.
    @ViewBuilder
    private var connectionIcon: some View {
        switch (isChannelConnected, reauthNeeded) {
        case (true, _):
            Image(systemName: "wifi")
                .foregroundStyle(.green)
                .font(.system(size: DSFont.Size.md))
                .accessibilityLabel("Connected to channel")
        case (false, true):
            Image(systemName: "wifi.slash")
                .foregroundStyle(.orange)
                .font(.system(size: DSFont.Size.md))
                .accessibilityLabel("Disconnected, sign-in expired")
        case (false, false):
            EmptyView()
        }
    }

    /// Bottom row with Connect/Disconnect, Test Login, and Log Out buttons.
    private var actionButtonsSection: some View {
        HStack(spacing: DSSpace.s3) {
            if reauthNeeded {
                Button(action: onReauth) {
                    Label("Reconnect with Twitch", systemImage: "arrow.clockwise.circle.fill")
                        .font(.system(size: DSFont.Size.body, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .controlSize(.small)
                .frame(height: Self.actionButtonHeight)
                .pointerCursor()
                .accessibilityLabel("Reconnect with Twitch")
                .accessibilityHint("Clears credentials and starts a new sign-in")
                .accessibilityIdentifier("twitchReauthButton")
            } else {
                Button(action: {
                    if isChannelConnected {
                        showingDisconnectConfirmation = true
                    } else {
                        onJoinChannel()
                    }
                }) {
                    if isConnecting {
                        HStack(spacing: DSSpace.s1h) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.mini)
                            Text("Connecting\u{2026}")
                                .font(.system(size: DSFont.Size.body))
                        }
                    } else {
                        Label(
                            isChannelConnected ? "Leave Channel" : "Join Channel",
                            systemImage: isChannelConnected
                                ? "xmark.circle.fill" : "checkmark.circle.fill"
                        )
                        .font(.system(size: DSFont.Size.body, weight: .medium))
                        .foregroundStyle(isChannelConnected ? DSColor.error : Color.primary)
                    }
                }
                .disabled(shouldDisableConnectButton)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .stableWidth {
                    Label("Connect", systemImage: "checkmark.circle.fill")
                        .font(.system(size: DSFont.Size.body, weight: .medium))
                    Label("Disconnect", systemImage: "xmark.circle.fill")
                        .font(.system(size: DSFont.Size.body, weight: .medium))
                    HStack(spacing: DSSpace.s1h) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.mini)
                        Text("Connecting...")
                            .font(.system(size: DSFont.Size.body))
                    }
                }
                .frame(height: Self.actionButtonHeight)
                .pointerCursor()
                .accessibilityLabel(
                    isChannelConnected ? "Leave channel" : "Join channel"
                )
                .accessibilityHint(
                    isChannelConnected ? "Removes the bot from the Twitch channel" : "Adds the bot to the Twitch channel"
                )
                .accessibilityValue(isChannelConnected ? "Connected" : "Disconnected")
                .accessibilityIdentifier("twitchConnectButton")

                Button(action: onTestConnection) {
                    switch testAuthResult {
                    case .idle:
                        Label("Test Login", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.system(size: DSFont.Size.body, weight: .medium))
                    case .testing:
                        HStack(spacing: DSSpace.s1h) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.mini)
                            Text("Testing...")
                                .font(.system(size: DSFont.Size.body))
                        }
                    case .success:
                        Label("Passed", systemImage: "checkmark.circle.fill")
                            .font(.system(size: DSFont.Size.body, weight: .medium))
                    case .failure:
                        Label("Failed", systemImage: "xmark.circle.fill")
                            .font(.system(size: DSFont.Size.body, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .tint(testAuthButtonTint)
                .controlSize(.small)
                .stableWidth {
                    Label("Test Login", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.system(size: DSFont.Size.body, weight: .medium))
                    HStack(spacing: DSSpace.s1h) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.mini)
                        Text("Testing...")
                            .font(.system(size: DSFont.Size.body))
                    }
                    Label("Passed", systemImage: "checkmark.circle.fill")
                        .font(.system(size: DSFont.Size.body, weight: .medium))
                    Label("Failed", systemImage: "xmark.circle.fill")
                        .font(.system(size: DSFont.Size.body, weight: .medium))
                }
                .disabled(testAuthResult == .testing)
                .frame(height: Self.actionButtonHeight)
                .pointerCursor()
                .animation(.easeInOut(duration: DSMotion.Duration.base), value: testAuthResult)
                .help("Checks if your Twitch sign-in is working")
                .accessibilityLabel("Test Twitch sign-in")
                .accessibilityHint("Checks if your Twitch sign-in is working")
                .accessibilityValue(
                    testAuthResult == .success ? "Passed" :
                    testAuthResult == .failure ? "Failed" :
                    testAuthResult == .testing ? "Testing" : "Not tested"
                )
                .accessibilityIdentifier("twitchTestConnectionButton")
            }

            Spacer()
        }
        .padding(.horizontal, AppConstants.SettingsUI.cardPadding)
        .padding(.vertical, DSSpace.s4)
        .confirmationDialog(
            "Disconnect from channel?", isPresented: $showingDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                onLeaveChannel()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will disconnect the bot from the current channel but keep you logged in.")
        }
    }

    /// Quiet sign-out row, kept on its own line below the everyday Join/Test
    /// actions so the destructive Log Out never shares a row with the reversible
    /// channel and test controls.
    private var logOutSection: some View {
        HStack(alignment: .center, spacing: DSSpace.s4) {
            VStack(alignment: .leading, spacing: DSSpace.s0) {
                Text("Sign out")
                    .font(.system(size: DSFont.Size.sm, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Removes chat commands until you reconnect.")
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("Log Out", action: onClearCredentials)
                .font(.system(size: DSFont.Size.body))
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
                .frame(height: Self.actionButtonHeight)
                .pointerCursor()
                .accessibilityLabel("Clear saved Twitch credentials")
                .accessibilityHint("Signs out of your Twitch account")
                .accessibilityIdentifier("twitchClearCredentialsButton")
        }
        .padding(.horizontal, AppConstants.SettingsUI.cardPadding)
        .padding(.vertical, DSSpace.s4)
    }

    /// Tint color for the Test Login button based on its result state.
    private var testAuthButtonTint: Color? {
        switch testAuthResult {
        case .idle, .testing: return nil
        case .success: return .green
        case .failure: return .red
        }
    }

    /// Whether the Connect button should be grayed out (missing channel name or still connecting).
    private var shouldDisableConnectButton: Bool {
        let validChannel = !channelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isConnecting { return true }
        // If credentials are saved we can attempt to connect even if the
        // bot username hasn't been resolved yet, rely on saved token.
        if credentialsSaved {
            return !validChannel
        }
        return botUsername.isEmpty || !validChannel
    }

    /// Builds the connection-status SF Symbol (orange exclamation for
    /// re-auth needed, green checkmark otherwise).
    ///
    /// - Parameter reauthNeeded: When `true`, returns the warning icon.
    /// - Returns: A pre-sized status icon view.
    @ViewBuilder
    private func statusIcon(reauthNeeded: Bool) -> some View {
        Image(systemName: reauthNeeded ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
            .foregroundStyle(reauthNeeded ? .orange : .green)
            .font(.system(size: DSFont.Size.md))
    }
}

// MARK: - Preview

#Preview("Not Connected") {
    let mockViewModel: TwitchViewModel = {
        let vm = TwitchViewModel()
        vm.credentialsSaved = false
        vm.channelConnected = false
        return vm
    }()
    TwitchSettingsView(viewModel: mockViewModel)
        .padding()
        .frame(width: 700)
}

#Preview("Connected State") {
    let mockViewModel: TwitchViewModel = {
        let vm = TwitchViewModel()
        vm.botUsername = "MrDemonWolf"
        vm.channelID = "mrdemonwolf"
        vm.credentialsSaved = true
        vm.channelConnected = true
        vm.statusMessage = "Connected to mrdemonwolf"
        return vm
    }()
    TwitchSettingsView(viewModel: mockViewModel)
        .padding()
        .frame(width: 700)
}

#Preview("Authorizing State") {
    let mockViewModel: TwitchViewModel = {
        let vm = TwitchViewModel()
        vm.authState = .waitingForAuth(
            userCode: "ABCD-WXYZ",
            verificationURI: "https://www.twitch.tv/activate"
        )
        return vm
    }()
    TwitchSettingsView(viewModel: mockViewModel)
        .padding()
        .frame(width: 700)
}

#Preview("Connected - Not Joined Channel") {
    let mockViewModel: TwitchViewModel = {
        let vm = TwitchViewModel()
        vm.botUsername = "MrDemonWolf"
        vm.channelID = ""
        vm.credentialsSaved = true
        vm.channelConnected = false
        return vm
    }()
    TwitchSettingsView(viewModel: mockViewModel)
        .padding()
        .frame(width: 700)
}

#Preview("Reauth Needed") {
    let mockViewModel: TwitchViewModel = {
        let vm = TwitchViewModel()
        vm.botUsername = "MrDemonWolf"
        vm.channelID = "mrdemonwolf"
        vm.credentialsSaved = true
        vm.channelConnected = false
        vm.reauthNeeded = true
        return vm
    }()
    TwitchSettingsView(viewModel: mockViewModel)
        .padding()
        .frame(width: 700)
}

#Preview("Error State") {
    let mockViewModel: TwitchViewModel = {
        let vm = TwitchViewModel()
        vm.authState = .error("Failed to authenticate. Please try again.")
        return vm
    }()
    TwitchSettingsView(viewModel: mockViewModel)
        .padding()
        .frame(width: 700)
}

#Preview("Validating Channel") {
    let mockViewModel: TwitchViewModel = {
        let vm = TwitchViewModel()
        vm.botUsername = "MrDemonWolf"
        vm.channelID = "mrdemonwolf"
        vm.credentialsSaved = true
        vm.channelConnected = false
        vm.channelValidationState = .validating
        return vm
    }()
    TwitchSettingsView(viewModel: mockViewModel)
        .padding()
        .frame(width: 700)
}

#Preview("Channel Verified") {
    let mockViewModel: TwitchViewModel = {
        let vm = TwitchViewModel()
        vm.botUsername = "MrDemonWolf"
        vm.channelID = "mrdemonwolf"
        vm.credentialsSaved = true
        vm.channelConnected = false
        vm.channelValidationState = .valid
        return vm
    }()
    TwitchSettingsView(viewModel: mockViewModel)
        .padding()
        .frame(width: 700)
}

#Preview("Channel Invalid") {
    let mockViewModel: TwitchViewModel = {
        let vm = TwitchViewModel()
        vm.botUsername = "MrDemonWolf"
        vm.channelID = "invalidchannel123"
        vm.credentialsSaved = true
        vm.channelConnected = false
        vm.channelValidationState = .invalid
        return vm
    }()
    TwitchSettingsView(viewModel: mockViewModel)
        .padding()
        .frame(width: 700)
}

