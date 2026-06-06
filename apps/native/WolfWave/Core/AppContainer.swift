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
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return base
            .appending(path: containerName, directoryHint: .isDirectory)
            .appending(path: sub, directoryHint: .isDirectory)
    }
}
