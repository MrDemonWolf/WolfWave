//
//  LogTailCursor.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-14.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Tracks position while tailing the log file, so a reader only ever pulls the
/// bytes it has not seen.
///
/// Split out from the view because this is the part that actually goes wrong:
/// re-reading the whole file every tick, losing the tail of a line that
/// straddles two reads, and silently reading past the end after the file
/// rotates or is cleared. All three are decided here, with no file I/O, so they
/// can be tested directly.
///
/// The caller owns the `FileHandle`: ask ``planRead(fileSize:primingBytes:)``
/// what to read, read it, then hand the text to ``consume(_:)``.
nonisolated struct LogTailCursor: Equatable {

    /// Byte offset already consumed. Everything before this has been returned.
    private(set) var offset: UInt64 = 0

    /// Trailing partial line held back until its newline arrives.
    private(set) var carry: String = ""

    /// Whether the first (priming) read has happened.
    private(set) var primed = false

    /// Decides which byte range to read next.
    ///
    /// - On the first call, primes from the last `primingBytes` of the file
    ///   rather than the whole thing: a 5 MB log would otherwise be parsed in
    ///   full just to show the most recent screenful.
    /// - When the file has shrunk, the log was cleared or rotated out from under
    ///   us. Reading from the old offset would seek past the end and return
    ///   nothing forever, so the cursor re-primes against the new file.
    /// - Otherwise, reads only what was appended since last time.
    ///
    /// - Parameters:
    ///   - fileSize: Current size of the log file in bytes.
    ///   - primingBytes: How much history to pull on the first read or after a
    ///     rotation.
    /// - Returns: The range to read, or `nil` when there is nothing new.
    mutating func planRead(fileSize: UInt64, primingBytes: UInt64) -> Range<UInt64>? {
        // First read, or the file shrank (cleared / rotated): start over from a
        // bounded window at the end.
        if !primed || fileSize < offset {
            primed = true
            carry = ""
            let start = fileSize > primingBytes ? fileSize - primingBytes : 0
            offset = fileSize
            return start < fileSize ? start..<fileSize : nil
        }

        guard fileSize > offset else { return nil }
        let start = offset
        offset = fileSize
        return start..<fileSize
    }

    /// Splits newly read text into complete lines.
    ///
    /// A read can land mid-line. The incomplete tail is held in ``carry`` and
    /// prepended to the next chunk, so a record is never handed to the parser in
    /// two halves (which would drop it, since half a line does not match the
    /// record header).
    ///
    /// - Parameter chunk: Text decoded from the planned byte range.
    /// - Returns: Only the lines terminated by a newline.
    mutating func consume(_ chunk: String) -> [String] {
        var pieces = (carry + chunk).components(separatedBy: "\n")
        // `components` always yields at least one element; the last is whatever
        // followed the final newline, which is "" when the chunk ended cleanly.
        carry = pieces.removeLast()
        return pieces
    }

    /// Drops all position state so the next plan re-primes.
    mutating func reset() {
        offset = 0
        carry = ""
        primed = false
    }
}
