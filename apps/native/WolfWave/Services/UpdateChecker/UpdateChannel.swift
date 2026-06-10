//
//  UpdateChannel.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-09.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Which Sparkle update track the app follows.
///
/// - ``stable``: shipped releases. Uses `SUFeedURL` from Info.plist. Default.
/// - ``nightly``: opt-in dev builds straight off `main`. Points Sparkle at the
///   nightly appcast (`AppConstants.Update.nightlyFeedURL`) via
///   ``SparkleUpdaterService/feedURLString(for:)``. Newer, but can be unstable.
///
/// Persisted as the raw value under `AppConstants.UserDefaults.updateChannel`.
///
/// `nonisolated` so it stays usable off the main actor (the module defaults to
/// `MainActor` isolation): pure value type with no isolation needs, read from
/// tests and Sparkle delegate callbacks alike.
nonisolated enum UpdateChannel: String, CaseIterable, Identifiable, Sendable {
    case stable
    case nightly

    var id: String { rawValue }

    /// Short label for the settings picker.
    var title: String {
        switch self {
        case .stable: return "Stable"
        case .nightly: return "Nightly"
        }
    }

    /// True for tracks that ship pre-release, potentially unstable builds.
    var isPrerelease: Bool { self == .nightly }

    /// Resolves a stored raw value to a channel, falling back to ``stable`` for
    /// a missing or unrecognized value.
    static func from(rawValue: String?) -> UpdateChannel {
        guard let rawValue, let channel = UpdateChannel(rawValue: rawValue) else {
            return .stable
        }
        return channel
    }
}
