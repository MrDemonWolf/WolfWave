//
//  DeviceCodeView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import SwiftUI

/// Native macOS device authorization code display.
/// Clean, minimal, system-native presentation for inline use in settings.
///
/// Follows macOS design principles:
/// - No heavy styling or borders
/// - Calm, trustworthy appearance
/// - Smooth interaction feedback
/// - Supports dark and light modes naturally
struct DeviceCodeView: View {
    let userCode: String
    let verificationURI: String
    let onCopy: () -> Void
    var onActivate: (() -> Void)? = nil
    
    @State private var isCodeCopied = false
    @State private var showCopyFeedback = false
    @State private var isHovering = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: subtle label + helper
            VStack(alignment: .leading, spacing: 2) {
                Text("Device Code")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Text("Click the button below to quickly sign in with Twitch and enable chat features")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
            }
            .transition(.move(edge: .top).combined(with: .opacity))


            // Code container - monospaced, larger and calm
            HStack(spacing: 8) {
                Text(userCode)
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityLabel("Device code")
                    .accessibilityValue(userCode)
                    .accessibilityIdentifier("deviceCodeText")

                // Always-visible copy button (subtle by default, highlighted on hover or when copied)
                Button(action: copyDeviceCode) {
                    Image(systemName: isCodeCopied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(isCodeCopied ? .green : .secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(isCodeCopied ? "Copied" : "Copy code")
                .accessibilityLabel(isCodeCopied ? "Copied" : "Copy device code")
                .accessibilityIdentifier("copyDeviceCodeButton")
                .transition(.opacity)
                .opacity((isHovering || isCodeCopied) ? 1.0 : 0.9)
                .animation(.easeInOut(duration: 0.12), value: isHovering || isCodeCopied)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .cornerRadius(8)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }

            // Primary action: open activation URL with subtler, smaller button
            Button(action: openActivationURL) {
                HStack(spacing: 6) {
                    Text("Continue to Twitch to Authorize")
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 30)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityLabel("Continue to Twitch to authorize")
            .accessibilityHint("Opens twitch.tv/activate in your browser")
            .accessibilityIdentifier("openTwitchButton")
        }
        // Position the small "copied" toast near the copy button (top-right)
        .overlay(
            copyFeedbackView
                .padding(.trailing, 6)
                .offset(x: -8, y: -8),
            alignment: .topTrailing
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.82, blendDuration: 0), value: userCode)
    }
    
    private func copyDeviceCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(userCode, forType: .string)
        
        isCodeCopied = true
        onCopy()
        
        // Show feedback
        withAnimation(.easeInOut(duration: 0.18)) {
            showCopyFeedback = true
        }

        // Auto-dismiss feedback and reset state
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            withAnimation(.easeInOut(duration: 0.18)) {
                showCopyFeedback = false
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            isCodeCopied = false
        }
    }

    private func openActivationURL() {
        if let url = URL(string: verificationURI) {
            NSWorkspace.shared.open(url)
            onActivate?()
        }
    }

    @ViewBuilder
    private var copyFeedbackView: some View {
        if showCopyFeedback {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Copied to clipboard")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Color(nsColor: .windowBackgroundColor).opacity(0.98)
            )
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        DeviceCodeView(
            userCode: "ABCD-EFGH",
            verificationURI: "https://www.twitch.tv/activate?device_code=test",
            onCopy: { print("Copied!") }
        )
        
        Divider()
        
        DeviceCodeView(
            userCode: "WXYZ-QRST",
            verificationURI: "https://www.twitch.tv/activate?device_code=test2",
            onCopy: { print("Copied!") }
        )
    }
    .padding(24)
}
