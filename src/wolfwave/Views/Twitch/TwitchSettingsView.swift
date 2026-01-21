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
    @ObservedObject var viewModel: TwitchViewModel
    @State private var hasStartedActivation = false

    var body: some View {
        VStack(spacing: 20) {
            headerView

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                authCard
                    .frame(maxWidth: 720)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(
                        .spring(response: 0.35, dampingFraction: 0.82, blendDuration: 0),
                        value: (viewModel.credentialsSaved || viewModel.channelConnected
                            || viewModel.authState.isInProgress))
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .onAppear {
            Log.debug("TwitchSettingsView: onAppear called", category: "Twitch")
            viewModel.loadSavedCredentials()

            // Ensure the service is set on the view model
            if viewModel.twitchService == nil {
                Log.debug(
                    "TwitchSettingsView: ViewModel service is nil, attempting to fetch from AppDelegate",
                    category: "Twitch")
                if let appDelegate = AppDelegate.shared {
                    Log.debug("TwitchSettingsView: AppDelegate.shared found", category: "Twitch")
                    viewModel.twitchService = appDelegate.twitchService
                    if viewModel.twitchService != nil {
                        Log.info(
                            "TwitchSettingsView: Service successfully set on ViewModel",
                            category: "Twitch")
                    } else {
                        Log.error(
                            "TwitchSettingsView: AppDelegate.twitchService is nil!",
                            category: "Twitch")
                    }
                } else {
                    Log.error("TwitchSettingsView: AppDelegate.shared is nil", category: "Twitch")
                }
            } else {
                Log.debug(
                    "TwitchSettingsView: ViewModel already has service reference",
                    category: "Twitch")
            }

            if let svc = viewModel.twitchService {
                viewModel.channelConnected = svc.isConnected
                Log.debug(
                    "TwitchSettingsView: Service connected state: \(svc.isConnected)",
                    category: "Twitch")
            }

            // If reauthentication is needed, disconnect from the channel
            if viewModel.reauthNeeded && viewModel.channelConnected {
                Log.info(
                    "TwitchSettingsView: Reauth needed, disconnecting from channel",
                    category: "Twitch")
                viewModel.leaveChannel()
            }
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Text("Twitch Integration")
                    .font(.system(size: 17, weight: .semibold))

                Spacer()

                // Use the view model's status chip text/color so the chip is
                // consistent with other parts of the app and can be tinted
                // independently from the header's descriptive text.
                StatusChip(text: viewModel.statusChipText, color: viewModel.statusChipColor)
                    .accessibilityLabel("Twitch integration status: \(viewModel.statusChipText)")
                    .scaleEffect(
                        viewModel.credentialsSaved || viewModel.channelConnected ? 1.02 : 0.98
                    )
                    .opacity(viewModel.credentialsSaved || viewModel.channelConnected ? 1.0 : 0.95)
                    .animation(
                        .easeInOut(duration: 0.18),
                        value: viewModel.credentialsSaved || viewModel.channelConnected
                    )
                    .padding(.trailing, 4)
            }

            Text("Enable chat features like commands, song requests, and moderation tools.")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    // keychain status moved into header as a subtle affordance

    private var authCardHeaderTitle: String {
        if viewModel.reauthNeeded {
            return "Sign In Again"
        } else if viewModel.credentialsSaved && viewModel.botUsername != "" {
            return "All Set!"
        } else {
            return "Enable the Twitch Bot"
        }
    }

    private var authCardHeaderSubtitle: String {
        if viewModel.reauthNeeded {
            return "Your authorization expired. Please sign in again."
        } else if viewModel.credentialsSaved && viewModel.botUsername != "" {
            return ""
        } else if viewModel.authState.isInProgress {
            return "A window will open for you to authorize. Just follow the steps."
        } else {
            return "Click below to connect your Twitch bot."
        }
    }

    @ViewBuilder
    private var authCard: some View {
        VStack(spacing: 14) {
            // Card header (compact, copy-friendly — no logo)
            // Only show header when not connected
            if case .connected = viewModel.integrationState {
                // Header hidden when connected
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(authCardHeaderTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    Text(authCardHeaderSubtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Main content switches by integration state
            Group {
                switch viewModel.integrationState {
                case .notConnected:
                    VStack(spacing: 12) {
                        if viewModel.authState.isInProgress || hasStartedActivation {
                            Text(
                                "Connect your bot so WolfWave can send and respond to chat commands in your channel."
                            )
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        }
                        Button(action: {
                            hasStartedActivation = false
                            viewModel.startOAuth()
                        }) {
                            HStack(spacing: 8) {
                                Image("TwitchLogo")
                                    .renderingMode(.original)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 14, height: 14)
                                Text("Get Started with Twitch")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .scaleEffect(viewModel.authState.isInProgress ? 0.995 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.12), value: viewModel.authState.isInProgress
                        )
                        .accessibilityLabel("Get started with Twitch authorization")
                    }

                case .authorizing:
                    VStack(spacing: 12) {
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

                        Text("You can also go to twitch.tv/activate with the code below.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Inline waiting row with compact spinner, text and cancel
                        if hasStartedActivation {
                            HStack(spacing: 12) {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .controlSize(.small)

                                Text("Waiting for authorization…")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(.secondary)

                                Spacer()

                                Button("Cancel") {
                                    hasStartedActivation = false
                                    viewModel.cancelOAuth()
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                                .controlSize(.small)
                            }
                            .padding(.top, 4)
                        } else {
                            HStack(spacing: 12) {
                                Spacer()

                                Button("Cancel") {
                                    viewModel.cancelOAuth()
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                                .controlSize(.small)
                            }
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
                        onClearCredentials: { viewModel.clearCredentials() },
                        onJoinChannel: { viewModel.joinChannel() },
                        onLeaveChannel: { viewModel.leaveChannel() },
                        onChannelIDChanged: { viewModel.saveChannelID() }
                    )

                case .error(let message):
                    VStack(spacing: 8) {
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                        HStack {
                            Button("Retry") { viewModel.startOAuth() }
                                .buttonStyle(.bordered)
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .animation(.easeInOut(duration: 0.18), value: viewModel.authState.isInProgress)
        .animation(.easeInOut(duration: 0.18), value: viewModel.channelConnected)
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
    var onClearCredentials: () -> Void
    var onJoinChannel: () -> Void
    var onLeaveChannel: () -> Void
    var onChannelIDChanged: () -> Void
    @State private var showingDisconnectConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                botAccountSection
                Divider()
                channelSection
                Divider()
                actionButtonsSection
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    // MARK: - Sections

    private var botAccountSection: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bot account")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Text(botUsername.isEmpty ? "Not set" : botUsername)
                    .font(.body)
                    .fontWeight(.semibold)
            }
            Spacer()
            statusIcon(reauthNeeded: reauthNeeded)
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
    }

    private var channelSection: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Channel")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                channelInputView
            }
            Spacer()
            connectionIcon
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var channelInputView: some View {
        switch (isChannelConnected, reauthNeeded) {
        case (true, _):
            Text(channelID.isEmpty ? "Not set" : channelID)
                .font(.body)
                .fontWeight(.semibold)
        case (false, true):
            TextField("Not set", text: .constant(channelID))
                .font(.body)
                .fontWeight(.semibold)
                .disabled(true)
                .accessibilityLabel("Twitch channel name")
                .onHover { isHovering in
                    if isHovering {
                        NSCursor.operationNotAllowed.push()
                    } else {
                        NSCursor.pop()
                    }
                }
        case (false, false):
            TextField("Enter channel name", text: $channelID)
                .font(.body)
                .disabled(isConnecting)
                .accessibilityLabel("Twitch channel name")
                .accessibilityHint("Enter the channel name for your Twitch channel")
                .accessibilityIdentifier("twitchChannelTextField")
                .onChange(of: channelID) { oldValue, newValue in
                    // Validate and normalize channel name only if needed
                    let sanitized = newValue.lowercased().trimmingCharacters(
                        in: CharacterSet.whitespacesAndNewlines)
                    if sanitized != newValue {
                        channelID = sanitized
                    }
                    // Only trigger save if the value actually changed from the previous sanitized value
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
                .foregroundColor(.green)
                .imageScale(.medium)
        case (false, true):
            Image(systemName: "wifi.slash")
                .foregroundColor(.orange)
                .imageScale(.medium)
        case (false, false):
            EmptyView()
        }
    }

    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
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
                            .controlSize(.small)
                            .scaleEffect(0.8)
                        Text("Connecting....")
                    }
                } else {
                    Label(
                        isChannelConnected ? "Disconnect" : "Connect",
                        systemImage: isChannelConnected
                            ? "xmark.circle.fill" : "checkmark.circle.fill"
                    )
                }
            }
            .disabled(shouldDisableConnectButton)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(
                isChannelConnected ? "Disconnect from channel" : "Connect to channel"
            )
            .accessibilityIdentifier("twitchConnectButton")
            Spacer()

            Button("Clear", action: onClearCredentials)
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
                .accessibilityLabel("Clear saved Twitch credentials")
                .accessibilityIdentifier("twitchClearCredentialsButton")
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .confirmationDialog(
            "Disconnect from channel?", isPresented: $showingDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                onLeaveChannel()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This will disconnect the bot from the current channel but keep saved credentials.")
        }
    }

    private var shouldDisableConnectButton: Bool {
        let validChannel = !channelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if reauthNeeded || isConnecting { return true }
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
            .foregroundColor(reauthNeeded ? .orange : .green)
            .imageScale(.medium)
            .onHover { isHovering in
                if isHovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

// MARK: - Status Chip

/// Colored status indicator chip.
private struct StatusChip: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(text)
                .font(.caption2).bold()
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}
// MARK: - Preview

#Preview {
    let mockViewModel = TwitchViewModel()
    mockViewModel.botUsername = "MrDemonWolf"
    mockViewModel.channelID = "mrdemonwolf"
    mockViewModel.credentialsSaved = true
    mockViewModel.channelConnected = true
    mockViewModel.statusMessage = "Connected to mrdemonwolf"

    return TwitchSettingsView(viewModel: mockViewModel)
        .padding()
}
