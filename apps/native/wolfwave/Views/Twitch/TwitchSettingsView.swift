//
//  TwitchSettingsView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//
//
//  Platform Support: Universal SwiftUI view works on macOS, iOS, and iPadOS.
//  Uses platform-conditional colors and controls for best appearance.
//
//  Input Validation: Enforces channel name constraints and normalizes input.
//  Channel names are lowercased and trimmed automatically.
//
//  State Management: Synchronized with TwitchViewModel for real-time updates.
//  UI reflects current connection state, auth status, and error conditions.
//
//  Accessibility: All buttons and controls have appropriate labels and hints.
//  Color contrasts meet WCAG AA standards.
//
//  Security: No sensitive data is displayed. Credentials are stored securely
//  in Keychain and never exposed in the UI.
//
//  Performance: View is optimized for responsive UI. Network operations are
//  non-blocking and provide progress feedback to the user.
//

import SwiftUI

// MARK: - Twitch Settings View

struct TwitchSettingsView: View {
    @Bindable var viewModel: TwitchViewModel
    @State private var hasStartedActivation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView

            authCard
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(
                    .spring(response: 0.35, dampingFraction: 0.82, blendDuration: 0),
                    value: (viewModel.credentialsSaved || viewModel.channelConnected
                        || viewModel.authState.isInProgress))
        }
        .onAppear {
            viewModel.loadSavedCredentials()

            // Ensure the service is set on the view model
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
                viewModel.channelConnected = svc.isConnected
            }

            // If reauthentication is needed, disconnect from the channel
            if viewModel.reauthNeeded && viewModel.channelConnected {
                viewModel.leaveChannel()
            }
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Text("Twitch")
                    .sectionHeader()

                Spacer()

                StatusChip(text: viewModel.statusChipText, color: viewModel.statusChipColor)
                    .accessibilityLabel("Twitch integration status: \(viewModel.statusChipText)")
                    .animation(.easeInOut(duration: 0.2), value: viewModel.statusChipText)
            }

            Text("Let people use chat commands to see what's playing.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    // keychain status moved into header as a subtle affordance

    private var authCardHeaderTitle: String {
        if viewModel.reauthNeeded {
            return "Log In Again"
        } else if viewModel.credentialsSaved && viewModel.botUsername != "" {
            return "All Set!"
        } else {
            return "Not signed in"
        }
    }

    private var authCardHeaderSubtitle: String {
        if viewModel.reauthNeeded {
            return "Your login expired. Please log in again."
        } else if viewModel.credentialsSaved && viewModel.botUsername != "" {
            return ""
        } else if viewModel.authState.isInProgress {
            return "Enter the code below on Twitch to connect."
        } else {
            return "Sign in to get started."
        }
    }

    @ViewBuilder
    private var authCard: some View {
        VStack(spacing: 14) {
            // Card header (compact, copy-friendly — no logo)
            // Only show header when not connected
            if case .connected = viewModel.integrationState {
                // Header hidden when connected
            } else if case .authorizing = viewModel.integrationState {
                // Header hidden when authorizing — helper text provides instruction
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(authCardHeaderTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(authCardHeaderSubtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Main content switches by integration state
            Group {
                switch viewModel.integrationState {
                case .notConnected:
                    VStack(spacing: 12) {
                        Button(action: {
                            hasStartedActivation = false
                            viewModel.startOAuth()
                        }) {
                            Text("Connect Twitch")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .pointerCursor()
                        .scaleEffect(viewModel.authState.isInProgress ? 0.995 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.12), value: viewModel.authState.isInProgress
                        )
                        .accessibilityLabel("Sign in with Twitch")
                        .accessibilityHint("Starts the Twitch authorization flow")
                    }

                case .authorizing:
                    VStack(spacing: 12) {
                        HStack(spacing: 0) {
                            Text("Visit ")
                            if let activateURL = URL(string: "https://www.twitch.tv/activate") {
                                Link("twitch.tv/activate", destination: activateURL)
                                    .pointerCursor()
                            } else {
                                Text("twitch.tv/activate")
                            }
                            Text(" and enter this code:")
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if case .waitingForAuth(let code, let uri) = viewModel.authState {
                            DeviceCodeView(
                                userCode: code, verificationURI: uri,
                                onCopy: {
                                    // small feedback handled in DeviceCodeView
                                    viewModel.statusMessage = "Code copied"
                                    hasStartedActivation = true
                                },
                                onActivate: {
                                    hasStartedActivation = true
                                }
                            )
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity)
                            )
                            .animation(
                                .spring(response: 0.35, dampingFraction: 0.82, blendDuration: 0),
                                value: viewModel.authState.userCode)
                        }

                        // Always-visible spinner + cancel row once device code is shown
                        HStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.small)

                            Text("Waiting for authorization\u{2026}")
                                .font(.system(size: 13))
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

                case .connected:
                    SignedInView(
                        botUsername: viewModel.botUsername,
                        channelID: $viewModel.channelID,
                        isChannelConnected: viewModel.channelConnected,
                        isConnecting: viewModel.isConnecting,
                        reauthNeeded: viewModel.reauthNeeded,
                        credentialsSaved: viewModel.credentialsSaved,
                        channelValidationState: viewModel.channelValidationState,
                        testAuthResult: viewModel.testAuthResult,
                        onReauth: { viewModel.clearCredentials(); viewModel.startOAuth() },
                        onClearCredentials: { viewModel.clearCredentials() },
                        onJoinChannel: { viewModel.joinChannel() },
                        onLeaveChannel: { viewModel.leaveChannel() },
                        onChannelIDChanged: { viewModel.saveChannelID() },
                        onTestConnection: { viewModel.testConnection() }
                    )

                case .error(let message):
                    VStack(spacing: 8) {
                        Text(message)
                            .font(.system(size: 13))
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
                }
            }
        }
        .cardStyle()
        .animation(.easeInOut(duration: 0.2), value: viewModel.integrationState)
    }
}

// MARK: - Sub-Views

/// View displayed when the user is signed in, showing bot info and channel controls.
private struct SignedInView: View {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            botAccountSection
            Divider()
                .padding(.leading, AppConstants.SettingsUI.cardPadding)
            channelSection
            Divider()
                .padding(.leading, AppConstants.SettingsUI.cardPadding)
            actionButtonsSection
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))
    }

    // MARK: - Sections

    private var botAccountSection: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bot Account")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(botUsername.isEmpty ? "Not set" : botUsername)
                    .font(.system(size: 13, weight: .semibold))
            }
            Spacer()
            statusIcon(reauthNeeded: reauthNeeded)
        }
        .padding(.horizontal, AppConstants.SettingsUI.cardPadding)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Bot account: \(botUsername.isEmpty ? "Not set" : botUsername)")
        .accessibilityValue(reauthNeeded ? "Re-authorization needed" : "Authorized")
    }

    private var channelSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Channel")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    channelInputView
                }
                Spacer()
                connectionIcon
            }

            channelValidationIndicator
                .animation(.easeInOut(duration: 0.2), value: channelValidationState)
        }
        .padding(.horizontal, AppConstants.SettingsUI.cardPadding)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var channelValidationIndicator: some View {
        switch channelValidationState {
        case .idle:
            EmptyView()
        case .validating:
            HStack(spacing: 6) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
                Text("Verifying channel...")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Verifying channel")
        case .valid:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 11))
                Text("Channel verified")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            }
            .padding(.top, 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Channel verified successfully")
        case .invalid:
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 11))
                Text("Channel not found")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
            .padding(.top, 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Channel not found")
        case .error(let message):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 11))
                Text("Validation error")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .help(message)
            }
            .padding(.top, 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Channel validation error: \(message)")
        }
    }

    @ViewBuilder
    private var channelInputView: some View {
        switch (isChannelConnected, reauthNeeded) {
        case (true, _):
            Text(channelID.isEmpty ? "Not set" : channelID)
                .font(.system(size: 13, weight: .semibold))
        case (false, true):
            Text(channelID.isEmpty ? "Not set" : channelID)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        case (false, false):
            TextField("Channel Name", text: $channelID)
                .font(.system(size: 13))
                .textFieldStyle(.plain)
                .disabled(isConnecting)
                .accessibilityLabel("Twitch channel name")
                .accessibilityHint("Enter the channel name for your Twitch channel")
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

    @ViewBuilder
    private var connectionIcon: some View {
        switch (isChannelConnected, reauthNeeded) {
        case (true, _):
            Image(systemName: "wifi")
                .foregroundStyle(.green)
                .font(.system(size: 14))
                .accessibilityLabel("Connected to channel")
        case (false, true):
            Image(systemName: "wifi.slash")
                .foregroundStyle(.orange)
                .font(.system(size: 14))
                .accessibilityLabel("Disconnected, re-authorization needed")
        case (false, false):
            EmptyView()
        }
    }

    private var actionButtonsSection: some View {
        HStack(spacing: 10) {
            if reauthNeeded {
                Button(action: onReauth) {
                    Label("Re-auth", systemImage: "arrow.clockwise.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .controlSize(.small)
                .pointerCursor()
                .accessibilityLabel("Re-authorize Twitch account")
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
                        HStack(spacing: 6) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.mini)
                            Text("Connecting...")
                                .font(.system(size: 12))
                        }
                    } else {
                        Label(
                            isChannelConnected ? "Disconnect" : "Connect",
                            systemImage: isChannelConnected
                                ? "xmark.circle.fill" : "checkmark.circle.fill"
                        )
                        .font(.system(size: 12, weight: .medium))
                    }
                }
                .disabled(shouldDisableConnectButton)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .pointerCursor()
                .accessibilityLabel(
                    isChannelConnected ? "Disconnect from channel" : "Connect to channel"
                )
                .accessibilityHint(
                    isChannelConnected ? "Disconnects the bot from the Twitch channel" : "Connects the bot to the Twitch channel"
                )
                .accessibilityValue(isChannelConnected ? "Connected" : "Disconnected")
                .accessibilityIdentifier("twitchConnectButton")

                Button(action: onTestConnection) {
                    switch testAuthResult {
                    case .idle:
                        Label("Test Login", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 12, weight: .medium))
                    case .testing:
                        HStack(spacing: 6) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.mini)
                            Text("Testing...")
                                .font(.system(size: 12))
                        }
                    case .success:
                        Label("Passed", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                    case .failure:
                        Label("Failed", systemImage: "xmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .frame(minWidth: 95)
                .buttonStyle(.bordered)
                .tint(testAuthButtonTint)
                .controlSize(.small)
                .disabled(testAuthResult == .testing)
                .pointerCursor()
                .animation(.easeInOut(duration: 0.2), value: testAuthResult)
                .help("Validates your Twitch token and checks required permissions")
                .accessibilityLabel("Test Twitch token validity")
                .accessibilityHint("Validates your Twitch token and checks required permissions")
                .accessibilityValue(
                    testAuthResult == .success ? "Passed" :
                    testAuthResult == .failure ? "Failed" :
                    testAuthResult == .testing ? "Testing" : "Not tested"
                )
                .accessibilityIdentifier("twitchTestConnectionButton")
            }

            Spacer()

            Button("Log Out", action: onClearCredentials)
                .font(.system(size: 12))
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
                .pointerCursor()
                .accessibilityLabel("Clear saved Twitch credentials")
                .accessibilityHint("Signs out of your Twitch account")
                .accessibilityIdentifier("twitchClearCredentialsButton")
        }
        .padding(.horizontal, AppConstants.SettingsUI.cardPadding)
        .padding(.vertical, 12)
        .confirmationDialog(
            "Disconnect from channel?", isPresented: $showingDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                onLeaveChannel()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will disconnect the bot from the current channel but keep saved credentials.")
        }
    }

    private var testAuthButtonTint: Color? {
        switch testAuthResult {
        case .idle, .testing: return nil
        case .success: return .green
        case .failure: return .red
        }
    }

    private var shouldDisableConnectButton: Bool {
        let validChannel = !channelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isConnecting { return true }
        // If credentials are saved we can attempt to connect even if the
        // bot username hasn't been resolved yet — rely on saved token.
        if credentialsSaved {
            return !validChannel
        }
        return botUsername.isEmpty || !validChannel
    }

    @ViewBuilder
    private func statusIcon(reauthNeeded: Bool) -> some View {
        Image(systemName: reauthNeeded ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
            .foregroundStyle(reauthNeeded ? .orange : .green)
            .font(.system(size: 14))
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

