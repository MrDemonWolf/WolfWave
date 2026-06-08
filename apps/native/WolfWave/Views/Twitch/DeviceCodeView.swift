//
//  DeviceCodeView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-01-13.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showCopyFeedback = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            // Header: subtle label
            Text("Your code")
                .font(.system(size: DSFont.Size.sm, weight: .medium))
                .foregroundStyle(.secondary)
                .transition(.move(edge: .top).combined(with: .opacity))


            // Code container - monospaced, larger and calm
            HStack(spacing: DSSpace.s2) {
                Text(userCode)
                    .font(.system(size: DSFont.Size.x2xl, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityLabel("Sign-in code")
                    .accessibilityValue(userCode)
                    .accessibilityIdentifier("deviceCodeText")

                // Always-visible copy button. CopyButton owns the checkmark
                // confirmation + reset timer; `action` forwards onCopy.
                CopyButton(
                    text: userCode,
                    buttonStyle: .borderless,
                    accessibilityLabel: "Copy sign-in code",
                    accessibilityIdentifier: "copyDeviceCodeButton",
                    feedbackDuration: 1.3,
                    action: onCopy
                )
                .help("Copy code")
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .padding(DSSpace.s4)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.md)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.md))
            .pointerCursor()
            .onTapGesture {
                copyDeviceCode()
            }

            // Primary action: open activation URL with subtler, smaller button
            Button(action: openActivationURL) {
                HStack(spacing: DSSpace.s1h) {
                    Text("Open twitch.tv/activate")
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
            .accessibilityLabel("Open twitch.tv/activate")
            .accessibilityHint("Opens the Twitch activation page in your browser so you can approve WolfWave")
            .accessibilityIdentifier("openTwitchButton")
        }
        // Position the small "copied" toast near the copy button (top-right)
        .overlay(
            copyFeedbackView
                .padding(.trailing, DSSpace.s2)
                .offset(x: -8, y: -8),
            alignment: .topTrailing
        )
        .animation(reduceMotion ? nil : DSMotion.Spring.snappy, value: userCode)
    }

    // MARK: - Helpers

    /// Tap-anywhere copy path for the code container: copies the code, forwards
    /// `onCopy`, and shows the "Copied to clipboard" toast for ~1.3 seconds.
    /// The explicit ``CopyButton`` provides its own checkmark feedback.
    private func copyDeviceCode() {
        Pasteboard.copy(userCode)
        onCopy()

        withAnimation(reduceMotion ? nil : .easeInOut(duration: DSMotion.Duration.fast)) {
            showCopyFeedback = true
        }

        // Auto-dismiss the toast after a beat.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1300))
            withAnimation(reduceMotion ? nil : .easeInOut(duration: DSMotion.Duration.fast)) {
                showCopyFeedback = false
            }
        }
    }

    /// Opens the Twitch device activation URL in the user's default browser
    /// and forwards the action to the parent via `onActivate`.
    private func openActivationURL() {
        if ExternalLink.open(verificationURI) {
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
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous))
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
    .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg2))
    .padding(DSSpace.s8)
    .frame(width: 400)
}

