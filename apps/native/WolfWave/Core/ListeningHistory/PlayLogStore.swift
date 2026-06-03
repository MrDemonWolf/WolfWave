//
//  PlayLogStore.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Append-only NDJSON store for the listening-history play log.
///
/// Each recorded play is one JSON line appended to a single file. A long-lived
/// `FileHandle` is kept open so appends are a `seekToEnd` + `write` with no
/// per-write `open`/`close` and no `fsync`. The gentlest possible profile on
/// SSD. The whole log is only ever rewritten by `replaceAll(with:)` (compaction
/// / retention), which is rare.
///
/// Thread Safety: all file state (`fileHandle`) is touched exclusively on the
/// serial `ioQueue`, so the store is safe to use from any thread. Hence the
/// `nonisolated` declaration and `@unchecked Sendable` conformance. Mirrors the
/// `Logger` file-I/O pattern.
nonisolated final class PlayLogStore: @unchecked Sendable {

    // MARK: - Properties

    /// URL of the NDJSON play log.
    let fileURL: URL

    /// Serial queue protecting all file I/O.
    private let ioQueue = DispatchQueue(
        label: "com.mrdemonwolf.wolfwave.playlog", qos: .utility
    )

    /// Open write handle, positioned at end of file. Only touched on `ioQueue`.
    private var fileHandle: FileHandle?

    /// Shared default coders. `PlayRecord` has explicit `CodingKeys` and
    /// its `Date` properties use the default `deferredToDate` strategy, so the
    /// strategy-free `JSONCoders.default` / `.defaultEncoder` match the
    /// on-disk format exactly.
    private let encoder = JSONCoders.defaultEncoder
    private let decoder = JSONCoders.default

    // MARK: - Init

    /// Creates a store writing to `directory`, or to
    /// `Application Support/WolfWave/History` when `directory` is `nil`.
    ///
    /// - Parameter directory: Override directory, primarily for tests. The
    ///   directory is created lazily on first write.
    init(directory: URL? = nil) {
        let dir = directory ?? PlayLogStore.defaultDirectory()
        fileURL = dir.appending(path: AppConstants.History.logFileName)
    }

    /// Resolves the default play-log directory under Application Support,
    /// falling back to the temporary directory if unavailable.
    private static func defaultDirectory() -> URL {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else {
            return FileManager.default.temporaryDirectory
                .appending(path: AppConstants.History.directoryName, directoryHint: .isDirectory)
        }
        return appSupport.appendingPathComponent(
            AppConstants.History.directoryName, isDirectory: true
        )
    }

    // MARK: - Public API

    /// Appends a single record as one NDJSON line. Returns immediately. The
    /// write happens asynchronously on `ioQueue`.
    ///
    /// - Parameter record: The play to persist.
    func append(_ record: PlayRecord) {
        ioQueue.async { [weak self] in
            self?.appendSync(record)
        }
    }

    /// Reads and decodes every record in the log.
    ///
    /// Malformed lines (e.g. from a partial write before a crash) are skipped
    /// rather than failing the whole load.
    ///
    /// - Returns: All recorded plays in file order (oldest first).
    func loadAll() -> [PlayRecord] {
        ioQueue.sync { readAllSync() }
    }

    /// Rewrites the log so it contains exactly `records`. Used for compaction
    /// and retention trimming. The only operation that rewrites the file.
    ///
    /// - Parameter records: The records the log should contain afterwards.
    func replaceAll(with records: [PlayRecord]) {
        ioQueue.sync { replaceSync(records) }
    }

    /// Deletes all recorded history, leaving an empty log file.
    func clear() {
        ioQueue.sync { replaceSync([]) }
    }

    /// Current on-disk size of the log in bytes (0 when the file is absent).
    var fileSizeBytes: Int {
        ioQueue.sync {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                  let size = attrs[.size] as? NSNumber else { return 0 }
            return size.intValue
        }
    }

    /// Flushes buffered data to disk. Call before the app terminates.
    func flush() {
        ioQueue.sync { try? fileHandle?.synchronize() }
    }

    /// Closes the file handle. Called at app termination.
    func shutdown() {
        ioQueue.sync {
            try? fileHandle?.synchronize()
            try? fileHandle?.close()
            fileHandle = nil
        }
    }

    deinit { try? fileHandle?.close() }

    // MARK: - Private (must run on ioQueue)

    /// Encodes one record and appends it as a single line. Runs on `ioQueue`.
    private func appendSync(_ record: PlayRecord) {
        guard let handle = openHandle() else { return }
        guard let json = try? encoder.encode(record),
              let line = String(data: json, encoding: .utf8) else {
            Log.warn("PlayLogStore: Failed to encode a play record", category: AppConstants.History.logCategory)
            return
        }
        guard let data = (line + "\n").data(using: .utf8) else { return }
        do {
            try handle.seekToEnd()
            handle.write(data)
        } catch {
            Log.error("PlayLogStore: Append failed: \(error.localizedDescription)", category: AppConstants.History.logCategory)
        }
    }

    /// Reads and decodes the whole log. Runs on `ioQueue`.
    private func readAllSync() -> [PlayRecord] {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return [] }
        var records: [PlayRecord] = []
        let newline = UInt8(0x0A)
        for lineData in data.split(separator: newline, omittingEmptySubsequences: true) {
            if let record = try? decoder.decode(PlayRecord.self, from: Data(lineData)) {
                records.append(record)
            }
        }
        return records
    }

    /// Rewrites the file with exactly `records`. Runs on `ioQueue`.
    private func replaceSync(_ records: [PlayRecord]) {
        try? fileHandle?.close()
        fileHandle = nil

        ensureDirectoryExists()
        let body = records
            .compactMap { try? encoder.encode($0) }
            .compactMap { String(data: $0, encoding: .utf8) }
            .joined(separator: "\n")
        let contents = records.isEmpty ? "" : body + "\n"
        do {
            try contents.data(using: .utf8)?.write(to: fileURL, options: .atomic)
        } catch {
            Log.error("PlayLogStore: Rewrite failed: \(error.localizedDescription)", category: AppConstants.History.logCategory)
        }
    }

    /// Returns the open write handle, creating the directory, file, and handle
    /// on first use. Runs on `ioQueue`.
    private func openHandle() -> FileHandle? {
        if let handle = fileHandle { return handle }
        ensureDirectoryExists()
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        let handle = FileHandle(forWritingAtPath: fileURL.path)
        fileHandle = handle
        return handle
    }

    /// Creates the containing directory if it does not exist. Runs on `ioQueue`.
    private func ensureDirectoryExists() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
