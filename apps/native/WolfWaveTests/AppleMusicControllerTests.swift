//
//  AppleMusicControllerTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-23.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Carbon
import Foundation
import Testing

@testable import WolfWave

/// Covers `AppleMusicController`'s pure helpers: `sanitizeForAppleScript(_:)`
/// (escapes user-supplied strings before they are embedded in an AppleScript
/// double-quoted literal), the generated script's addressing and liveness
/// guard, structured error parsing, and focus-restoration policy. Playback
/// paths (`playNow`, `playPause`, …) dispatch through `NSAppleScript` and are
/// not exercised here; use the Debug tab's Music access self-test for those.
@MainActor
@Suite("AppleMusicController Tests")
struct AppleMusicControllerTests {

    // MARK: - Fixture

    private func makeController() -> AppleMusicController {
        AppleMusicController()
    }

    // MARK: - Empty / Passthrough

    @Test("Empty string sanitizes to empty")
    func empty() {
        #expect(makeController().sanitizeForAppleScript("") == "")
    }

    @Test("Plain ASCII passes through unchanged")
    func plainASCII() {
        #expect(makeController().sanitizeForAppleScript("hello world") == "hello world")
    }

    @Test("Single quote is not escaped")
    func singleQuoteUntouched() {
        #expect(makeController().sanitizeForAppleScript("it's fine") == "it's fine")
    }

    // MARK: - Escaping

    @Test("Double quote is escaped to backslash-quote")
    func doubleQuoteEscaped() {
        // Input:  a"b      (3 chars)
        // Output: a\"b     (4 chars)
        let result = makeController().sanitizeForAppleScript("a\"b")
        #expect(result == "a\\\"b")
    }

    @Test("Backslash is escaped to double backslash")
    func backslashEscaped() {
        // Input:  a\b      (3 chars: a, \, b)
        // Output: a\\b     (4 chars: a, \, \, b)
        let result = makeController().sanitizeForAppleScript("a\\b")
        #expect(result == "a\\\\b")
    }

    @Test("Backslash-then-quote: backslash escaped first, then quote")
    func backslashThenQuoteOrder() {
        // Input is two characters: \ "
        // Pass 1 (\ → \\) yields three chars:  \ \ "
        // Pass 2 (" → \") yields four chars:   \ \ \ "
        let input = "\\\""
        let result = makeController().sanitizeForAppleScript(input)
        #expect(result == "\\\\\\\"")
        #expect(result.count == 4)
    }

    // MARK: - Unicode

    @Test("Accented letters and emoji preserved")
    func unicodePreserved() {
        let input = "café 🎵 日本"
        #expect(makeController().sanitizeForAppleScript(input) == input)
    }

    // MARK: - Control characters

    @Test("Newline stripped")
    func newlineStripped() {
        #expect(makeController().sanitizeForAppleScript("a\nb") == "ab")
    }

    @Test("Tab stripped")
    func tabStripped() {
        #expect(makeController().sanitizeForAppleScript("a\tb") == "ab")
    }

    @Test("Carriage return stripped")
    func carriageReturnStripped() {
        #expect(makeController().sanitizeForAppleScript("a\rb") == "ab")
    }

    @Test("Null byte stripped")
    func nullStripped() {
        let input = "a\u{0000}b"
        #expect(makeController().sanitizeForAppleScript(input) == "ab")
    }

    @Test("DEL (U+007F) stripped")
    func delStripped() {
        let input = "a\u{007F}b"
        #expect(makeController().sanitizeForAppleScript(input) == "ab")
    }

    @Test("Mixed printable + control: all control chars removed")
    func mixedControl() {
        let input = "a\nb\tc\u{0007}d"
        #expect(makeController().sanitizeForAppleScript(input) == "abcd")
    }

    @Test("Space (U+0020) preserved: boundary of control-char filter")
    func spacePreserved() {
        #expect(makeController().sanitizeForAppleScript("a b") == "a b")
    }

    // MARK: - Script targeting

    @Test("Script addresses Music by bundle id inside a timeout")
    func musicTargetedScriptShape() {
        let script = AppleMusicController.musicTargetedScript("playpause", seconds: 5)

        #expect(script.contains("with timeout of 5 seconds"))
        #expect(script.contains("tell application id \"com.apple.Music\""))
        #expect(script.contains("playpause"))
        #expect(script.contains("end timeout"))
    }

    @Test("Liveness guard runs before the tell block, not after")
    func musicTargetedScriptGuardsBeforeTell() {
        let script = AppleMusicController.musicTargetedScript("playpause", seconds: 5)

        // Ordering is the whole point. A bundle-id `tell` is auto-launched by
        // LaunchServices, so a running-check placed after it would relaunch the
        // Music the user just quit before it ever ran. That bug shipped twice
        // (PR #203, PR #273). The guard itself shipped in PR #392 and was lost
        // in PR #410, which is what broke every Apple Event in 2.1.0.
        let guardIndex = script.range(of: "is not running then error")?.lowerBound
        let tellIndex = script.range(of: "tell application id")?.lowerBound

        #expect(guardIndex != nil)
        #expect(tellIndex != nil)
        if let guardIndex, let tellIndex {
            #expect(guardIndex < tellIndex)
        }
    }

    @Test("Closed Music raises -600, the code callers already map to musicAppNotRunning")
    func musicTargetedScriptRaisesProcNotFound() {
        let script = AppleMusicController.musicTargetedScript("playpause", seconds: 5)

        // `requireCommandSuccess` and `playFromRequestsPlaylist` both branch on
        // -600. Any other number silently degrades a closed Music into a generic
        // commandFailed, which the request queue treats as a real failure rather
        // than "buffer and retry when Music comes back".
        #expect(script.contains("error \"Music is not running\" number -600"))
    }

    @Test("Reveal script contains only the reveal command")
    func revealScriptOmitsActivate() {
        let script = makeController().revealScript(playlistName: "WolfWave Requests")

        #expect(script.contains("reveal playlist \"WolfWave Requests\""))
        // Music is raised from Swift via NSRunningApplication so macOS
        // cooperative activation and focus restoration stay in AppKit's hands.
        #expect(!script.contains("activate"))
    }

    @Test("Reveal script escapes quotes in the playlist name")
    func revealScriptSanitizesName() {
        let script = makeController().revealScript(playlistName: "a\"b\nc")

        #expect(script.contains("reveal playlist \"a\\\"bc\""))
    }

    @Test("Script never addresses Music by a raw pid descriptor")
    func musicTargetedScriptRejectsPIDAddressing() {
        // Regression guard. Passing `NSAppleEventDescriptor(processIdentifier:)`
        // as a `tell` argument compiles and unit-tests clean, but at runtime
        // AppleScript sees an opaque «data kpid…» with no terminology: every
        // property read fails -1728 and every verb -1708. That silently killed
        // song requests, the now-playing card, and the setup gate on macOS 26,
        // and no test caught it because the shape was asserted, not the behavior.
        let script = AppleMusicController.musicTargetedScript("get player state", seconds: 5)

        #expect(!script.contains("musicTarget"))
        #expect(!script.contains("wolfWaveRun"))
        #expect(!script.contains("using terms from"))
    }

    @Test("Focus restores only when Music remains frontmost")
    func focusRestorationPolicy() {
        #expect(AppleMusicController.shouldRestoreFocus(
            previousPID: 10,
            currentPID: 20,
            musicPID: 20
        ))
        #expect(!AppleMusicController.shouldRestoreFocus(
            previousPID: 10,
            currentPID: 30,
            musicPID: 20
        ))
        #expect(!AppleMusicController.shouldRestoreFocus(
            previousPID: 20,
            currentPID: 20,
            musicPID: 20
        ))
    }

    @Test("AppleScript error dictionaries preserve number and message")
    func structuredScriptFailure() {
        let error = NSMutableDictionary()
        error[NSAppleScript.errorNumber] = NSNumber(value: -1_712)
        error[NSAppleScript.errorMessage] = "Timed out"

        let failure = AppleMusicController.scriptFailure(from: error)
        #expect(failure.number == -1_712)
        #expect(failure.message == "Timed out")
    }

    @Test("probe timeout is shorter than the command timeout")
    func timeoutBudgets() {
        // The song-request poll reads playbackSnapshot() every 2 seconds, so
        // probes must fail fast; commands get a little longer.
        #expect(AppleMusicController.ScriptTimeout.probe == 2)
        #expect(AppleMusicController.ScriptTimeout.command == 5)
        #expect(AppleMusicController.ScriptTimeout.probe < AppleMusicController.ScriptTimeout.command)
    }

    // MARK: - Playback Target Identity

    @Test("Snapshot parser preserves the empty-artist framing tab")
    func snapshotParserPreservesEmptyArtist() {
        let snapshot = AppleMusicController.parsePlaybackSnapshot("playing\nSong\t")

        #expect(snapshot == PlaybackSnapshot(state: .playing, trackKey: "Song\t"))
    }

    @Test("Snapshot parser preserves leading and trailing metadata whitespace")
    func snapshotParserPreservesMetadataWhitespace() {
        let key = " Song \t Artist "
        let snapshot = AppleMusicController.parsePlaybackSnapshot("paused\n\(key)")

        #expect(snapshot == PlaybackSnapshot(state: .paused, trackKey: key))
    }

    @Test("Target guard preserves an empty artist component")
    func targetGuardPreservesEmptyArtist() {
        let source = makeController().targetGuardSource(for: "Song\t")

        #expect(source.contains("if currentKey is not (\"Song\" & tab & \"\")"))
    }

    @Test("Target guard preserves metadata whitespace")
    func targetGuardPreservesMetadataWhitespace() {
        let source = makeController().targetGuardSource(for: " Song \t Artist ")

        #expect(source.contains(
            "if currentKey is not (\" Song \" & tab & \" Artist \")"))
    }

    // MARK: - Edge

    @Test("Very long input passes through without truncation")
    func longInput() {
        let input = String(repeating: "x", count: 2000)
        #expect(makeController().sanitizeForAppleScript(input) == input)
        #expect(makeController().sanitizeForAppleScript(input).count == 2000)
    }

    @Test("Combined: backslash + quote + control + unicode")
    func combined() {
        // Input chars: a, \, b, ", c, \n, é
        let input = "a\\b\"c\né"
        // After backslash escape: a\\b"c\né
        // After quote escape:     a\\b\"c\né
        // After control strip:    a\\b\"cé
        let result = makeController().sanitizeForAppleScript(input)
        #expect(result == "a\\\\b\\\"cé")
    }
}
