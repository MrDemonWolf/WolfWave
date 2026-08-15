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

/// Persists the cross-store history-clear intent before either data file is
/// mutated. A leftover marker is replayed on launch, making deletion resilient
/// to a crash between clearing the play log and the lifetime tally.
nonisolated final class HistoryClearMarkerStore: @unchecked Sendable {

    /// URL of the versioned clear-pending tombstone.
    let fileURL: URL

    private let ioQueue = DispatchQueue(
        label: "com.mrdemonwolf.wolfwave.history-clear", qos: .utility
    )
    private let beginOverride: (@Sendable () -> Bool)?
    private let completeOverride: (@Sendable () -> Bool)?

    init(
        directory: URL? = nil,
        beginOverride: (@Sendable () -> Bool)? = nil,
        completeOverride: (@Sendable () -> Bool)? = nil
    ) {
        let dir = directory ?? HistoryStoreSupport.defaultDirectory()
        fileURL = dir.appending(path: AppConstants.History.clearPendingFileName)
        self.beginOverride = beginOverride
        self.completeOverride = completeOverride
    }

    /// Whether an interrupted clear still needs to be completed.
    var isPending: Bool {
        ioQueue.sync {
            FileManager.default.fileExists(atPath: fileURL.path)
        }
    }

    /// Durably records clear intent before either history data store changes.
    @discardableResult
    func begin() -> Bool {
        ioQueue.sync {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return true
            }
            if let beginOverride, !beginOverride() {
                return false
            }
            HistoryStoreSupport.ensureDirectory(for: fileURL)
            do {
                try Data("1\n".utf8).write(to: fileURL, options: .atomic)
                return true
            } catch {
                Log.error(
                    "HistoryClearMarkerStore: Begin failed: \(error.localizedDescription)",
                    category: .history)
                return false
            }
        }
    }

    /// Removes the marker only after both data stores are known empty.
    @discardableResult
    func complete() -> Bool {
        ioQueue.sync {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return true
            }
            if let completeOverride, !completeOverride() {
                return false
            }
            do {
                try FileManager.default.removeItem(at: fileURL)
                return true
            } catch {
                Log.error(
                    "HistoryClearMarkerStore: Completion failed: \(error.localizedDescription)",
                    category: .history)
                return false
            }
        }
    }
}
