//
//  HistoryStoreSupport.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-07-18.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Shared filesystem helpers for the two on-disk listening-history stores
/// (`PlayLogStore`, `LifetimeTallyStore`), so default-directory resolution and
/// containing-directory creation live in one place.
///
/// Pure `FileManager` calls with no shared state; each store still invokes these
/// from its own `ioQueue`, so queue confinement is preserved. Does not merge the
/// stores' divergent NDJSON-append vs atomic-blob I/O bodies.
nonisolated enum HistoryStoreSupport {

    /// The default history directory under the `WolfWave/` Application Support
    /// container, falling back to the temporary directory when unavailable.
    static func defaultDirectory() -> URL {
        AppContainer.directory(AppConstants.History.directoryName)
    }

    /// Creates the containing directory of `fileURL` if it does not already exist.
    static func ensureDirectory(for fileURL: URL) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
