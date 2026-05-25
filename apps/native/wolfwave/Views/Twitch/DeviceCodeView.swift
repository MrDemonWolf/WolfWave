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

    // MARK: - Properties

    let userCode: String
    let verificationURI: String
    let onCopy: () -> Void
    var onActivate: (() -> Void)? = nil
    
    @State private var isCodeCopied = false
    @State private var showCopyFeedback = false
    @State private var isHovering = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            // Header: subtle label
            Text("Sign-in Code")
                .font(.system(size: DSFont.Size.sm, weight: .medium))
                .foregroundStyle(.secondary)
                .transition(.move(edge: .top).combined(with: .opacity))


            // Code container - monospaced, larger and calm
            HStack(spacing: DSSpace.s2) {
                Text(userCode)
                    .font(.system(size: DSFont.Size.x28, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityLabel("Sign-in code")
                    .accessibilityValue(userCode)
                    .accessibilityIdentifier("deviceCodeText")

                // Always-visible copy button (subtle by default, highlighted on hover or when copied)
                Button(action: copyDeviceCode) {
                    Image(systemName: isCodeCopied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: DSFont.Size.md, weight: .regular))
                        .foregroundStyle(isCodeCopied ? .green : .secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .help(isCodeCopied ? "Copied" : "Copy code")
                .accessibilityLabel(isCodeCopied ? "Copied" : "Copy sign-in code")
                .accessibilityIdentifier("copyDeviceCodeButton")
                .transition(.opacity)
                .opacity((isHovering || isCodeCopied) ? 1.0 : 0.9)
                .animation(.easeInOut(duration: 0.12), value: isHovering || isCodeCopied)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .padding(DSSpace.s4)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onTapGesture {
                copyDeviceCode()
            }

            // Primary action: open activation URL with subtler, smaller button
            Button(action: openActivationURL) {
                HStack(spacing: 6) {
                    Text("Continue to Twitch to sign in")
                        .font(.system(size: DSFont.Size.body, weight: .medium))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: DSFont.Size.xs, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 30)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .pointerCursor()
            .accessibilityLabel("Continue to Twitch to Authorize")
            .accessibilityHint("Opens twitch.tv/activate in your browser")
            .accessibilityIdentifier("openTwitchButton")
        }
        // Position the small "copied" toast near the copy button (top-right)
        .overlay(
            copyFeedbackView
                .padding(.trailing, DSSpace.s2)
                .offset(x: -8, y: -8),
            alignment: .topTrailing
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.82, blendDuration: 0), value: userCode)
    }

    // MARK: - Helpers

    /// Copies the displayed device code to the pasteboard, animates the
    /// "Copied" affordance, and resets the visual state after ~1.3 seconds.
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
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1300))
            withAnimation(.easeInOut(duration: 0.18)) {
                showCopyFeedback = false
            }
            isCodeCopied = false
        }
    }

    /// Opens the Twitch device activation URL in the user's default browser
    /// and forwards the action to the parent via `onActivate`.
    private func openActivationURL() {
        if let url = URL(string: verificationURI) {
            NSWorkspace.shared.open(url)
            onActivate?()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var copyFeedbackView: some View {
        if showCopyFeedback {
            HStack(spacing: DSSpace.s2) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Copied to clipboard")
                    .font(.system(size: DSFont.Size.body, weight: .semibold))
            }
            .padding(.horizontal, DSSpace.s4)
            .padding(.vertical, DSSpace.s2)
            .background(
                Color(nsColor: .windowBackgroundColor).opacity(0.98)
            )
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

#Preview("Standard Code") {
    VStack(spacing: DSSpace.s8) {
        DeviceCodeView(
            userCode: "ABCD-EFGH",
            verificationURI: "https://www.twitch.tv/activate?device_code=test",
            onCopy: { }
        )

        Divider()

        DeviceCodeView(
            userCode: "WXYZ-QRST",
            verificationURI: "https://www.twitch.tv/activate?device_code=test2",
            onCopy: { }
        )
    }
    .padding(DSSpace.s8)
    .frame(width: 500)
}
#Preview("Long Code") {
    DeviceCodeView(
        userCode: "ABCDEFGH-IJKLMNOP",
        verificationURI: "https://www.twitch.tv/activate",
        onCopy: { }
    )
    .padding(DSSpace.s8)
    .frame(width: 500)
}

#Preview("Compact Card") {
    VStack(alignment: .leading, spacing: DSSpace.s4) {
        Text("Enter this code on Twitch")
            .font(.system(size: DSFont.Size.base))
            .foregroundStyle(.secondary)
        
        DeviceCodeView(
            userCode: "MNOP-QRST",
            verificationURI: "https://www.twitch.tv/activate",
            onCopy: { },
            onActivate: { }
        )
    }
    .padding()
    .background(Color(nsColor: .controlBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .padding(DSSpace.s8)
    .frame(width: 400)
}

