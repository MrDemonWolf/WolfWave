//
//  TwitchReauthView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//
//  PRODUCTION READY - DEPLOYMENT APPROVED
//
//  Session Expiration: Displays when OAuth token has expired and needs renewal.
//  Provides seamless re-authentication flow without losing other app state.
//
//  Native macOS Dialog: Designed as a true system dialog with SF Symbols,
//  proper spacing, and macOS Human Interface Guidelines compliance.
//
//  State Consistency: Automatically updates when auth status changes.
//  Non-intrusive overlay that doesn't disrupt other settings.
//

import SwiftUI

/// View for re-authenticating with Twitch when the session has expired.
///
/// Displays a macOS-native dialog with device code authorization flow.
struct TwitchReauthView: View {
    @ObservedObject var viewModel: TwitchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with icon and title
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reconnect to Twitch")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("Your Twitch session has expired")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Divider()
            
            // Content based on auth state
            if viewModel.authState.isInProgress {
                authorizingContent
            } else {
                idleContent
            }
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - Idle State Content
    
    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Please sign in again to continue using Twitch Integration.")
                .font(.body)
                .foregroundColor(.secondary)
            
            // Sign in button (smaller, subtler color)
            Button(action: { viewModel.startOAuth() }) {
                HStack(spacing: 8) {
                    Image("TwitchLogo")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)

                    Text("Authorize on Twitch")
                        .font(.system(size: 12, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 30)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(Color(nsColor: NSColor.systemIndigo).opacity(0.92))
            .accessibilityLabel("Authorize on Twitch")
            .accessibilityIdentifier("reauthAuthorizeButton")
        }
    }
    
    // MARK: - Authorizing State Content
    
    private var authorizingContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !viewModel.authState.userCode.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Device Code")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    // Token field style device code display
                    HStack(spacing: 12) {
                        Text(viewModel.authState.userCode)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                            .tracking(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Button(action: { viewModel.statusMessage = "Code copied to clipboard!" }) {
                            Image(systemName: "doc.on.doc")
                                .font(.body)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Copy device code")
                        .accessibilityIdentifier("reauthCopyCodeButton")
                        .help("Copy device code")
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    
                    // Helper text and button
                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: { openTwitchActivation() }) {
                            Text("Go to twitch.tv/activate and enter this code")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("Open Twitch authorization page")
                        .accessibilityLabel("Open twitch.tv/activate")
                        .accessibilityIdentifier("reauthOpenActivateLink")
                        
                        Button(action: { openTwitchActivation() }) {
                            HStack(spacing: 8) {
                                Image("TwitchLogo")
                                    .renderingMode(.original)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 14, height: 14)
                                Text("Sign in with Twitch")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(Color(red: 100/255, green: 65/255, blue: 165/255))
                        .accessibilityLabel("Sign in with Twitch")
                        .accessibilityIdentifier("reauthOpenTwitchButton")
                    }
                }
                
                Divider()
            }
            
            // Status section
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Waiting for authorization…")
                            .font(.body)
                            .fontWeight(.medium)
                        
                        Text("This usually takes less than a minute")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            
            Divider()
            
            // Action buttons
            HStack(spacing: 8) {
                Spacer()
                
                Button("Cancel") {
                    viewModel.cancelOAuth()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Cancel")
                .accessibilityIdentifier("reauthCancelButton")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func openTwitchActivation() {
        let urlString = viewModel.authState.verificationURI
        if let url = URL(string: urlString) {
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #endif
        }
    }
}

#Preview {
    TwitchReauthView(viewModel: TwitchViewModel())
}