//
//  AppContainer.swift
//  WolfWave
//
//  Single owner of the app's Application Support container layout.
//

import Foundation

/// Resolves on-disk directories under the app's `WolfWave/` Application Support
/// container.
///
/// Every persistence site (logs, play history, crash markers, diagnostics,
/// artwork cache) routed through here so the `WolfWave/` prefix and the
/// "fall back to the temporary directory" policy live in exactly one place.
enum AppContainer {
    // MARK: - Properties

    /// Top-level container folder name under Application Support.
    nonisolated static let containerName = "WolfWave"

    // MARK: - Public Methods

    /// Returns `Application Support/WolfWave/<sub>`, falling back to
    /// `<temporary>/WolfWave/<sub>` when Application Support can't be resolved.
    ///
    /// This only composes the path. It does **not** create the directory.
    /// Callers that need the folder to exist (Logger, ArtworkService) keep
    /// their own `createDirectory` call.
    ///
    /// - Parameter sub: Leaf subdirectory under the container, e.g. `"Logs"`,
    ///   `"History"`, `"State"`, `"Diagnostics"`, `"Cache"`.
    /// - Returns: The composed directory URL.
    nonisolated static func directory(_ sub: String) -> URL {
        return root.appending(path: sub, directoryHint: .isDirectory)
    }

    /// The container root: `Application Support/WolfWave/` (or the temporary
    /// fallback). Composes the path only. Does not create the directory.
    nonisolated static var root: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return base.appending(path: containerName, directoryHint: .isDirectory)
    }

    /// Deletes the entire on-disk container (logs, listening history, artwork
    /// cache, crash markers, diagnostics) for a factory reset. Succeeds
    /// silently when the container doesn't exist.
    ///
    /// - Returns: `true` if the container is gone afterward, `false` if removal
    ///   failed.
    @discardableResult
    nonisolated static func wipe() -> Bool {
        let url = root
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            Log.error(
                "AppContainer: failed to wipe container - \(error.localizedDescription)",
                category: "Reset"
            )
            return false
        }
    }
}
