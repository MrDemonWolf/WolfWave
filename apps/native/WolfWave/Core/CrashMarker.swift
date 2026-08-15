//
//  CrashMarker.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-14.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// A parsed crash breadcrumb left by ``CrashReporter``.
///
/// The marker used to be write-only. `CrashReporter` recorded the signal name,
/// or an exception plus twenty backtrace frames, and the next launch checked
/// only that the file *existed* before deleting it. Everything it contained was
/// destroyed without ever reaching the log, the UI, or a bug report, so the one
/// artifact describing the crash was thrown away on the way to telling the user
/// a crash had happened.
///
/// This reads it. ``CrashReporter`` writes the current schema; the legacy shapes
/// are still parsed because a user upgrading across this change can have an old
/// marker sitting on disk from the crash that prompted the upgrade.
nonisolated struct CrashMarker: Equatable {

    /// First line of the current schema. Version bump goes here.
    static let header = "WOLFWAVE-CRASH 1"

    enum Kind: String, Equatable {
        case signal
        case exception
        case unknown
    }

    let kind: Kind

    /// e.g. `SIGSEGV`. Signal crashes only.
    let signalName: String?

    /// e.g. `NSInvalidArgumentException`. Exception crashes only.
    let exceptionName: String?

    /// Redacted exception reason, newlines already collapsed by the writer.
    let reason: String?

    /// Up to 20 redacted backtrace frames. Exception crashes only: a signal
    /// handler cannot walk the stack safely.
    let frames: [String]

    let date: Date?
    let pid: Int?
    let version: String?
    let build: String?

    // MARK: - Parsing

    /// Parses a marker file's contents.
    ///
    /// - Returns: The marker, or `nil` for empty/whitespace-only input.
    static func parse(_ text: String) -> CrashMarker? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard trimmed.hasPrefix(header) else { return parseLegacy(trimmed) }

        var values: [String: String] = [:]
        var frames: [String] = []

        for line in trimmed.split(separator: "\n").dropFirst() {
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<separator])
            let value = String(line[line.index(after: separator)...])
            if key == "frame" {
                frames.append(value)
            } else {
                values[key] = value
            }
        }

        return CrashMarker(
            kind: Kind(rawValue: values["kind"] ?? "") ?? .unknown,
            signalName: values["signal"],
            exceptionName: values["name"],
            reason: values["reason"],
            frames: frames,
            date: values["epoch"].flatMap(Double.init).map(Date.init(timeIntervalSince1970:)),
            pid: values["pid"].flatMap(Int.init),
            version: values["version"],
            build: values["build"]
        )
    }

    /// Parses the pre-schema shapes: a bare `SIGSEGV` line, or
    /// `EXCEPTION <name>` followed by a reason and raw frames.
    ///
    /// These carry no timestamp, pid, or build, which is exactly why the schema
    /// exists. Reading them is still better than showing the user nothing.
    private static func parseLegacy(_ text: String) -> CrashMarker? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first, !first.isEmpty else { return nil }

        if first.hasPrefix("EXCEPTION ") {
            return CrashMarker(
                kind: .exception,
                signalName: nil,
                exceptionName: String(first.dropFirst("EXCEPTION ".count)),
                reason: lines.count > 1 ? lines[1] : nil,
                frames: Array(lines.dropFirst(2)).filter { !$0.isEmpty },
                date: nil,
                pid: nil,
                version: nil,
                build: nil
            )
        }

        return CrashMarker(
            kind: .signal,
            signalName: first,
            exceptionName: nil,
            reason: nil,
            frames: [],
            date: nil,
            pid: nil,
            version: nil,
            build: nil
        )
    }

    // MARK: - Presentation

    /// One-line description for the recovery callout, e.g.
    /// `SIGSEGV at 14:03 on 2.1.1 (1841)`.
    var summary: String {
        var parts: [String] = []

        switch kind {
        case .signal:
            parts.append(signalName ?? "Fatal signal")
        case .exception:
            parts.append(exceptionName ?? "Uncaught exception")
        case .unknown:
            parts.append("Unexpected termination")
        }

        if let date {
            parts.append("at \(SharedFormatters.crashTimestamp.string(from: date))")
        }
        if let version {
            parts.append(build.map { "on \(version) (\($0))" } ?? "on \(version)")
        }

        return parts.joined(separator: " ")
    }

    /// Multi-line detail for the log and the diagnostics export.
    var detail: String {
        var lines = [summary]
        if let reason, !reason.isEmpty {
            lines.append("reason: \(reason)")
        }
        if let pid {
            lines.append("pid: \(pid)")
        }
        lines.append(contentsOf: frames.map { "  \($0)" })
        return lines.joined(separator: "\n")
    }
}
