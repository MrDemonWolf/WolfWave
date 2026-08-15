//
//  LogRecord.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-14.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// One parsed line from the on-disk log file.
///
/// This is the canonical reader for the format ``Log`` writes. The Debug tab's
/// log viewer, the diagnostics export composer, and any external tooling all go
/// through here, so the grammar has exactly one definition instead of one
/// writer and several ad-hoc regexes that drift apart.
///
/// ## Grammar
///
/// ```
/// <ISO8601>  <LEVEL>  <Category>  <File.swift:line>  <message>[ key=value…]
/// ```
///
/// The single invariant a reader can rely on:
///
/// > **A record starts with an ISO-8601 timestamp at column 0.
/// > A line starting with whitespace is a continuation of the record above it.**
///
/// Fields are separated by runs of two or more spaces. Values containing
/// whitespace, `=`, or `"` are double-quoted with backslash escaping.
///
/// See `apps/native/docs/logging-format.md` for the full write-up.
nonisolated struct LogRecord: Equatable, Sendable, Identifiable {

    /// One `key=value` pair from a line's structured tail.
    struct Field: Equatable, Sendable {
        let key: String
        let value: String
    }

    /// Stable identity for SwiftUI lists: byte offset is not available here, so
    /// the parse order index is assigned by ``parse(contents:)``.
    let id: Int

    /// When the record was written, with its original UTC offset resolved.
    let timestamp: Date

    /// The record's severity.
    let level: LogLevel

    /// Logical area tag, e.g. `"Twitch"`.
    let category: String

    /// `File.swift:42` source location of the call site.
    let location: String

    /// Free-form message body, with continuation lines folded back in.
    let message: String

    /// Ordered structured fields parsed off the tail of the message.
    let fields: [Field]

    /// The raw line(s) exactly as they appeared on disk.
    let raw: String

    // MARK: - Parsing

    /// Matches the leading fixed portion of a record.
    ///
    /// Anchored at column 0 and requiring the full ISO-8601 stamp is what makes
    /// continuation detection reliable: any line that fails this is either a
    /// continuation or corruption, never a half-parsed record.
    /// Written in extended (multi-line) form, where literal whitespace is
    /// ignored even inside a character class. Field separators are therefore
    /// spelled `\x20`, not a space in brackets.
    nonisolated(unsafe) private static let headerPattern = #/
        ^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}(?:[+-]\d{2}:\d{2}|Z))
        \x20{2,}(\S+)
        \x20{2,}(\S+)
        \x20{2,}(\S+)
        \x20{2,}(.*)$
    /#

    /// Parses a single line into a record.
    ///
    /// - Parameters:
    ///   - line: One line from the log file, without its trailing newline.
    ///   - id: Identity to assign, for list rendering.
    /// - Returns: The record, or `nil` when `line` is a continuation, a blank
    ///   line, or otherwise not a well-formed record start. A malformed line
    ///   never yields a partially populated record.
    static func parse(_ line: String, id: Int = 0) -> LogRecord? {
        guard let match = try? headerPattern.wholeMatch(in: line) else { return nil }

        let (_, stamp, levelToken, category, location, remainder) = match.output

        guard let level = LogLevel(rawValue: String(levelToken)),
              let timestamp = SharedFormatters.logTimestampISO.date(from: String(stamp))
        else { return nil }

        let (message, fields) = splitFields(from: String(remainder))

        return LogRecord(
            id: id,
            timestamp: timestamp,
            level: level,
            category: String(category),
            location: String(location),
            message: message,
            fields: fields,
            raw: line
        )
    }

    /// Parses whole log-file contents, folding continuation lines into the
    /// record that precedes them.
    ///
    /// Lines before the first valid record start (a truncated tail read, say)
    /// are dropped rather than guessed at.
    ///
    /// - Parameter contents: Raw text of a log file or a tail of one.
    /// - Returns: Records in file order.
    static func parse(contents: String) -> [LogRecord] {
        var records: [LogRecord] = []
        var pendingContinuations: [String] = []

        func flush() {
            guard !pendingContinuations.isEmpty, let last = records.popLast() else {
                pendingContinuations.removeAll()
                return
            }
            let folded = ([last.message] + pendingContinuations).joined(separator: "\n")
            records.append(
                LogRecord(
                    id: last.id,
                    timestamp: last.timestamp,
                    level: last.level,
                    category: last.category,
                    location: last.location,
                    message: folded,
                    fields: last.fields,
                    raw: ([last.raw] + pendingContinuations.map { "  " + $0 }).joined(separator: "\n")
                )
            )
            pendingContinuations.removeAll()
        }

        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            if let record = parse(text, id: records.count) {
                flush()
                records.append(record)
            } else if !records.isEmpty, text.first?.isWhitespace == true {
                // Continuation: strip the two-space frame the writer added.
                pendingContinuations.append(String(text.dropFirst(2)))
            }
            // Anything else (blank lines, pre-first-record noise) is dropped.
        }
        flush()

        return records
    }

    // MARK: - Field Splitting

    /// Splits a trailing run of `key=value` tokens off a message body.
    ///
    /// Walks tokens from the end and takes the longest suffix that all parse as
    /// fields. A message that genuinely ends in `word=word` is absorbed as a
    /// field, which is harmless: the text and the parsed field carry the same
    /// information.
    private static func splitFields(from remainder: String) -> (message: String, fields: [Field]) {
        let tokens = tokenize(remainder)
        guard !tokens.isEmpty else { return (remainder, []) }

        var firstFieldIndex = tokens.count
        var collected: [Field] = []

        for index in stride(from: tokens.count - 1, through: 0, by: -1) {
            guard let field = parseField(tokens[index].text) else { break }
            collected.append(field)
            firstFieldIndex = index
        }

        guard firstFieldIndex < tokens.count else { return (remainder, []) }

        let cutoff = tokens[firstFieldIndex].start
        let message = String(remainder[remainder.startIndex..<cutoff])
            .trimmingCharacters(in: .whitespaces)

        return (message, collected.reversed())
    }

    /// Splits on spaces that sit outside a quoted value.
    private static func tokenize(_ text: String) -> [(start: String.Index, text: String)] {
        var tokens: [(start: String.Index, text: String)] = []
        var current = ""
        var start = text.startIndex
        var inQuotes = false
        var escaped = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]

            if character == " " && !inQuotes && !escaped {
                if !current.isEmpty {
                    tokens.append((start, current))
                    current = ""
                }
            } else {
                // Every append path has to stamp the start index, including the
                // quote and escape branches: a token that opens with `"` would
                // otherwise inherit a stale offset and cut the message wrong.
                if current.isEmpty { start = index }

                if escaped {
                    escaped = false
                } else if character == "\\" && inQuotes {
                    escaped = true
                } else if character == "\"" {
                    inQuotes.toggle()
                }
                current.append(character)
            }

            index = text.index(after: index)
        }

        if !current.isEmpty { tokens.append((start, current)) }
        return tokens
    }

    /// Matches a bare `key=value` token.
    nonisolated(unsafe) private static let fieldPattern =
        #/^([A-Za-z_][A-Za-z0-9_.]*)=(.*)$/#

    /// Parses one token as a field, unquoting the value.
    private static func parseField(_ token: String) -> Field? {
        guard let match = try? fieldPattern.wholeMatch(in: token) else { return nil }
        return Field(key: String(match.output.1), value: unquote(String(match.output.2)))
    }

    /// Reverses ``Log``'s value quoting.
    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
        let inner = value.dropFirst().dropLast()

        var out = ""
        var escaped = false
        for character in inner {
            if escaped {
                switch character {
                case "n": out.append("\n")
                case "t": out.append("\t")
                default: out.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                out.append(character)
            }
        }
        return out
    }
}
