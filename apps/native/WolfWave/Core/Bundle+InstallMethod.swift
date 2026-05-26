//
//  Bundle+InstallMethod.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-16.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

extension Bundle {
    /// Whether this bundle was installed via Homebrew (cask or formula).
    var isHomebrewInstall: Bool {
        Bundle.isHomebrewPath(bundlePath)
    }

    /// Path-matching helper exposed for testing.
    static func isHomebrewPath(_ path: String) -> Bool {
        let homebrewMarkers = [
            "/opt/homebrew/",
            "/usr/local/Caskroom/",
            "/usr/local/Cellar/",
            "/Homebrew/"
        ]
        return homebrewMarkers.contains { path.contains($0) }
    }
}
