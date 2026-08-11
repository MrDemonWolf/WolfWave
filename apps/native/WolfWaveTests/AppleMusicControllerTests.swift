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
/// double-quoted literal), the PID-addressed invocation descriptor, structured
/// error parsing, and focus-restoration policy. Playback paths (`playNow`,
/// `playPause`, …) dispatch through `NSAppleScript` and are not exercised
/// here.
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

    // MARK: - PID-targeted scripts

    @Test("PID-targeted script wraps Music terminology in a timeout handler")
    func pidTargetedScriptShape() {
        let script = AppleMusicController.pidTargetedScript("playpause", seconds: 5)

        #expect(script.contains("using terms from application \"Music\""))
        #expect(script.contains("on wolfWaveRun(musicTarget)"))
        #expect(script.contains("with timeout of 5 seconds"))
        #expect(script.contains("tell musicTarget"))
        #expect(script.contains("playpause"))
        #expect(script.contains("end wolfWaveRun"))
        #expect(!script.contains("tell application \"Music\""))
        #expect(!script.contains("if application \"Music\" is running"))
    }

    @Test("Invocation event carries a kernel process ID argument")
    func invocationEventTargetsPID() {
        let event = AppleMusicController.scriptInvocationEvent(targetPID: 4_242)
        let handler = event.paramDescriptor(forKeyword: AEKeyword(keyASSubroutineName))
        let arguments = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))
        let target = arguments?.atIndex(1)

        #expect(handler?.stringValue == "wolfWaveRun")
        #expect(target?.descriptorType == typeKernelProcessID)
        #expect(target?.int32Value == 4_242)
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
