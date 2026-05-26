//
//  ConfigRequiredBanner.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-04.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
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
            .font(.system(size: DSFont.Size.sm))
            .foregroundStyle(.orange)
            .transition(.opacity)
        #endif
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    ConfigRequiredBanner(
        message: "Set DISCORD_CLIENT_ID in Config.xcconfig to enable this feature."
    )
    .padding()
    .frame(width: 420)
}
#endif
