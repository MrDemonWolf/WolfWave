//
//  ConfigRequiredBanner.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 4/4/26.
//

import SwiftUI

/// A warning banner shown when a required configuration value is missing.
///
/// Only rendered in DEBUG builds. Used in Discord and Twitch settings to
/// prompt developers to set up `Config.xcconfig` values.
///
/// Usage:
/// ```swift
/// ConfigRequiredBanner(message: "Set DISCORD_CLIENT_ID in Config.xcconfig to enable this feature.")
/// ```
struct ConfigRequiredBanner: View {

    // MARK: - Properties

    let message: String

    // MARK: - Body

    var body: some View {
        #if DEBUG
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(.orange)
            .transition(.opacity)
        #endif
    }
}
