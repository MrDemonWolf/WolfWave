//
//  AppleMusicControllerTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 5/23/26.
//

import Foundation
import Testing

@testable import WolfWave

/// Covers `AppleMusicController.sanitizeForAppleScript(_:)` — the pure helper
/// used to escape user-supplied strings before they are embedded in an
/// AppleScript double-quoted literal. Playback paths (`playNow`, `playPause`,
/// …) dispatch through `NSAppleScript` and are not exercised here.
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

    @Test("Space (U+0020) preserved — boundary of control-char filter")
    func spacePreserved() {
        #expect(makeController().sanitizeForAppleScript("a b") == "a b")
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
