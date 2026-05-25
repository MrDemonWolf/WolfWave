//
//  TwitchDeviceAuthDialog.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import SwiftUI

/// Clean, modern native macOS authorization dialog for Twitch device login.
///
/// Follows macOS Human Interface Guidelines with:
/// - Calm, trustworthy tone
/// - Native system appearance (no web-style cards or heavy borders)
/// - Support for dark and light modes
/// - Clear visual hierarchy and typography
/// - Subtle Twitch branding
///
/// States:
/// - Initial: Shows device code and instructions
/// - Authorizing: Smooth transition to waiting state with tasteful spinner
struct TwitchDeviceAuthDialog: View {

    // MARK: - Properties

    let deviceCode: String
    let onAuthorizePressed: () -> Void
    let onCancelPressed: () -> Void
    
    @State private var isCodeCopied = false
    @State private var isWaiting = false
    @State private var showCopyFeedback = false

    // MARK: - Body

    var body: some View {
        ZStack {
            // Main content
            VStack(spacing: 0) {
                // Spacer for natural top breathing room
                VStack(spacing: DSSpace.s8) {
                    // Title and explanation
                    VStack(spacing: DSSpace.s2) {
                        Text("Reconnect to Twitch")
                            .font(.system(size: DSFont.Size.x18, weight: .semibold))
                            .tracking(-0.5)
                        
                        Text("Your session has expired. Authorize WolfWave to continue.")
                            .font(.system(size: DSFont.Size.base, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    
                    // Divider with subtle styling
                    Divider()
                        .padding(.vertical, DSSpace.s2)
                }
                .padding(.horizontal, DSSpace.s8)
                .padding(.vertical, DSSpace.s7)
                
                // Content area
                VStack(spacing: DSSpace.s7) {
                    if isWaiting {
                        // Native, minimal waiting state
                        VStack(spacing: DSSpace.s3) {
                            ProgressView()
                                .progressViewStyle(.circular)

                            Text("Waiting for authorization…")
                                .font(.system(size: DSFont.Size.base, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        // Code entry state
                        DeviceCodeEntryView(
                            deviceCode: deviceCode,
                            isCodeCopied: $isCodeCopied,
                            onCopyTapped: copyDeviceCode
                        )
                    }
                }
                .padding(.horizontal, DSSpace.s8)
                .padding(.vertical, DSSpace.s7)
                
                Spacer()
                
                // Action buttons - standard macOS layout at bottom
                HStack(spacing: DSSpace.s4) {
                    Spacer()

                    // Cancel button (text style, lower emphasis)
                    Button(action: {
                        isWaiting = false
                        onCancelPressed()
                    }) {
                        Text("Cancel")
                            .font(.system(size: DSFont.Size.base, weight: .regular))
                    }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel")
                    .accessibilityIdentifier("deviceAuthCancelButton")

                    // Primary authorize button - smaller and subtler tint
                    Button(action: handleAuthorizePressed) {
                        Text("Authorize on Twitch")
                            .font(.system(size: DSFont.Size.body, weight: .semibold))
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel("Authorize on Twitch")
                    .accessibilityHint("Open Twitch activation page to authorize")
                    .accessibilityIdentifier("authorizeOnTwitchButton")
                }
                .padding(.horizontal, DSSpace.s8)
                .padding(.vertical, DSSpace.s6)
            }
            .frame(maxWidth: 440)
            .background(Color(.windowBackgroundColor))
            
            // Copy feedback toast
            if showCopyFeedback {
                VStack {
                    HStack(spacing: DSSpace.s2) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Copied to clipboard")
                            .font(.system(size: DSFont.Size.body, weight: .medium))
                    }
                    .padding(.horizontal, DSSpace.s4)
                    .padding(.vertical, DSSpace.s2)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(6)
                    
                    Spacer()
                }
                .padding(DSSpace.s6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Helpers

    /// Transitions the dialog into the "waiting for authorization" state and
    /// opens `twitch.tv/activate?device_code=…` in the browser after a brief
    /// animation hold so the state change reads naturally.
    private func handleAuthorizePressed() {
        // Transition to waiting state
        withAnimation(.easeInOut(duration: DSMotion.Duration.slow)) {
            isWaiting = true
        }
        
        // Open browser after brief delay for visual feedback
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            if let encodedCode = deviceCode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: "https://www.twitch.tv/activate?device_code=\(encodedCode)") {
                NSWorkspace.shared.open(url)
            }
            onAuthorizePressed()
        }
    }
    
    /// Copies the device code to the pasteboard, shows the toast feedback,
    /// and resets both the toast and the copy button after 2 seconds.
    private func copyDeviceCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(deviceCode, forType: .string)
        
        isCodeCopied = true
        
        // Show toast feedback
        withAnimation(.easeInOut(duration: DSMotion.Duration.base)) {
            showCopyFeedback = true
        }
        
        // Auto-dismiss feedback and reset button state in sync
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeInOut(duration: DSMotion.Duration.base)) {
                showCopyFeedback = false
                isCodeCopied = false
            }
        }
    }
}

/// The device code entry state view
private struct DeviceCodeEntryView: View {

    // MARK: - Properties

    let deviceCode: String
    @Binding var isCodeCopied: Bool
    let onCopyTapped: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: DSSpace.s6) {
            // Instructions text
            VStack(alignment: .leading, spacing: 0) {
                Text("Device Code")
                    .font(.system(size: DSFont.Size.sm, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                    .padding(.bottom, DSSpace.s2)
                
                Text("Enter this code on Twitch to authorize")
                    .font(.system(size: DSFont.Size.body, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Device code field with copy button
            HStack(spacing: DSSpace.s3) {
                // Code display - monospaced for clarity
                Text(deviceCode)
                    .font(.system(size: DSFont.Size.xl, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .tracking(1.5)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, DSSpace.s4)
                    .accessibilityLabel("Device code")
                    .accessibilityValue(deviceCode)
                    .accessibilityIdentifier("deviceAuthCodeText")
                
                // Copy button
                Button(action: onCopyTapped) {
                    Image(systemName: isCodeCopied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: DSFont.Size.x15, weight: .regular))
                        .foregroundStyle(isCodeCopied ? .green : .secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isCodeCopied ? "Copied to clipboard" : "Copy device code")
                .accessibilityLabel(isCodeCopied ? "Copied to clipboard" : "Copy device code")
                .accessibilityIdentifier("deviceAuthCopyButton")
            }
            .padding(.horizontal, DSSpace.s4)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)

            // Inline copy feedback placed just above the code field
            if isCodeCopied {
                HStack(spacing: DSSpace.s2) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Copied to clipboard")
                        .font(.system(size: DSFont.Size.sm, weight: .medium))
                }
                .padding(.horizontal, DSSpace.s3)
                .padding(.vertical, DSSpace.s2)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .padding(.bottom, DSSpace.s2)
            }
            
            // Subtle branding or helper text
            HStack(spacing: DSSpace.s1) {
                Image(systemName: "info.circle")
                    .font(.system(size: DSFont.Size.sm, weight: .regular))
                    .foregroundStyle(.secondary)
                
                Text("This dialog will automatically close once authorized")
                    .font(.system(size: DSFont.Size.sm, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DSSpace.s1)
        }
    }
}



#Preview {
    TwitchDeviceAuthDialog(
        deviceCode: "ABCD-EFGH",
        onAuthorizePressed: { },
        onCancelPressed: { }
    )
    .frame(width: 440, height: 380)
}
