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
    let deviceCode: String
    let onAuthorizePressed: () -> Void
    let onCancelPressed: () -> Void
    
    @State private var isCodeCopied = false
    @State private var isWaiting = false
    @State private var showCopyFeedback = false
    
    var body: some View {
        ZStack {
            // Main content
            VStack(spacing: 0) {
                // Spacer for natural top breathing room
                VStack(spacing: 24) {
                    // Title and explanation
                    VStack(spacing: 8) {
                        Text("Reconnect to Twitch")
                            .font(.system(size: 18, weight: .semibold))
                            .tracking(-0.5)
                        
                        Text("Your session has expired. Authorize WolfWave to continue")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    
                    // Divider with subtle styling
                    Divider()
                        .padding(.vertical, 8)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                
                // Content area
                VStack(spacing: 20) {
                    if isWaiting {
                        // Native, minimal waiting state
                        VStack(spacing: 10) {
                            ProgressView()
                                .progressViewStyle(.circular)

                            Text("Waiting for authorization…")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
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
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                
                Spacer()
                
                // Action buttons - standard macOS layout at bottom
                HStack(spacing: 12) {
                    Spacer()

                    // Cancel button (text style, lower emphasis)
                    Button(action: {
                        isWaiting = false
                        onCancelPressed()
                    }) {
                        Text("Cancel")
                            .font(.system(size: 13, weight: .regular))
                    }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel")
                    .accessibilityIdentifier("deviceAuthCancelButton")

                    // Primary authorize button - smaller and subtler tint
                    Button(action: handleAuthorizePressed) {
                        Text("Authorize on Twitch")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Color(nsColor: NSColor.systemIndigo).opacity(0.9))
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel("Authorize on Twitch")
                    .accessibilityHint("Open Twitch activation page to authorize")
                    .accessibilityIdentifier("authorizeOnTwitchButton")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .frame(maxWidth: 440)
            .background(Color(.windowBackgroundColor))
            
            // Copy feedback toast
            if showCopyFeedback {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Copied to clipboard")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(6)
                    
                    Spacer()
                }
                .padding(16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    
    private func handleAuthorizePressed() {
        // Transition to waiting state
        withAnimation(.easeInOut(duration: 0.3)) {
            isWaiting = true
        }
        
        // Open browser after brief delay for visual feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let url = URL(string: "https://www.twitch.tv/activate?device_code=\(deviceCode)") {
                NSWorkspace.shared.open(url)
            }
            onAuthorizePressed()
        }
    }
    
    private func copyDeviceCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(deviceCode, forType: .string)
        
        isCodeCopied = true
        
        // Show toast feedback
        withAnimation(.easeInOut(duration: 0.2)) {
            showCopyFeedback = true
        }
        
        // Auto-dismiss feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showCopyFeedback = false
            }
        }
        
        // Reset button state
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isCodeCopied = false
        }
    }
}

/// The device code entry state view
private struct DeviceCodeEntryView: View {
    let deviceCode: String
    @Binding var isCodeCopied: Bool
    let onCopyTapped: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Instructions text
            VStack(alignment: .leading, spacing: 0) {
                Text("Device Code")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                    .padding(.bottom, 6)
                
                Text("Share this code with Twitch during authorization")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Device code field with copy button
            HStack(spacing: 10) {
                // Code display - monospaced for clarity
                Text(deviceCode)
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
                    .tracking(1.5)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
                    .accessibilityLabel("Device code")
                    .accessibilityValue(deviceCode)
                    .accessibilityIdentifier("deviceAuthCodeText")
                
                // Copy button
                Button(action: onCopyTapped) {
                    Image(systemName: isCodeCopied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(isCodeCopied ? .green : .secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isCodeCopied ? "Copied to clipboard" : "Copy device code")
                .accessibilityLabel(isCodeCopied ? "Copied to clipboard" : "Copy device code")
                .accessibilityIdentifier("deviceAuthCopyButton")
            }
            .padding(.horizontal, 12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)

            // Inline copy feedback placed just above the code field
            if isCodeCopied {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Copied to clipboard")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .padding(.bottom, 6)
            }
            
            // Subtle branding or helper text
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
                
                Text("This dialog will automatically close once authorized")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }
}



#Preview {
    TwitchDeviceAuthDialog(
        deviceCode: "ABCD-EFGH",
        onAuthorizePressed: { print("Authorize pressed") },
        onCancelPressed: { print("Cancel pressed") }
    )
    .frame(width: 440, height: 380)
}
