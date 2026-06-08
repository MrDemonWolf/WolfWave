//
//  AppleMusicController.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit
import Foundation
import MusicKit

/// Errors that can occur during song request playback.
enum PlaybackError: Error {
    /// Music.app is not currently running. The request has been buffered.
    case musicAppNotRunning
    /// The song was added to the library but could not be played from it yet.
    /// Usually the track is still syncing down from iCloud Music Library; can
    /// also mean the song is unavailable or the user has no active subscription.
    /// The caller keeps the request queued and retries.
    case notPlayable(title: String)
}

/// An atomic snapshot of Music.app's playback state and the loaded track's
/// identity, captured in a single AppleScript round-trip.
///
/// The song-request auto-advance poll needs the player state and the loaded
/// track to agree with each other. Reading them as separate AppleScript calls
/// let them disagree: the state read could return "playing" while a second call
/// for the current track timed out and came back empty. The boundary detector
/// then misread that empty value as "the song changed" and cut the streamer's
/// track off mid-play. One combined read keeps the two fields consistent, and a
/// failed read becomes a single `nil` the caller can treat as "no information"
/// instead of a false state transition.
struct PlaybackSnapshot: Equatable {
    /// Coarse player state. `fast forwarding` / `rewinding` collapse to
    /// `.playing`: a track is loaded and advancing in both.
    enum State {
        case playing
        case paused
        case stopped
    }

    /// The current coarse player state.
    let state: State

    /// Stable identity of the loaded track (its name + artist). Name and artist
    /// are intrinsic metadata that do not flake between reads the way a streamed
    /// catalog track's persistent ID can, so they make a reliable "is this still
    /// the same song" key. `nil` when no track is loaded or the metadata could
    /// not be read this tick; a `nil` key is treated as "unknown", never as a
    /// track boundary.
    let trackKey: String?
}

/// Abstracts Apple Music search and playback control so the live
/// `AppleMusicController` can be swapped for a stub in tests.
protocol AppleMusicControlling {
    /// `true` while Music.app reports an active playing state.
    var isPlaying: Bool { get }

    /// `true` while Music.app is paused (a track is loaded but not advancing).
    var isPaused: Bool { get }

    /// Stable identifier of the track Music.app currently has loaded, or `nil`
    /// when nothing is loaded or Music.app is closed. Used to detect when the
    /// streamer's own track changes so a queued request can take over at the
    /// boundary instead of cutting a song off mid-play.
    var currentTrackID: String? { get }

    /// Atomically reads player state and the loaded track's identity in one
    /// AppleScript round-trip. Returns `nil` when Music.app is closed or the read
    /// fails, so the auto-advance poll can treat a failed read as "no information"
    /// rather than a state change. See `PlaybackSnapshot`.
    func playbackSnapshot() -> PlaybackSnapshot?

    /// `true` once the user has granted MusicKit catalog access.
    var isAuthorized: Bool { get }

    /// `true` if Music.app is currently running. Reading this value never
    /// launches Music.app. It only inspects the workspace.
    var isMusicAppRunning: Bool { get }

    /// Current MusicKit authorization status.
    var authStatus: AppleMusicController.AuthStatus { get }

    /// Searches the catalog for the best match for `query`.
    func search(query: String) async -> AppleMusicController.SearchResult

    /// Resolves an Apple Music / Spotify / YouTube URL into a catalog track.
    func resolve(url: URL) async -> AppleMusicController.SearchResult

    /// Replaces the current track and starts playback immediately.
    func playNow(song: Song) async throws

    /// Appends a track to the playback queue without interrupting playback.
    func enqueue(song: Song) async throws

    /// Advances to the next track in Music.app's player queue.
    func skipToNext() async throws

    /// Rewinds to the previous track in Music.app's player queue.
    func previousTrack() async throws

    /// Toggles play/pause for whatever is currently loaded in Music.app.
    func playPause() async throws

    /// Clears Music.app's player queue and stops playback.
    func clearPlayerQueue() async

    /// Replaces the player queue with `songs` and starts the first item.
    func rebuildPlayerQueue(from songs: [Song]) async throws

    /// Starts a named Apple Music library playlist as the fallback source.
    func playFallbackPlaylist(name: String) async throws
}

/// Controls Apple Music playback and search via MusicKit (search) and AppleScript (playback).
///
/// MusicKit is used for catalog search and URL resolution only.
/// All playback commands use AppleScript to control Music.app directly,
/// so songs play through Music.app's audio session rather than within this app.
///
/// Note: macOS has no public API to insert songs into Music.app's native Up Next
/// queue (the AppleScript dictionary has no queue command, and the MusicKit
/// players that can (`ApplicationMusicPlayer` / `SystemMusicPlayer`) are not
/// available on macOS). WolfWave manages playback sequence internally. To play a
/// requested song it adds the song to the library via `AppleMusicLibraryService`
/// (required on macOS 26, where AppleScript can no longer play catalog songs that
/// aren't in the library) and then plays it from the `WolfWave Requests` playlist.
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

    // MARK: - Properties

    /// Writes requested songs into the `WolfWave Requests` library playlist so
    /// they become playable via AppleScript on macOS 26. See `playNow`.
    private let libraryService = AppleMusicLibraryService()

    /// Catalog ids already added to the library this session. Playback retries
    /// re-enter `playNow` for the same song, so this prevents re-adding it (and
    /// piling up duplicate playlist entries) on every retry.
    private var addedSongIDs: Set<String> = []

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
            $0.bundleIdentifier == AppConstants.Music.bundleIdentifier && !$0.isTerminated
        }
    }

    // MARK: - Playback State (via AppleScript → Music.app)

    /// Whether Music.app is currently playing.
    ///
    /// Returns `false` without scripting when Music.app is closed. A bare
    /// `tell application "Music"` auto-launches Music.app, so probing player
    /// state on a closed app would relaunch it. The exact behavior that kept
    /// Music popping back open after the user quit it (poll loop in
    /// `SongRequestService`).
    var isPlaying: Bool {
        guard isMusicAppRunning else { return false }
        return runAppleScript("""
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
    ///
    /// Returns `false` without scripting when Music.app is closed. See
    /// `isPlaying` for why probing a closed app must be avoided.
    var isPaused: Bool {
        guard isMusicAppRunning else { return false }
        return runAppleScript("""
        tell application "Music"
            if player state is paused then
                return "true"
            else
                return "false"
            end if
        end tell
        """) == "true"
    }

    /// Stable identifier of the track Music.app currently has loaded.
    ///
    /// Returns `nil` without scripting when Music.app is closed (see `isPlaying`
    /// for why probing a closed app must be avoided), and `nil` when no track is
    /// loaded. Wrapped in an AppleScript `try` because reading `current track`
    /// with nothing loaded raises an error rather than returning empty.
    var currentTrackID: String? {
        guard isMusicAppRunning else { return nil }
        let result = runAppleScript("""
        tell application "Music"
            try
                return persistent ID of current track
            on error
                return ""
            end try
        end tell
        """)
        guard let result, !result.isEmpty else { return nil }
        return result
    }

    /// Atomically reads player state plus the loaded track's name + artist in a
    /// single AppleScript call. See `PlaybackSnapshot` for why a combined read
    /// matters.
    ///
    /// Returns `nil` without scripting when Music.app is closed (a bare
    /// `tell application "Music"` would relaunch the app the user just quit), and
    /// `nil` when the script itself fails (an Apple Event to Music.app timed out),
    /// so the auto-advance poll can treat that tick as "no information" instead of
    /// a stop or a track change.
    ///
    /// Uses the AppleScript `linefeed` / `tab` constants as field separators
    /// rather than embedding raw control characters in the string literals, and
    /// wraps the track read in `try` so a momentary "no current track" yields an
    /// empty key (parsed back to `nil`) rather than aborting the whole script.
    func playbackSnapshot() -> PlaybackSnapshot? {
        guard isMusicAppRunning else { return nil }
        let raw = runAppleScript("""
        tell application "Music"
            set stateText to "stopped"
            if player state is playing then
                set stateText to "playing"
            else if player state is paused then
                set stateText to "paused"
            else if player state is fast forwarding then
                set stateText to "playing"
            else if player state is rewinding then
                set stateText to "playing"
            end if
            set keyText to ""
            try
                set keyText to (get name of current track) & tab & (get artist of current track)
            end try
            return stateText & linefeed & keyText
        end tell
        """)
        guard let raw else { return nil }

        let parts = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let stateText = parts.first.map(String.init) ?? ""
        let keyText = parts.count > 1 ? String(parts[1]) : ""

        let state: PlaybackSnapshot.State
        switch stateText {
        case "playing": state = .playing
        case "paused": state = .paused
        default: state = .stopped
        }

        let trimmedKey = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
        return PlaybackSnapshot(state: state, trackKey: trimmedKey.isEmpty ? nil : trimmedKey)
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

    /// Add a requested song to the library and play it from the `WolfWave
    /// Requests` playlist.
    ///
    /// macOS 26 (Tahoe) broke AppleScript playback of catalog songs that aren't
    /// in the user's library (`open location` for a catalog URL no longer starts
    /// playback), and there is no Up Next / "add to queue" AppleScript command.
    /// So the song is first added to the library via `AppleMusicLibraryService`
    /// (contained in the requests playlist, which also adds it to the library),
    /// then played from that playlist. Library tracks still play under Tahoe.
    ///
    /// - Throws: `PlaybackError.musicAppNotRunning` if Music.app is closed, so the
    ///   caller can buffer the request and retry on launch. `PlaybackError.notPlayable`
    ///   if the library add fails (no subscription, unavailable) or the added
    ///   track can't be played within the retry window (still syncing from iCloud
    ///   Music Library), so the caller keeps it queued and retries.
    func playNow(song: Song) async throws {
        guard isMusicAppRunning else {
            Log.debug("AppleMusicController: Music.app not running, buffering \"\(song.title)\"", category: "SongRequest")
            throw PlaybackError.musicAppNotRunning
        }

        // Add to the library once per song (retries re-enter here). A failure
        // here (e.g. no active subscription) means we can't play it, so surface
        // notPlayable and let the caller keep the request queued.
        let songID = song.id.rawValue
        if !addedSongIDs.contains(songID) {
            do {
                try await libraryService.addSongToRequestsPlaylist(song)
                addedSongIDs.insert(songID)
            } catch {
                Log.debug("AppleMusicController: Library add failed for \"\(song.title)\": \(error)", category: "SongRequest")
                throw PlaybackError.notPlayable(title: song.title)
            }
        }

        // A freshly added track takes a moment to sync down before AppleScript
        // can see it, so the play is retried over a few seconds.
        guard await playFromRequestsPlaylist(song: song) else {
            // The playlist may have been deleted and rebuilt mid-session.
            // Drop the stale cache so the next attempt re-adds the song to the
            // fresh playlist rather than skipping the add step.
            addedSongIDs.remove(songID)
            libraryService.resetCachedPlaylistID()
            throw PlaybackError.notPlayable(title: song.title)
        }
        Log.debug("AppleMusicController: Now playing \"\(song.title)\" by \(song.artistName) from \(AppConstants.Music.requestsPlaylistName)", category: "SongRequest")
    }

    /// Plays a song from the `WolfWave Requests` playlist by matching title and
    /// artist, retrying briefly because a just-added track takes a moment to sync
    /// down from iCloud Music Library and become visible to AppleScript.
    ///
    /// Matches title + artist first, then falls back to title-only within the
    /// (small) requests playlist so a minor artist-string difference (e.g. a
    /// "feat." credit) still resolves.
    ///
    /// - Returns: `true` once playback starts, `false` if the track never appeared
    ///   within the retry window.
    private func playFromRequestsPlaylist(song: Song) async -> Bool {
        let playlist = sanitizeForAppleScript(AppConstants.Music.requestsPlaylistName)
        let name = sanitizeForAppleScript(song.title)
        let artist = sanitizeForAppleScript(song.artistName)
        let script = """
        tell application "Music"
            try
                set ms to (every track of playlist "\(playlist)" whose name is "\(name)" and artist is "\(artist)")
                if (count of ms) is 0 then
                    set ms to (every track of playlist "\(playlist)" whose name is "\(name)")
                end if
                if (count of ms) > 0 then
                    play (item 1 of ms)
                    return "ok"
                end if
            end try
            return "miss"
        end tell
        """
        for attempt in 0..<5 {
            if runAppleScriptPreservingFocus(script) == "ok" { return true }
            if attempt < 4 { try? await Task.sleep(for: .milliseconds(700)) }
        }
        return false
    }

    /// Note that a song has been queued internally.
    ///
    /// macOS has no public API to insert songs into Music.app's Up Next queue.
    /// The internal `SongRequestQueue` tracks sequence; `SongRequestService` calls
    /// `playNow` for each song when it's ready to play.
    func enqueue(song: Song) async throws {
        Log.debug("AppleMusicController: Queued internally: \"\(song.title)\" by \(song.artistName)", category: "SongRequest")
    }

    /// Skip the current song in Music.app via AppleScript.
    ///
    /// No-op when Music.app is closed. A bare `tell application "Music"` would
    /// relaunch the app the user just quit.
    func skipToNext() async throws {
        guard isMusicAppRunning else { return }
        runAppleScript("""
        tell application "Music"
            next track
        end tell
        """)
    }

    /// Rewind to the previous song in Music.app via AppleScript.
    ///
    /// Uses `previous track` (not `back track`) so Music.app moves to the
    /// prior queue entry rather than restarting the current track.
    ///
    /// No-op when Music.app is closed. A bare `tell application "Music"` would
    /// relaunch the app the user just quit.
    func previousTrack() async throws {
        guard isMusicAppRunning else { return }
        runAppleScript("""
        tell application "Music"
            previous track
        end tell
        """)
    }

    /// Toggle Music.app's play/pause state. Routes through the focus-
    /// preserving runner so calling from the tray does not steal focus from
    /// the frontmost app.
    ///
    /// No-op when Music.app is closed. A bare `tell application "Music"` would
    /// relaunch the app the user just quit.
    func playPause() async throws {
        guard isMusicAppRunning else { return }
        runAppleScriptPreservingFocus("""
        tell application "Music"
            playpause
        end tell
        """)
    }

    /// Stop playback in Music.app.
    ///
    /// No-op when Music.app is closed. There is nothing to stop, and a bare
    /// `tell application "Music"` would relaunch the app the user just quit.
    func clearPlayerQueue() async {
        guard isMusicAppRunning else { return }
        runAppleScript("""
        tell application "Music"
            stop
        end tell
        """)
        Log.debug("AppleMusicController: Music.app stopped", category: "SongRequest")
    }

    /// No-op on macOS. Music.app's Up Next queue is not scriptable.
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

    /// Reveals (selects and scrolls to) the `WolfWave Requests` playlist in
    /// Music.app and brings Music forward, so the streamer can hit Share to make
    /// it public. macOS exposes no API to publish a playlist or generate its
    /// share link, so this is the setup shortcut: one click to the playlist
    /// instead of hunting for it in the sidebar.
    ///
    /// Deliberately launches Music.app if it is closed (the user asked to open
    /// it), unlike the playback probes that avoid relaunching a quit app.
    func revealRequestsPlaylist() {
        let name = sanitizeForAppleScript(AppConstants.Music.requestsPlaylistName)
        runAppleScript("""
        tell application "Music"
            activate
            try
                reveal playlist "\(name)"
            end try
        end tell
        """)
    }

    // MARK: - Private Helpers

    /// Sanitize a string for safe inclusion in an AppleScript string literal.
    ///
    /// Escapes backslashes and double quotes, then strips ASCII control characters
    /// (U+0000-U+001F, U+007F) which could break out of AppleScript string literals.
    func sanitizeForAppleScript(_ input: String) -> String {
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
    /// Playing in Music.app causes it to pop forward. This helper captures
    /// whichever app had focus before the script runs and refocuses it ~150ms later,
    /// so Music.app plays silently in the background during streaming.
    ///
    /// - Returns: The script's string result, so callers like the requests-playlist
    ///   poller can read whether playback started.
    @discardableResult
    private func runAppleScriptPreservingFocus(_ source: String) -> String? {
        let previousFrontApp = NSWorkspace.shared.frontmostApplication
        let result = runAppleScript(source)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            previousFrontApp?.activate()
        }
        return result
    }

    /// Run an AppleScript and return the string result.
    ///
    /// `NSAppleScript` is **not** thread-safe and must execute on the main
    /// thread (running it off-main can crash with a libdispatch queue assertion)
    /// or return a spurious nil. Most callers are already on the main actor,
    /// but `isPlaying`/`isPaused` are synchronous and can be read from the
    /// `SongRequestService` background poll loop, so bounce to main when the
    /// current thread isn't already it. The `Thread.isMainThread` guard avoids
    /// a `DispatchQueue.main.sync` deadlock when we're already on main.
    @discardableResult
    private func runAppleScript(_ source: String) -> String? {
        if Thread.isMainThread {
            return Self.executeAppleScript(source)
        }
        return DispatchQueue.main.sync { Self.executeAppleScript(source) }
    }

    /// Executes an `NSAppleScript` and returns its string result.
    ///
    /// Must be called on the main thread. See `runAppleScript`.
    private nonisolated static func executeAppleScript(_ source: String) -> String? {
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
