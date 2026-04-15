//
//  SongBlocklist.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 4/8/26.
//

import Foundation

/// Manages a persistent blocklist of songs and artists.
///
/// Blocked entries are stored in UserDefaults as JSON. Matching is case-insensitive.
final class SongBlocklist {
    // MARK: - Properties

    private let lock = NSLock()
    private var entries: [BlocklistItem] = []
    private let storageKey = "songRequestBlocklist"

    // MARK: - Init

    init() {
        load()
    }

    // MARK: - Public API

    /// All current blocklist entries.
    var allEntries: [BlocklistItem] {
        lock.withLock { entries }
    }

    /// Check if a song is blocked by title or artist.
    ///
    /// - Parameters:
    ///   - title: The song title to check.
    ///   - artist: The artist name to check.
    /// - Returns: `true` if the song or its artist is on the blocklist.
    func isBlocked(title: String, artist: String) -> Bool {
        lock.withLock {
            entries.contains { entry in
                switch entry.type {
                case .song:
                    return entry.value.lowercased() == title.lowercased()
                case .artist:
                    return entry.value.lowercased() == artist.lowercased()
                }
            }
        }
    }

    /// Add a song or artist to the blocklist.
    ///
    /// - Parameter item: The blocklist entry to add.
    func add(_ item: BlocklistItem) {
        lock.withLock {
            // Avoid duplicates
            guard !entries.contains(where: {
                $0.type == item.type && $0.value.lowercased() == item.value.lowercased()
            }) else { return }
            entries.append(item)
        }
        save()
    }

    /// Remove an entry from the blocklist by its ID.
    func remove(id: UUID) {
        lock.withLock {
            entries.removeAll { $0.id == id }
        }
        save()
    }

    /// Remove all entries from the blocklist.
    func clearAll() {
        lock.withLock {
            entries.removeAll()
        }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = Foundation.UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([BlocklistItem].self, from: data) else {
            return
        }
        entries = decoded
    }

    private func save() {
        let snapshot = lock.withLock { entries }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        Foundation.UserDefaults.standard.set(data, forKey: storageKey)
    }
}
