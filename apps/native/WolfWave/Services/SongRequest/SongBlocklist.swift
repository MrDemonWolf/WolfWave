//
//  SongBlocklist.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Pluggable byte-level persistence for `SongBlocklist`.
///
/// Production wires this to UserDefaults; tests inject an in-memory
/// implementation to avoid the macos-26 GitHub runner's JSON-via-defaults
/// crash that surfaces as `malloc: pointer being freed was not allocated`
/// the first time the blocklist persists state inside an xctest host.
nonisolated protocol BlocklistStorage: AnyObject, Sendable {
    func read() -> Data?
    func write(_ data: Data)
}

/// Default UserDefaults-backed storage used by the running app.
nonisolated final class UserDefaultsBlocklistStorage: BlocklistStorage, @unchecked Sendable {
    private let key: String
    private let defaults: UserDefaults

    /// - Parameters:
    ///   - key: UserDefaults key holding the encoded blocklist.
    ///   - defaults: UserDefaults store to read/write. Defaults to `.standard`.
    init(key: String = "songRequestBlocklist", defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    /// Returns the raw stored bytes, or `nil` when the key is unset.
    func read() -> Data? { defaults.data(forKey: key) }

    /// Persists `data` under the configured key.
    func write(_ data: Data) { defaults.set(data, forKey: key) }
}

/// In-memory storage suitable for unit tests — no UserDefaults round-trip.
nonisolated final class InMemoryBlocklistStorage: BlocklistStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?

    /// - Parameter initialData: Optional seed payload returned by the first `read()`.
    init(initialData: Data? = nil) { self.data = initialData }

    /// Returns the currently-held payload (thread-safe via NSLock).
    func read() -> Data? { lock.withLock { data } }

    /// Replaces the held payload atomically.
    func write(_ data: Data) { lock.withLock { self.data = data } }
}

/// Manages a persistent blocklist of songs and artists.
///
/// Blocked entries are stored as JSON via the injected `BlocklistStorage`.
/// Matching is case-insensitive. Implemented as an `actor` so mutation safety
/// is enforced by the compiler — replaces the prior `final class + NSLock`.
actor SongBlocklist {
    // MARK: - Properties

    private var entries: [BlocklistItem] = []
    private let storage: BlocklistStorage

    // MARK: - Init

    /// Creates a blocklist backed by `storage`.
    ///
    /// - Parameter storage: Pluggable byte-level persistence. Defaults to
    ///   `UserDefaultsBlocklistStorage`. Tests inject `InMemoryBlocklistStorage`.
    init(storage: BlocklistStorage = UserDefaultsBlocklistStorage()) {
        self.storage = storage
        // Inline the load logic — calling an actor-isolated method from a
        // nonisolated init is a Swift 6 error. Mutating stored properties
        // directly during init is allowed and equivalent.
        if let data = storage.read(),
           let decoded = try? JSONCoders.camelCase.decode([BlocklistItem].self, from: data) {
            self.entries = decoded
        }
    }

    // MARK: - Public API

    /// All current blocklist entries.
    var allEntries: [BlocklistItem] { entries }

    /// Check if a song is blocked by title or artist.
    ///
    /// - Parameters:
    ///   - title: The song title to check.
    ///   - artist: The artist name to check.
    /// - Returns: `true` if the song or its artist is on the blocklist.
    func isBlocked(title: String, artist: String) -> Bool {
        entries.contains { entry in
            switch entry.type {
            case .song:
                return entry.value.lowercased() == title.lowercased()
            case .artist:
                return entry.value.lowercased() == artist.lowercased()
            }
        }
    }

    /// Add a song or artist to the blocklist.
    ///
    /// - Parameter item: The blocklist entry to add.
    func add(_ item: BlocklistItem) {
        guard !entries.contains(where: {
            $0.type == item.type && $0.value.lowercased() == item.value.lowercased()
        }) else { return }
        entries.append(item)
        save()
    }

    /// Remove an entry from the blocklist by its identifier.
    ///
    /// - Parameter id: Identifier of the `BlocklistItem` to delete. Unknown
    ///   IDs are a silent no-op.
    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    /// Remove all entries from the blocklist.
    func clearAll() {
        entries.removeAll()
        save()
    }

    // MARK: - Persistence

    /// Encodes a snapshot of `entries` and writes it through `storage`.
    /// Called after every mutation.
    private func save() {
        guard let data = try? JSONCoders.camelCaseEncoder.encode(entries) else { return }
        storage.write(data)
    }
}
