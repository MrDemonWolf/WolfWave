//
//  LaunchAtLoginService.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-03-31.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit
import Foundation
import ServiceManagement

// MARK: - Launch At Login Service

/// Manages the app's login item registration via `SMAppService`.
///
/// Wraps `SMAppService.mainApp` to register or unregister the app as a
/// macOS login item (visible in System Settings → General → Login Items).
/// No helper bundle is required. The main app bundle is registered directly.
///
/// This requires macOS 13+, which WolfWave already mandates (macOS 26).
enum LaunchAtLoginService {

    // MARK: - Types

    /// Outcome of a register/unregister request.
    ///
    /// `.requiresApproval` means the registration succeeded but macOS is holding
    /// it pending the user's approval in System Settings → General → Login Items.
    /// The toggle should stay ON in that case (the request was accepted), with an
    /// "Approve in Login Items" affordance shown alongside it — silently reverting
    /// the toggle would hide a half-completed registration from the user.
    enum RegistrationOutcome: Hashable {
        /// Registered (or unregistered) and active.
        case success
        /// Registered but blocked behind the user's approval in Login Items.
        case requiresApproval
        /// `SMAppService` threw; nothing changed.
        case failure
    }

    // MARK: - Public API

    /// Whether the app is currently an active login item.
    ///
    /// Returns `true` for both `.enabled` and `.requiresApproval`: in the
    /// requires-approval state the registration request was accepted, so the
    /// toggle should reflect that the user opted in (even if macOS hasn't
    /// finished honoring it yet).
    static var isEnabled: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    /// Whether the login-item registration is waiting on the user's approval in
    /// System Settings → General → Login Items.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Registers or unregisters the app as a login item.
    ///
    /// - Parameter enabled: Pass `true` to register, `false` to unregister.
    /// - Returns: A ``RegistrationOutcome``. `.requiresApproval` is reported when a
    ///   registration is accepted but blocked behind the user's approval; treat it
    ///   as a success that keeps the toggle on.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> RegistrationOutcome {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            // Log the post-operation status so a requires-approval / not-yet-active
            // state is visible in Console rather than silently swallowed.
            let status = SMAppService.mainApp.status
            Log.info("LaunchAtLogin: \(enabled ? "Registered" : "Unregistered") (status: \(statusDescription(status)))", category: "App")
            if enabled && status == .requiresApproval {
                return .requiresApproval
            }
            return .success
        } catch {
            Log.error("LaunchAtLogin: Failed to \(enabled ? "register" : "unregister"): \(error.localizedDescription)", category: "App")
            return .failure
        }
    }

    /// Opens System Settings → General → Login Items so the user can approve a
    /// pending login-item registration.
    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - Private Helpers

    /// Human-readable label for an `SMAppService.Status` for logging.
    private static func statusDescription(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: return "enabled"
        case .requiresApproval: return "requiresApproval"
        case .notRegistered: return "notRegistered"
        case .notFound: return "notFound"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }
}
