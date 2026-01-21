//
//  TwitchDeviceAuthWindowController.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import SwiftUI
import AppKit

/// A window controller that presents the Twitch device auth dialog as a native macOS window.
/// This handles the dialog lifecycle and window management.
/// 
/// Features:
/// - Floating window that stays above other windows
/// - Minimal chrome (no minimize/zoom buttons)
/// - Centered on screen
/// - Follows macOS system appearance
/// - Transient behavior (doesn't appear in Expose)
class TwitchDeviceAuthWindowController: NSWindowController, NSWindowDelegate {
    
    // MARK: - Initialization
    init(deviceCode: String, onAuthorize: @escaping () -> Void, onCancel: @escaping () -> Void) {
        let hostingView = NSHostingView(
            rootView: TwitchDeviceAuthDialog(
                deviceCode: deviceCode,
                onAuthorizePressed: {
                    onAuthorize()
                },
                onCancelPressed: {
                    onCancel()
                }
            )
        )
        
        let frame = CGRect(x: 0, y: 0, width: 460, height: 420)
        let style: NSWindow.StyleMask = [.titled, .closable]
        let window = NSWindow(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
        window.contentView = hostingView
        
        super.init(window: window)
        
        // Configure window properties for macOS system dialog appearance
        window.title = "Reconnect to Twitch"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .transient]
        
        // Set delegate for window lifecycle management
        window.delegate = self
        
        // Disable resize and minimize for consistent, focused dialog
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        
        // Center window on screen
        window.center()
        
        // Add subtle shadow for depth
        window.hasShadow = true
        
        // Ensure window is not opaque for proper rendering
        window.isOpaque = false
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        // Clear the retained controller reference when window closes
        TwitchDeviceAuthWindow.retainedTwitchController = nil
    }
}

/// A SwiftUI wrapper for managing the dialog presentation.
/// Use this in your SwiftUI app to show the authorization dialog.
struct TwitchDeviceAuthWindow {
    let deviceCode: String
    let onAuthorize: () -> Void
    let onCancel: () -> Void
    
    // Retained reference to keep the window controller alive while the window is open
    static var retainedTwitchController: TwitchDeviceAuthWindowController?
    
    func show() {
        let windowController = TwitchDeviceAuthWindowController(
            deviceCode: deviceCode,
            onAuthorize: onAuthorize,
            onCancel: onCancel
        )
        // Retain the controller to prevent deallocation while window is open
        TwitchDeviceAuthWindow.retainedTwitchController = windowController
        windowController.showWindow(nil)
    }
}
