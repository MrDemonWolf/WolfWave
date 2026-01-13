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
        GroupBox(
            label:
                HStack {
                    Label("Twitch Bot", systemImage: "bubble.left.and.bubble.right")
                        .font(.headline)
                        .padding(.bottom, 4)
                    Spacer()
                    StatusChip(text: viewModel.statusChipText, color: viewModel.statusChipColor)
                }
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.credentialsSaved {
                    Text(
                        "Bot username, OAuth token, and channel are kept securely in macOS Keychain. The bot username fills in automatically right after you sign in."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                }

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
                        .tint(.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }

                if viewModel.reauthNeeded {
                    Text("Re-authentication required. Click 'Sign in with Twitch'.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

// MARK: - Sub-Views

/// Banner displayed when re-authentication is required.
private struct ReauthBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
            Text("Your Twitch session expired. Please sign in again to continue.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

/// View displayed when the user is not signed in to Twitch.
private struct NotSignedInView: View {
    var onStartOAuth: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                "Connect Twitch so WolfWave can chat in your channel. Credentials stay in macOS Keychain."
            )
            .font(.caption)
            .foregroundColor(.secondary)

            Button(action: onStartOAuth) {
                Label(
                    "Sign in with Twitch", systemImage: "person.badge.key"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Bot account")
                    .foregroundColor(.secondary)
                    .frame(width: 140, alignment: .leading)
                Text(botUsername.isEmpty ? "Not set" : botUsername)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Channel to join")
                    .foregroundColor(.secondary)
                    .frame(width: 140, alignment: .leading)
                if isChannelConnected {
                    Text(channelID.isEmpty ? "Not set" : channelID)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField("", text: $channelID)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 260, maxWidth: .infinity)
                }
            }

            HStack(spacing: 10) {
                Button("Save Channel", action: onSaveCredentials)
                    .disabled(channelID.isEmpty || isChannelConnected)

                Button(action: isChannelConnected ? onLeaveChannel : onJoinChannel) {
                    Label(
                        isChannelConnected ? "Leave channel" : "Join channel",
                        systemImage: isChannelConnected
                            ? "xmark.circle.fill" : "arrow.right.circle.fill"
                    )
                }
                .disabled(
                    botUsername.isEmpty
                        || channelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Clear bot info", action: onClearCredentials)
                    .foregroundColor(.red)
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
        VStack(alignment: .leading, spacing: 8) {
            Label("Authorize on Twitch", systemImage: "number")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(
                "Open Twitch to authorize, or go to twitch.tv/activate on any device and enter this code."
            )
            .font(.caption)
            .foregroundColor(.secondary)

            HStack {
                Text(userCode)
                    .font(.title3).monospaced().bold()
                Spacer()
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(userCode, forType: .string)
                    onCopy()
                }) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
            }

            Button(action: {
                if let url = URL(string: verificationURI) {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Label("Open Twitch to authorize", systemImage: "link")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .frame(maxWidth: .infinity, alignment: .leading)

            Link(
                "Or go to twitch.tv/activate and enter the code",
                destination: URL(string: "https://twitch.tv/activate")!
            )
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        )
        .padding(.bottom, 6)
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
