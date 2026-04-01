//
//  LaunchAtLoginService.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 3/31/26.
//

import Foundation
import ServiceManagement

// MARK: - Launch At Login Service

/// Manages the app's login item registration via `SMAppService`.
///
/// Wraps `SMAppService.mainApp` to register or unregister the app as a
/// macOS login item (visible in System Settings → General → Login Items).
/// No helper bundle is required — the main app bundle is registered directly.
///
/// This requires macOS 13+, which WolfWave already mandates (macOS 26).
enum LaunchAtLoginService {

    // MARK: - Public API

    /// Whether the app is currently registered as a login item.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the app as a login item.
    ///
    /// - Parameter enabled: Pass `true` to register, `false` to unregister.
    /// - Returns: `true` if the operation succeeded, `false` if `SMAppService` threw an error.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                Log.info("LaunchAtLogin: Registered as login item", category: "App")
            } else {
                try SMAppService.mainApp.unregister()
                Log.info("LaunchAtLogin: Unregistered from login items", category: "App")
            }
            return true
        } catch {
            Log.error("LaunchAtLogin: Failed to \(enabled ? "register" : "unregister"): \(error.localizedDescription)", category: "App")
            return false
        }
    }
}
