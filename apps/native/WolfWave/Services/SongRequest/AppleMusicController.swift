//
//  AppleMusicController.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-04-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit
import Carbon
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
    /// Music.app rejected or timed out while executing a playback command.
    case commandFailed(command: String, message: String)
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

/// Exact Music.app identity a vote-skip was opened against.
///
/// The track key is re-checked inside the final AppleScript event.
/// `revision` is a cheap in-process guard that rejects work as soon as the music
/// monitor has observed a replacement, without relying on actor task ordering.
struct PlaybackTarget: Equatable, Sendable {
    let trackKey: String
    let revision: UInt64
}

/// Music mutation selected when a target-bound vote passes.
///
/// `SongRequestService` decides queue policy; `AppleMusicController` executes
/// the selected action only if Music.app still has the exact target loaded.
enum TargetedPlaybackAction: Sendable {
    case nextTrack
    case request(SongRequestItem)
    case fallbackPlaylist(name: String)
    case stop
}

/// Abstracts Apple Music search and playback control so the live
/// `AppleMusicController` can be swapped for a stub in tests.
protocol AppleMusicControlling {
    /// Atomically reads player state and the loaded track's identity in one
    /// AppleScript round-trip. Returns `nil` when Music.app is closed or the read
    /// fails, so the auto-advance poll can treat a failed read as "no information"
    /// rather than a state change. See `PlaybackSnapshot`.
    ///
    /// `async` because callers already live in the structured-concurrency playback
    /// pipeline. `NSAppleScript` itself executes on the main thread, as required by
    /// Foundation's thread-safety contract.
    func playbackSnapshot() async -> PlaybackSnapshot?

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

    /// Performs a vote-skip mutation only while Music.app still has
    /// `targetTrackKey` loaded. The identity check and mutation execute in one
    /// AppleScript event, removing the read-then-command race.
    ///
    /// - Returns: `true` when the mutation ran; `false` for a stale target.
    func performTargetedPlayback(
        _ action: TargetedPlaybackAction,
        ifCurrentTrackKeyEquals targetTrackKey: String
    ) async throws -> Bool

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

    /// Whether Music.app itself can resolve the `WolfWave Requests` playlist.
    ///
    /// The requests playlist is created through the Apple Music **cloud** library
    /// API but played through AppleScript against Music.app's **local** library,
    /// so "the create call succeeded" is not evidence that playback can ever find
    /// it. This probe closes that gap by asking the same question playback asks.
    func requestsPlaylistLocalVisibility() async -> PlaylistLocalVisibility
}

extension AppleMusicControlling {
    /// Stubs and any future conformer default to "no information", which every
    /// caller already treats as "change nothing".
    func requestsPlaylistLocalVisibility() async -> PlaylistLocalVisibility { .unknown }
}

/// Whether Music.app can see the `WolfWave Requests` playlist in the local
/// library that AppleScript playback resolves against.
///
/// `unknown` is a genuine third state, not a failure: Music.app being closed or
/// an Apple Event timing out proves nothing about the playlist, so callers must
/// leave banners and toggles exactly as they are.
enum PlaylistLocalVisibility: Equatable, Sendable {
    /// Music.app resolves the playlist, so playback can address it.
    case visible
    /// Music.app answered and has no such playlist. Playback cannot work.
    case notVisible
    /// Music.app was closed or the probe failed. No conclusion.
    case unknown
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

    /// A structured AppleScript failure, preserving the Apple Event error number
    /// for callers that need to distinguish a quit target (`-600`) from another
    /// command failure.
    struct ScriptFailure: Error, Equatable, Sendable {
        /// AppleScript / Apple Event error number, when supplied by Foundation.
        let number: Int?
        /// Human-readable error detail suitable for logs and propagated errors.
        let message: String
    }

    /// Result of one script invocation. Command callers must inspect this instead
    /// of treating a missing string result as success.
    enum ScriptExecutionResult: Equatable, Sendable {
        /// Script completed. Many commands legitimately return no string value.
        case success(String?)
        /// Script compilation or execution failed.
        case failure(ScriptFailure)

        /// String result for read/query scripts; nil for failures and successful
        /// commands that do not return text.
        var output: String? {
            guard case .success(let value) = self else { return nil }
            return value
        }
    }

    /// AppleScript-level Apple Event timeouts, in seconds.
    ///
    /// Without an explicit `with timeout` block, an Apple Event to a wedged
    /// Music.app waits the AppleEvent default (about 60 seconds). `NSAppleScript`
    /// is main-thread-only, so a bounded timeout is also the UI-stall budget. The
    /// song-request poll probes must fail fast; playback commands get a little
    /// longer. A timeout is preserved as a structured failure rather than being
    /// mistaken for success.
    enum ScriptTimeout {
        /// Read-only state probes (`player state`, `current track`).
        static let probe = 2
        /// Playback and UI commands (`play`, `next track`, `stop`, `reveal`).
        static let command = 5
    }

    // MARK: - Properties

    /// Writes requested songs into the `WolfWave Requests` library playlist so
    /// they become playable via AppleScript on macOS 26. See `playNow`.
    private let libraryService = AppleMusicLibraryService()

    /// Catalog ids already added to the library this session. Playback retries
    /// re-enter `playNow` for the same song, so this prevents re-adding it (and
    /// piling up duplicate playlist entries) on every retry.
    private var addedSongIDs: Set<String> = []

    /// Compiled scripts are main-actor confined with the controller. The cache is
    /// bounded because request-track metadata is embedded in some script bodies.
    private var compiledScripts: [String: NSAppleScript] = [:]

    /// Maximum number of compiled scripts retained before the small cache clears.
    private static let compiledScriptsCap = 32

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
    var isMusicAppRunning: Bool { MusicProcess.isRunning }

    // MARK: - Playback State (via AppleScript → Music.app)

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
    func playbackSnapshot() async -> PlaybackSnapshot? {
        guard let pid = MusicProcess.pid else { return nil }
        let source = Self.musicTargetedScript("""
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
        """, seconds: ScriptTimeout.probe)
        guard let raw = runAppleScript(source, targetPID: pid).output else { return nil }
        return Self.parsePlaybackSnapshot(raw)
    }

    /// Parses the linefeed-delimited state and tab-framed track identity returned
    /// by `playbackSnapshot()`. Internal so exact framing edge cases are tested
    /// without sending Apple Events to Music.app.
    static func parsePlaybackSnapshot(_ raw: String) -> PlaybackSnapshot {
        let parts = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let stateText = parts.first.map(String.init) ?? ""
        let keyText = parts.count > 1 ? String(parts[1]) : ""

        let state: PlaybackSnapshot.State
        switch stateText {
        case "playing": state = .playing
        case "paused": state = .paused
        default: state = .stopped
        }

        // The tab is part of the exact name-and-artist identity. Trimming the
        // composite turns "Song\t" into "Song" and changes leading/trailing
        // metadata, so only the truly empty no-track sentinel maps to nil.
        return PlaybackSnapshot(state: state, trackKey: keyText.isEmpty ? nil : keyText)
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
        try await prepareForPlayback(song: song)
        let songID = song.id.rawValue

        // A freshly added track takes a moment to sync down before AppleScript
        // can see it, so the play is retried over a few seconds.
        guard try await playFromRequestsPlaylist(song: song) == .played else {
            // The playlist may have been deleted and rebuilt mid-session.
            // Drop the stale cache so the next attempt re-adds the song to the
            // fresh playlist rather than skipping the add step.
            addedSongIDs.remove(songID)
            libraryService.resetCachedPlaylistID()
            throw PlaybackError.notPlayable(title: song.title)
        }
        Log.debug("AppleMusicController: Now playing \"\(song.title)\" by \(song.artistName) from \(AppConstants.Music.requestsPlaylistName)", category: "SongRequest")
    }

    /// Ensures Music is running and the requested song belongs to the requests
    /// playlist. Shared by ordinary playback and target-bound vote replacement.
    private func prepareForPlayback(song: Song) async throws {
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
            } catch let error as CancellationError {
                throw error
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                    throw CancellationError()
                }
                Log.debug("AppleMusicController: Library add failed for \"\(song.title)\": \(error)", category: "SongRequest")
                throw PlaybackError.notPlayable(title: song.title)
            }
        }
    }

    private enum RequestPlaybackResult: Equatable {
        case played
        case staleTarget
        case unavailable
    }

    /// Plays a song from the `WolfWave Requests` playlist by matching title and
    /// artist, retrying briefly because a just-added track takes a moment to sync
    /// down from iCloud Music Library and become visible to AppleScript.
    ///
    /// Requires title + artist. A title-only fallback can select an unrelated
    /// song when two artists use the same title, so a mismatch remains queued.
    ///
    /// - Returns: Whether playback started, the vote target changed, or the
    ///   requested track never appeared within the retry window.
    private func playFromRequestsPlaylist(
        song: Song,
        replacing targetTrackKey: String? = nil
    ) async throws -> RequestPlaybackResult {
        let playlist = sanitizeForAppleScript(AppConstants.Music.requestsPlaylistName)
        let name = sanitizeForAppleScript(song.title)
        let artist = sanitizeForAppleScript(song.artistName)
        let guardSource = targetTrackKey.map { targetGuardSource(for: $0) } ?? ""
        let script = Self.musicTargetedScript("""
        \(guardSource)
        set ms to (every track of playlist "\(playlist)" whose name is "\(name)" and artist is "\(artist)")
        if (count of ms) > 0 then
            play (item 1 of ms)
            return "ok"
        end if
        return "miss"
        """, seconds: ScriptTimeout.command)

        var lastFailure: ScriptFailure?
        for attempt in 0..<5 {
            guard let pid = MusicProcess.pid else {
                throw PlaybackError.musicAppNotRunning
            }
            let result = await runAppleScriptPreservingFocus(script, targetPID: pid)
            switch result {
            case .success(let output):
                lastFailure = nil
                if output == "ok" { return .played }
                if output == "stale" { return .staleTarget }
            case .failure(let failure):
                if failure.number == -600 || failure.number == -609 {
                    throw PlaybackError.musicAppNotRunning
                }
                lastFailure = failure
            }
            if attempt < 4 {
                try await Task.sleep(for: .milliseconds(700))
            }
        }
        if let lastFailure {
            throw PlaybackError.commandFailed(
                command: "play request",
                message: lastFailure.message
            )
        }
        return .unavailable
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
    /// Throws when Music.app is closed or rejects the command. The event is
    /// addressed by bundle id; a quit Music is caught by the caller's
    /// `MusicProcess.pid` check and, decisively, by the in-script `is running`
    /// guard in `musicTargetedScript`. Nothing about the *address* prevents a
    /// relaunch, so that guard is load-bearing.
    func skipToNext() async throws {
        guard let pid = MusicProcess.pid else { throw PlaybackError.musicAppNotRunning }
        let result = runAppleScript(
            Self.musicTargetedScript("next track", seconds: ScriptTimeout.command),
            targetPID: pid
        )
        try requireCommandSuccess(result, command: "next track")
    }

    func performTargetedPlayback(
        _ action: TargetedPlaybackAction,
        ifCurrentTrackKeyEquals targetTrackKey: String
    ) async throws -> Bool {
        let command: String
        let body: String
        let preservesFocus: Bool
        switch action {
        case .request(let item):
            let song = item.song
            try await prepareForPlayback(song: song)
            switch try await playFromRequestsPlaylist(
                song: song,
                replacing: targetTrackKey
            ) {
            case .played:
                return true
            case .staleTarget:
                return false
            case .unavailable:
                addedSongIDs.remove(song.id.rawValue)
                libraryService.resetCachedPlaylistID()
                throw PlaybackError.notPlayable(title: song.title)
            }
        case .nextTrack:
            command = "next track"
            body = "next track"
            preservesFocus = false
        case .fallbackPlaylist(let name):
            command = "play fallback playlist"
            body = "play playlist \"\(sanitizeForAppleScript(name))\""
            preservesFocus = true
        case .stop:
            command = "stop"
            body = "stop"
            preservesFocus = false
        }

        guard let pid = MusicProcess.pid else {
            throw PlaybackError.musicAppNotRunning
        }
        let script = Self.musicTargetedScript("""
        \(targetGuardSource(for: targetTrackKey))
        \(body)
        return "ok"
        """, seconds: ScriptTimeout.command)
        let result: ScriptExecutionResult
        if preservesFocus {
            result = await runAppleScriptPreservingFocus(script, targetPID: pid)
        } else {
            result = runAppleScript(script, targetPID: pid)
        }
        try requireCommandSuccess(result, command: command)
        return result.output == "ok"
    }

    /// Rewind to the previous song in Music.app via AppleScript.
    ///
    /// Uses `previous track` (not `back track`) so Music.app moves to the
    /// prior queue entry rather than restarting the current track.
    ///
    /// Throws when Music.app is closed or rejects the command. The event is
    /// addressed by bundle id; a quit Music is caught by the caller's
    /// `MusicProcess.pid` check and, decisively, by the in-script `is running`
    /// guard in `musicTargetedScript`. Nothing about the *address* prevents a
    /// relaunch, so that guard is load-bearing.
    func previousTrack() async throws {
        guard let pid = MusicProcess.pid else { throw PlaybackError.musicAppNotRunning }
        let result = runAppleScript(
            Self.musicTargetedScript("previous track", seconds: ScriptTimeout.command),
            targetPID: pid
        )
        try requireCommandSuccess(result, command: "previous track")
    }

    /// Toggle Music.app's play/pause state. Routes through the focus-
    /// preserving runner so calling from the tray does not steal focus from
    /// the frontmost app.
    ///
    /// Throws when Music.app is closed or rejects the command. The event is
    /// addressed by bundle id; a quit Music is caught by the caller's
    /// `MusicProcess.pid` check and, decisively, by the in-script `is running`
    /// guard in `musicTargetedScript`. Nothing about the *address* prevents a
    /// relaunch, so that guard is load-bearing.
    func playPause() async throws {
        guard let pid = MusicProcess.pid else { throw PlaybackError.musicAppNotRunning }
        let result = await runAppleScriptPreservingFocus(
            Self.musicTargetedScript("playpause", seconds: ScriptTimeout.command),
            targetPID: pid
        )
        try requireCommandSuccess(result, command: "play/pause")
    }

    /// Stop playback in Music.app.
    ///
    /// No-op when Music.app is closed. There is nothing to stop, and a bare
    /// `tell application "Music"` would relaunch the app the user just quit.
    func clearPlayerQueue() async {
        guard let pid = MusicProcess.pid else { return }
        let result = runAppleScript(
            Self.musicTargetedScript("stop", seconds: ScriptTimeout.command),
            targetPID: pid
        )
        switch result {
        case .success:
            Log.debug("AppleMusicController: Music.app stopped", category: "SongRequest")
        case .failure(let failure):
            Log.warn(
                "AppleMusicController: Failed to stop Music.app: \(failure.message)",
                category: "SongRequest"
            )
        }
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
        guard let pid = MusicProcess.pid else { throw PlaybackError.musicAppNotRunning }
        let safeName = sanitizeForAppleScript(name)
        let script = Self.musicTargetedScript("""
        play playlist "\(safeName)"
        """, seconds: ScriptTimeout.command)
        let result = await runAppleScriptPreservingFocus(script, targetPID: pid)
        try requireCommandSuccess(result, command: "play fallback playlist")
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
    /// `ensureMusicRunningForReveal()` runs first and waits for the process, so
    /// the script's own liveness guard is normally a no-op here; if Music dies in
    /// that window the reveal becomes a logged no-op rather than a relaunch.
    ///
    /// Music is raised through `NSRunningApplication` rather than an AppleScript
    /// `activate` so macOS cooperative activation and the focus-restoration
    /// policy stay in AppKit's hands.
    func revealRequestsPlaylist() async {
        await ensureMusicRunningForReveal()
        guard let pid = MusicProcess.pid else {
            Log.warn("AppleMusicController: Could not launch Music.app to reveal requests playlist", category: "SongRequest")
            return
        }
        // Raising Music is a courtesy; macOS cooperative activation may decline it.
        // Reveal still runs either way, so the playlist is selected when the user switches over.
        if NSRunningApplication(processIdentifier: pid)?.activate() != true {
            Log.debug("AppleMusicController: Music did not come forward for reveal", category: "SongRequest")
        }
        let result = runAppleScript(
            revealScript(playlistName: AppConstants.Music.requestsPlaylistName),
            targetPID: pid
        )
        if case .failure(let failure) = result {
            Log.warn(
                "AppleMusicController: Could not reveal requests playlist: \(failure.message)",
                category: "SongRequest"
            )
        }
    }

    /// Asks Music.app whether it can resolve the `WolfWave Requests` playlist.
    ///
    /// Playback resolves `playlist "WolfWave Requests"` against Music.app's local
    /// library; the playlist is created against the Apple Music cloud library. A
    /// cloud playlist only reaches the local library through Sync Library, so the
    /// create call succeeding says nothing about whether playback can find it.
    /// This probe asks in the same terminology playback uses, which is the whole
    /// point: the setup gate must validate the layer that actually plays songs.
    ///
    /// Counts matching playlists rather than using `exists`, because a `reveal` or
    /// property read against a name that does not exist fails `-1708` and reads
    /// like "Music does not understand the command" instead of "no such playlist".
    ///
    /// Never launches Music.app: a closed Music yields `.unknown`, same as a
    /// timeout, so a quiet machine can never be mistaken for a broken setup.
    func requestsPlaylistLocalVisibility() async -> PlaylistLocalVisibility {
        guard let pid = MusicProcess.pid else { return .unknown }
        let name = sanitizeForAppleScript(AppConstants.Music.requestsPlaylistName)
        let source = Self.musicTargetedScript("""
        if (count of (every playlist whose name is "\(name)")) > 0 then return "yes"
        return "no"
        """, seconds: ScriptTimeout.probe)
        return Self.parseLocalVisibility(runAppleScript(source, targetPID: pid).output)
    }

    /// Maps the probe's script output to a visibility. Anything other than the two
    /// expected sentinels is `.unknown`, so a failed or truncated read is never
    /// read as a definitive "the playlist is gone".
    static func parseLocalVisibility(_ raw: String?) -> PlaylistLocalVisibility {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "yes": return .visible
        case "no": return .notVisible
        default: return .unknown
        }
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

    /// AppleScript source that reveals a playlist by name.
    ///
    /// Contains only `reveal`. Music is brought forward from Swift via
    /// `NSRunningApplication`, not an AppleScript `activate`, so macOS
    /// cooperative activation and the focus-restoration policy stay in AppKit's
    /// hands rather than being forced by the script.
    ///
    /// - Parameter playlistName: Playlist to select, sanitized before embedding.
    /// - Returns: AppleScript source addressed at Music.
    func revealScript(playlistName: String) -> String {
        Self.musicTargetedScript("""
        reveal playlist "\(sanitizeForAppleScript(playlistName))"
        """, seconds: ScriptTimeout.command)
    }

    /// AppleScript source that rejects a playback mutation unless the loaded
    /// track still has the exact name-and-artist key captured for the vote.
    func targetGuardSource(for trackKey: String) -> String {
        let expected = trackKey
            .components(separatedBy: "\t")
            .map { "\"\(sanitizeForAppleScript($0))\"" }
            .joined(separator: " & tab & ")
        return """
        set currentKey to ""
        try
            set currentKey to (get name of current track) & tab & (get artist of current track)
        end try
        if currentKey is not (\(expected)) then return "stale"
        """
    }

    /// Builds a script addressed at Music by bundle id, gated on Music actually
    /// being alive.
    ///
    /// ## Why not address by process id
    ///
    /// A raw kernel-pid descriptor is an Apple Event *address*, not an
    /// application specifier. `NSAppleScript` has no way to consume one: handed
    /// to `tell` as a value it arrives as opaque `«data kpid…»` with no
    /// terminology bound, so AppleScript evaluates the body against a
    /// meaningless object and every property read fails `-1728` while every verb
    /// fails `-1708`. Only ScriptingBridge can genuinely address by pid; see
    /// `MusicProcess`.
    ///
    /// ## Why the in-script running check
    ///
    /// A bundle-id `tell` is auto-launched by LaunchServices, which is how
    /// "WolfWave keeps reopening Music" shipped twice (PR #203, PR #273). Callers
    /// already resolve `MusicProcess.pid` first, but that leaves a check-then-send
    /// window across the Swift/AppleScript boundary. Re-checking *inside* the
    /// script narrows that window to the microseconds between two adjacent
    /// AppleScript statements. `is running` is answered without launching the
    /// target, and the `error` aborts before the `tell` block is ever entered.
    ///
    /// Raising `-600` (`procNotFound`) rather than returning a sentinel keeps a
    /// closed Music on the path callers already handle: `scriptFailure(from:)`
    /// reads the number straight out of Foundation's error dictionary, and both
    /// `requireCommandSuccess` and `playFromRequestsPlaylist` already translate
    /// `-600` into `PlaybackError.musicAppNotRunning`. This guard shipped in
    /// PR #392 and was lost in PR #410; do not remove it again.
    ///
    /// - Parameters:
    ///   - body: Music terminology to execute inside the `tell`.
    ///   - seconds: Apple Event reply timeout; see `ScriptTimeout`.
    static func musicTargetedScript(_ body: String, seconds: Int) -> String {
        """
        with timeout of \(seconds) seconds
            if application id "\(AppConstants.Music.bundleIdentifier)" is not running then error "Music is not running" number -600
            tell application id "\(AppConstants.Music.bundleIdentifier)"
        \(body)
            end tell
        end timeout
        """
    }

    /// Runs an AppleScript while preserving the user's focus when Music brings
    /// itself forward. Focus is restored only if Music is still frontmost after
    /// the short settling delay; a deliberate user switch is never overridden.
    @discardableResult
    private func runAppleScriptPreservingFocus(
        _ source: String,
        targetPID: pid_t
    ) async -> ScriptExecutionResult {
        let previousFrontApp = NSWorkspace.shared.frontmostApplication
        let result = runAppleScript(source, targetPID: targetPID)

        do {
            try await Task.sleep(for: .milliseconds(150))
        } catch {
            return result
        }

        let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if Self.shouldRestoreFocus(
            previousPID: previousFrontApp?.processIdentifier,
            currentPID: currentPID,
            musicPID: targetPID
        ) {
            previousFrontApp?.activate()
        }
        return result
    }

    /// Pure focus-restoration policy, internal so races are covered without
    /// activating real applications in tests.
    static func shouldRestoreFocus(
        previousPID: pid_t?,
        currentPID: pid_t?,
        musicPID: pid_t
    ) -> Bool {
        guard let previousPID, let currentPID else { return false }
        return previousPID != musicPID && currentPID == musicPID
    }

    /// Runs NSAppleScript on the main actor, Foundation's documented supported
    /// execution context. ScriptTimeout bounds how long a wedged target can
    /// block that actor.
    @MainActor
    @discardableResult
    private func runAppleScript(
        _ source: String,
        targetPID: pid_t
    ) -> ScriptExecutionResult {
        executeAppleScript(source, targetPID: targetPID)
    }

    /// Returns a cached compiled script, clearing the small bounded cache before
    /// dynamic track metadata can make it grow indefinitely.
    private func compiledScript(for source: String) -> NSAppleScript? {
        if let cached = compiledScripts[source] { return cached }
        guard let fresh = NSAppleScript(source: source) else { return nil }
        if compiledScripts.count >= Self.compiledScriptsCap {
            compiledScripts.removeAll(keepingCapacity: true)
        }
        compiledScripts[source] = fresh
        return fresh
    }

    /// Executes the script and preserves the Apple Event error number instead of
    /// collapsing every failure into a successful nil result.
    ///
    /// `targetPID` is a cheap pre-filter, not the address: callers resolve Music's
    /// pid first so a quit Music short-circuits before any script runs. The event
    /// itself is addressed by bundle id, because a raw kernel-pid descriptor is
    /// not an application specifier. See `musicTargetedScript` for why, and for
    /// the in-script `is running` guard that closes the check-then-send window
    /// this pre-filter alone would leave open.
    private func executeAppleScript(
        _ source: String,
        targetPID: pid_t
    ) -> ScriptExecutionResult {
        guard let script = compiledScript(for: source) else {
            return .failure(ScriptFailure(
                number: nil,
                message: "Could not create AppleScript from source."
            ))
        }

        var error: NSDictionary?
        let descriptor = script.executeAndReturnError(&error)
        if let error {
            let failure = Self.scriptFailure(from: error)
            Log.warn(
                "AppleMusicController: AppleScript error \(failure.number.map(String.init) ?? "unknown"): \(failure.message)",
                category: "SongRequest"
            )
            return .failure(failure)
        }
        return .success(descriptor.stringValue)
    }

    /// Converts Foundation's loosely typed AppleScript dictionary into the
    /// controller's structured, Sendable error value.
    static func scriptFailure(from error: NSDictionary) -> ScriptFailure {
        let number = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue
        let message = (error[NSAppleScript.errorMessage] as? String)
            ?? (error[NSAppleScript.errorBriefMessage] as? String)
            ?? "Unknown AppleScript error"
        return ScriptFailure(number: number, message: message)
    }

    /// Throws the public playback error corresponding to a failed command.
    private func requireCommandSuccess(
        _ result: ScriptExecutionResult,
        command: String
    ) throws {
        guard case .failure(let failure) = result else { return }
        if failure.number == -600 || failure.number == -609 {
            throw PlaybackError.musicAppNotRunning
        }
        throw PlaybackError.commandFailed(command: command, message: failure.message)
    }

    /// Launches Music only for the explicit Reveal action, then waits briefly for
    /// its process identifier to become observable before dispatching the event.
    private func ensureMusicRunningForReveal() async {
        guard MusicProcess.pid == nil else { return }
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.Music"
        ) else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        do {
            _ = try await NSWorkspace.shared.openApplication(
                at: applicationURL,
                configuration: configuration
            )
            for _ in 0..<20 {
                if MusicProcess.pid != nil { return }
                try await Task.sleep(for: .milliseconds(100))
            }
        } catch {
            Log.warn(
                "AppleMusicController: Could not launch Music.app: \(error.localizedDescription)",
                category: "SongRequest"
            )
        }
    }
}
