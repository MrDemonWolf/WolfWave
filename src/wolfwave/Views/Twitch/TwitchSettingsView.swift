//
//  TwitchSettingsView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/13/26.
//

import AppKit
import SwiftUI

// MARK: - Twitch Settings View

/// SwiftUI view displaying Twitch bot configuration and connection controls.
///
/// This view provides:
/// - OAuth device code flow initiation
/// - Bot identity display (username)
/// - Channel name configuration
/// - Join/leave channel controls
/// - Credential management (save/clear)
/// - Connection status indicator
struct TwitchSettingsView: View {
    @ObservedObject var viewModel: TwitchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.body)
                    .foregroundStyle(.green)
                Text("All credentials are stored securely in macOS Keychain")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)

            if viewModel.reauthNeeded {
                TwitchReauthView(viewModel: viewModel)
            } else if !viewModel.credentialsSaved {
                NotSignedInView(onStartOAuth: { viewModel.startOAuth() })
            } else {
                SignedInView(
                    botUsername: viewModel.botUsername,
                    channelID: $viewModel.channelID,
                    isChannelConnected: viewModel.channelConnected && !viewModel.reauthNeeded,
                    reauthNeeded: viewModel.reauthNeeded,
                    onSaveCredentials: { viewModel.saveCredentials() },
                    onClearCredentials: { viewModel.clearCredentials() },
                    onJoinChannel: { viewModel.joinChannel() },
                    onLeaveChannel: { viewModel.leaveChannel() },
                    onChannelIDChanged: { viewModel.saveChannelID() }
                )
            }

            if !viewModel.authState.userCode.isEmpty && !viewModel.reauthNeeded {
                DeviceCodeView(
                    userCode: viewModel.authState.userCode,
                    verificationURI: viewModel.authState.verificationURI,
                    onCopy: { viewModel.statusMessage = "Connecting to Twitch..." }
                )
            }

            if viewModel.authState.isInProgress && !viewModel.reauthNeeded {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Color(nsColor: .controlAccentColor))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - Sub-Views

/// View displayed when the user is not signed in to Twitch.
private struct NotSignedInView: View {
    var onStartOAuth: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect your Twitch account to enable chat bot features")
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: onStartOAuth) {
                Label {
                    Text("Sign in with Twitch")
                        .fontWeight(.semibold)
                } icon: {
                    Image("TwitchLogo")
                        .renderingMode(.original)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

/// View displayed when the user is signed in, showing bot info and channel controls.
///
/// Displays:
/// - Bot account name with connection status indicator
/// - Channel name (editable when disconnected, read-only when connected)
/// - Connect/Disconnect button for channel
/// - Clear credentials button to reset authentication
private struct SignedInView: View {
    let botUsername: String
    @Binding var channelID: String
    let isChannelConnected: Bool
    let reauthNeeded: Bool
    var onSaveCredentials: () -> Void
    var onClearCredentials: () -> Void
    var onJoinChannel: () -> Void
    var onLeaveChannel: () -> Void
    var onChannelIDChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
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
                    Image(systemName: reauthNeeded ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundColor(reauthNeeded ? .orange : .green)
                        .imageScale(.medium)
                }
                .padding(12)
                .background(reauthNeeded ? Color.orange.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Channel")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        if isChannelConnected {
                            Text(channelID.isEmpty ? "Not set" : channelID)
                                .font(.body)
                                .fontWeight(.semibold)
                        } else {
                            TextField("Enter channel name", text: $channelID)
                                .font(.body)
                                .onChange(of: channelID) { _, _ in
                                    onChannelIDChanged()
                                }
                                .disabled(reauthNeeded)
                        }
                    }
                    Spacer()
                    if isChannelConnected {
                        Image(systemName: "wifi")
                            .foregroundColor(.green)
                            .imageScale(.medium)
                    } else if reauthNeeded {
                        Image(systemName: "wifi.slash")
                            .foregroundColor(.orange)
                            .imageScale(.medium)
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }

            HStack(spacing: 8) {
                Button(action: isChannelConnected ? onLeaveChannel : onJoinChannel) {
                    Label(
                        isChannelConnected ? "Disconnect" : "Connect",
                        systemImage: isChannelConnected
                            ? "xmark.circle.fill" : "checkmark.circle.fill"
                    )
                }
                .disabled(
                    botUsername.isEmpty
                        || channelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || reauthNeeded)
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Clear", action: onClearCredentials)
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
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
        Text(text)
            .font(.caption2).bold()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundColor(color)
            .background(color.opacity(0.15))
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