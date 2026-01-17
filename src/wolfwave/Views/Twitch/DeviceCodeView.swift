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
    
    @State private var isCodeCopied = false
    @State private var showCopyFeedback = false
    
    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 16) {
                // Section header
                VStack(alignment: .leading, spacing: 2) {
                    Text("Device Code")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                    
                    Text("Share this code during Twitch authorization")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                }
                
                // Code display with copy button
                HStack(spacing: 10) {
                    Text(userCode)
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                        .tracking(1.2)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 10)
                    
                    Button(action: copyDeviceCode) {
                        Image(systemName: isCodeCopied ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(isCodeCopied ? .green : .secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isCodeCopied ? "Copied to clipboard" : "Copy device code")
                }
                .padding(.horizontal, 10)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
                
                // Open link button with subtle styling
                Link(destination: URL(string: verificationURI) ?? URL(string: "https://www.twitch.tv/activate")!) {
                    HStack(spacing: 6) {
                        Text("Open twitch.tv/activate")
                            .font(.system(size: 13, weight: .medium))
                        
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .foregroundColor(.white)
                    .background(Color.accentColor)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            
            // Copy feedback toast
            if showCopyFeedback {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Copied to clipboard")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(6)
                    
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    
    private func copyDeviceCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(userCode, forType: .string)
        
        isCodeCopied = true
        onCopy()
        
        // Show feedback
        withAnimation(.easeInOut(duration: 0.2)) {
            showCopyFeedback = true
        }
        
        // Auto-dismiss feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
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
