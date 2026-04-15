//
//  AppleMusicController.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 4/8/26.
//

import AppKit
import Foundation
import MusicKit

/// Errors that can occur during song request playback.
enum PlaybackError: Error {
    /// Music.app is not currently running. The request has been buffered.
    case musicAppNotRunning
    /// The song has no Apple Music URL to open.
    case noURL
}

/// Abstracts Apple Music search and playback control for testability.
protocol AppleMusicControlling {
    var isPlaying: Bool { get }
    var isPaused: Bool { get }
    var isAuthorized: Bool { get }
    /// Whether Music.app is currently running (does NOT launch it).
    var isMusicAppRunning: Bool { get }
    var authStatus: AppleMusicController.AuthStatus { get }
    func search(query: String) async -> AppleMusicController.SearchResult
    func resolve(url: URL) async -> AppleMusicController.SearchResult
    func playNow(song: Song) async throws
    func enqueue(song: Song) async throws
    func skipToNext() async throws
    func clearPlayerQueue() async
    func rebuildPlayerQueue(from songs: [Song]) async throws
    func playFallbackPlaylist(name: String) async throws
}

/// Controls Apple Music playback and search via MusicKit (search) and AppleScript (playback).
///
/// MusicKit is used for catalog search and URL resolution only.
/// All playback commands use AppleScript to control Music.app directly,
/// so songs play through Music.app's audio session rather than within this app.
///
/// Note: macOS has no public API to insert songs into Music.app's native Up Next queue.
/// WolfWave manages playback sequence internally and tells Music.app to open each song
/// via `open location` when it is ready to play.
final class AppleMusicController: AppleMusicControlling {
    // MARK: - Types

    /// Authorization status for MusicKit.
    enum AuthStatus {
        case notDetermined
        case authorized
        case denied
        case restricted
    }

    /// Result of a song search.
    enum SearchResult {
        case found(Song)
        case notFound
        case error(String)
    }

    // MARK: - Authorization Status

    /// Current MusicKit authorization status.
    var authStatus: AuthStatus {
        switch MusicAuthorization.currentStatus {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .notDetermined
        }
    }

    /// Whether MusicKit is authorized for music access.
    var isAuthorized: Bool {
        authStatus == .authorized
    }

    /// Whether Music.app is currently running.
    ///
    /// Checked before sending any playback command. If Music.app is closed,
    /// song requests are buffered in WolfWave's queue until it re-opens.
    var isMusicAppRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == AppConstants.Music.bundleIdentifier
        }
    }

    // MARK: - Playback State (via AppleScript → Music.app)

    /// Whether Music.app is currently playing.
    var isPlaying: Bool {
        runAppleScript("""
        tell application "Music"
            if player state is playing then
                return "true"
            else
                return "false"
            end if
        end tell
        """) == "true"
    }

    /// Whether Music.app is paused (as opposed to stopped or finished).
    var isPaused: Bool {
        runAppleScript("""
        tell application "Music"
            if player state is paused then
                return "true"
            else
                return "false"
            end if
        end tell
        """) == "true"
    }

    // MARK: - Authorization

    /// Request MusicKit authorization from the user.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let status = await MusicAuthorization.request()
        return status == .authorized
    }

    // MARK: - Search (MusicKit)

    /// Search the Apple Music catalog for a song by text query.
    ///
    /// Auto-requests authorization if not yet determined.
    /// - Parameter query: The search text (song name, artist, etc.).
    /// - Returns: The search result.
    func search(query: String) async -> SearchResult {
        if authStatus == .notDetermined {
            let granted = await requestAuthorization()
            if !granted {
                return .error("Apple Music access not authorized")
            }
        }

        guard isAuthorized else {
            return .error("Apple Music access not authorized. Enable it in Settings → Song Requests.")
        }

        do {
            var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
            request.limit = 1
            let response = try await request.response()

            if let song = response.songs.first {
                return .found(song)
            }
            return .notFound
        } catch {
            return .error("Search failed: \(error.localizedDescription)")
        }
    }

    /// Resolve an Apple Music URL to a Song object.
    ///
    /// Used after oEmbed returns an Apple Music URL from a Spotify/YouTube link.
    func resolve(url: URL) async -> SearchResult {
        guard isAuthorized else {
            return .error("Apple Music access not authorized")
        }

        // Try to extract the song catalog ID from the URL
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let songID = components.queryItems?.first(where: { $0.name == "i" })?.value {
            do {
                let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(songID))
                let response = try await request.response()
                if let song = response.items.first {
                    return .found(song)
                }
            } catch {
                Log.debug("AppleMusicController: Failed to resolve by ID, falling back to URL search: \(error)", category: "SongRequest")
            }
        }

        // Fallback: extract song name from URL path and search
        let pathComponents = url.pathComponents
        if let songSlug = pathComponents.last {
            let searchTerm = songSlug.replacingOccurrences(of: "-", with: " ")
            return await search(query: searchTerm)
        }

        return .notFound
    }

    // MARK: - Playback (via AppleScript → Music.app)

    /// Open and play a song in Music.app immediately.
    ///
    /// Throws `PlaybackError.musicAppNotRunning` if Music.app is not running,
    /// so the caller can buffer the request and retry when Music.app launches.
    /// Uses `open location` with the song's Apple Music URL so Music.app handles
    /// playback through its own audio session. Refocuses the previously-frontmost
    /// app after opening so Music.app does not steal focus during streaming.
    func playNow(song: Song) async throws {
        guard isMusicAppRunning else {
            Log.debug("AppleMusicController: Music.app not running — buffering \"\(song.title)\"", category: "SongRequest")
            throw PlaybackError.musicAppNotRunning
        }

        if let musicURL = song.url {
            let urlString = musicURL.absoluteString
            let script = """
            tell application "Music"
                open location "\(urlString)"
            end tell
            """
            runAppleScriptPreservingFocus(script)
            Log.debug("AppleMusicController: Opening in Music.app — \"\(song.title)\" by \(song.artistName)", category: "SongRequest")
        } else {
            // Fallback: search local library and play
            let query = sanitizeForAppleScript("\(song.title) \(song.artistName)")
            let script = """
            tell application "Music"
                set searchResults to search playlist "Library" for "\(query)"
                if (count of searchResults) > 0 then
                    play item 1 of searchResults
                end if
            end tell
            """
            runAppleScriptPreservingFocus(script)
            Log.debug("AppleMusicController: Library fallback — \"\(song.title)\" by \(song.artistName)", category: "SongRequest")
        }
    }

    /// Note that a song has been queued internally.
    ///
    /// macOS has no public API to insert songs into Music.app's Up Next queue.
    /// The internal `SongRequestQueue` tracks sequence; `SongRequestService` calls
    /// `playNow` for each song when it's ready to play.
    func enqueue(song: Song) async throws {
        Log.debug("AppleMusicController: Queued internally — \"\(song.title)\" by \(song.artistName)", category: "SongRequest")
    }

    /// Skip the current song in Music.app via AppleScript.
    func skipToNext() async throws {
        runAppleScript("""
        tell application "Music"
            next track
        end tell
        """)
    }

    /// Stop playback in Music.app.
    func clearPlayerQueue() async {
        runAppleScript("""
        tell application "Music"
            stop
        end tell
        """)
        Log.debug("AppleMusicController: Music.app stopped", category: "SongRequest")
    }

    /// No-op on macOS — Music.app's Up Next queue is not scriptable.
    ///
    /// The internal queue in `SongRequestQueue` is the source of truth for ordering.
    func rebuildPlayerQueue(from songs: [Song]) async throws {
        Log.debug("AppleMusicController: Internal queue rebuilt with \(songs.count) songs", category: "SongRequest")
    }

    /// Play a named Apple Music playlist in Music.app as a fallback when the request queue is empty.
    ///
    /// Throws `PlaybackError.musicAppNotRunning` if Music.app is not running.
    func playFallbackPlaylist(name: String) async throws {
        guard isMusicAppRunning else { throw PlaybackError.musicAppNotRunning }
        let safeName = sanitizeForAppleScript(name)
        let script = """
        tell application "Music"
            play playlist "\(safeName)"
        end tell
        """
        runAppleScriptPreservingFocus(script)
        Log.debug("AppleMusicController: Fallback playlist '\(name)' started", category: "SongRequest")
    }

    // MARK: - Private Helpers

    /// Sanitize a string for safe inclusion in an AppleScript string literal.
    ///
    /// Escapes backslashes and double quotes, then strips ASCII control characters
    /// (U+0000–U+001F, U+007F) which could break out of AppleScript string literals.
    private func sanitizeForAppleScript(_ input: String) -> String {
        let escaped = input
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return escaped.unicodeScalars
            .filter { $0.value >= 32 && $0.value != 127 }
            .map(String.init)
            .joined()
    }

    /// Run an AppleScript while preserving the frontmost app's focus.
    ///
    /// `open location` in Music.app causes it to pop forward. This helper captures
    /// whichever app had focus before the script runs and refocuses it ~150ms later,
    /// so Music.app plays silently in the background during streaming.
    private func runAppleScriptPreservingFocus(_ source: String) {
        let previousFrontApp = NSWorkspace.shared.frontmostApplication
        runAppleScript(source)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            previousFrontApp?.activate(options: [.activateIgnoringOtherApps])
        }
    }

    /// Run an AppleScript and return the string result.
    @discardableResult
    private func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        let result = script?.executeAndReturnError(&error)

        if let error {
            Log.debug("AppleMusicController: AppleScript error: \(error)", category: "SongRequest")
            return nil
        }

        return result?.stringValue
    }
}
