//
//  SettingsNavigation.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-09-01.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Observation

/// Hand-off between whoever wants Settings opened somewhere specific (a deep
/// link, the menu bar, a Twitch re-auth banner) and the live `SettingsView`.
///
/// Replaces the old `selectedSettingsSection` UserDefaults hint, which was
/// read once on pane appear and so did nothing when the window was already
/// open. `SettingsView` observes `pending`, navigates, then clears it.
@MainActor
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()

    /// Destination waiting to be applied by `SettingsView`.
    var pending: SettingsDeepLink?

    /// Section slug currently flashing its highlight ring, if any.
    var highlighted: String?

    private init() {}
}
