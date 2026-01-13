//
//  TwitchSettingsView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/8/26.
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
                ReauthBanner()
            }

            if !viewModel.credentialsSaved {
                NotSignedInView(onStartOAuth: { viewModel.startOAuth() })
            } else {
                SignedInView(
                    botUsername: viewModel.botUsername,
                    channelID: $viewModel.channelID,
                    isChannelConnected: viewModel.channelConnected,
                    onSaveCredentials: { viewModel.saveCredentials() },
                    onClearCredentials: { viewModel.clearCredentials() },
                    onJoinChannel: { viewModel.joinChannel() },
                    onLeaveChannel: { viewModel.leaveChannel() }
                )
            }

            if !viewModel.authState.userCode.isEmpty {
                DeviceCodeView(
                    userCode: viewModel.authState.userCode,
                    verificationURI: viewModel.authState.verificationURI,
                    onCopy: { viewModel.statusMessage = "Connecting to Twitch..." }
                )
            }

            if viewModel.authState.isInProgress {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Color(nsColor: .controlAccentColor))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }

            if viewModel.reauthNeeded {
                Text("Re-authentication required. Click 'Sign in with Twitch'.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Sub-Views

/// Banner displayed when re-authentication is required.
private struct ReauthBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Session Expired")
                    .font(.body)
                    .fontWeight(.medium)
                Text("Your Twitch session expired. Please sign in again to continue.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

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
private struct SignedInView: View {
    let botUsername: String
    @Binding var channelID: String
    let isChannelConnected: Bool
    var onSaveCredentials: () -> Void
    var onClearCredentials: () -> Void
    var onJoinChannel: () -> Void
    var onLeaveChannel: () -> Void

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
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .imageScale(.medium)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
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
                        }
                    }
                    Spacer()
                    if isChannelConnected {
                        Image(systemName: "wifi")
                            .foregroundColor(.green)
                            .imageScale(.medium)
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }

            HStack(spacing: 8) {
                Button("Save Channel") {
                    onSaveCredentials()
                }
                .disabled(channelID.isEmpty || isChannelConnected)
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: isChannelConnected ? onLeaveChannel : onJoinChannel) {
                    Label(
                        isChannelConnected ? "Disconnect" : "Connect",
                        systemImage: isChannelConnected
                            ? "xmark.circle.fill" : "checkmark.circle.fill"
                    )
                }
                .disabled(
                    botUsername.isEmpty
                        || channelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

/// View displaying the device code authorization UI during OAuth flow.
private struct DeviceCodeView: View {
    let userCode: String
    let verificationURI: String
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "number")
                    .font(.title3)
                    .foregroundStyle(Color(nsColor: .controlAccentColor))
                Text("Authorize on Twitch")
                    .font(.body)
                    .fontWeight(.medium)
            }
            
            Text(
                "Open Twitch to authorize, or go to twitch.tv/activate on any device and enter this code."
            )
            .font(.caption)
            .foregroundColor(.secondary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Device Code")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    Text(userCode)
                        .font(.title3)
                        .monospaced()
                        .fontWeight(.bold)
                        .tracking(1)
                }
                Spacer()
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(userCode, forType: .string)
                    onCopy()
                }) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            VStack(spacing: 10) {
                Button(action: {
                    if let url = URL(string: verificationURI) {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Label("Open Twitch to authorize", systemImage: "link.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Link(
                    "Or visit twitch.tv/activate and enter the code",
                    destination: URL(string: "https://twitch.tv/activate")!
                )
                .font(.caption)
                .foregroundColor(.blue)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlAccentColor).opacity(0.1))
        )
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
