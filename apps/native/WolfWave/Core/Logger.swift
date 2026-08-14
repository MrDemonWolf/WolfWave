//
//  Logger.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-01-08.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import os

/// Typed log category. Use the enum form to avoid typos that silently route
/// a log line to a sibling category. String overloads on `Log` remain for
/// incremental migration.
enum LogCategory: String, CaseIterable {
    case app = "App"
    case twitch = "Twitch"
    case discord = "Discord"
    case music = "Music"
    case keychain = "Keychain"
    case network = "Network"
    case websocket = "WebSocket"
    case update = "Update"
    case songRequest = "SongRequest"
    case devTools = "DevTools"
    case dev = "Dev"
    case diagnostics = "Diagnostics"
    case onboarding = "Onboarding"
    case artwork = "Artwork"
    case whatsNew = "WhatsNew"
    case history = "History"
}

/// Severity classification used by every log line.
///
/// The raw value is the bare uppercase token written to the on-disk log file.
/// It is deliberately *not* emoji-prefixed: an emoji is multi-codepoint
/// (`ℹ️` is U+2139 U+FE0F), variable-width in bytes, and makes `grep -c ERROR`
/// ambiguous against message text. The Debug tab's log viewer colorizes by
/// level instead, and Console.app renders its own level column.
///
/// Severity ordering (lowest → highest): `.debug`, `.info`, `.warn`, `.error`.
enum LogLevel: String, CaseIterable {
    /// Verbose developer-only information. Suppressed in release builds.
    case debug = "DEBUG"

    /// Informational events that are useful at all times (lifecycle, state
    /// transitions, connection success).
    case info = "INFO"

    /// Recoverable problems or unexpected conditions that did not interrupt
    /// the user-visible flow.
    case warn = "WARN"

    /// Failures that produced an error result or aborted an operation.
    case error = "ERROR"
}

// `Log` is one cohesive namespace. Splitting the line-format and redaction
// helpers into an extension file would force widening a dozen `private` members
// to internal, since `private` is file-scoped in Swift.
// swiftlint:disable type_body_length

/// Structured logging utility.
///
/// ## Line format
///
/// Every record written to the log file follows one invariant:
///
/// > **A log record starts with an ISO-8601 timestamp at column 0.
/// > Continuation lines start with whitespace.**
///
/// ```
/// 2026-08-14T14:03:24.102-05:00  ERROR  Twitch        TwitchChatService.swift:812  Reconnect failed attempt=3 code=4003
/// ```
///
/// Fields, left to right: timestamp, level (padded), category (padded),
/// `File.swift:line` (padded), message, then an optional ` key=value` tail
/// from ``log(_:level:category:fields:file:line:)``. Fields are separated by
/// two or more spaces, so a parser can split on that run and take the message
/// as the remainder. ``LogRecord`` is the canonical reader; the grammar is
/// written up in `apps/native/docs/logging-format.md`.
///
/// Debug logs are only emitted in development builds (`DEBUG` flag).
/// Production builds only emit info, warning, and error logs.
///
/// Logs go to both the macOS unified logging system and a rotating file in the
/// app's Application Support directory. Use ``exportLogFile()`` for the URL.
///
/// ## Thread safety
///
/// All mutable file state (`fileHandle`, `_logFileURL`, `bannerPending`,
/// `lineCountCache`) is accessed exclusively on `fileQueue`, a serial dispatch
/// queue. The throttle table and the OSLog cache have their own locks.
///
/// ## Usage
///
/// ```swift
/// Log.info("Connected", category: "Twitch")
/// Log.error("Reconnect failed", category: "Twitch", fields: ["attempt": 3, "code": 4003])
/// Log.debug("Payload dump", category: "Dev")  // Only in development
/// ```
enum Log {

    /// Ordered `key=value` pairs appended to a log line.
    ///
    /// `KeyValuePairs` preserves declaration order and is expressible as a
    /// dictionary literal at the call site, so no new type is needed.
    typealias Fields = KeyValuePairs<String, any CustomStringConvertible>

    /// Whether debug logging is enabled (only in DEBUG builds)
    nonisolated private static var isDebugLoggingEnabled: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    // MARK: - Session

    /// Short random identifier for this process, emitted in the launch banner.
    ///
    /// Deliberately *not* repeated on every line. The banner marks the session
    /// boundary and a reader carries it forward, which costs nothing per line.
    nonisolated static let sessionID: String = {
        String(format: "%06x", UInt32.random(in: 0...0xFF_FFFF))
    }()

    // MARK: - Level Gate

    /// Numeric severity rank for `LogLevel`. Higher = more severe.
    nonisolated private static func rank(_ level: LogLevel) -> Int {
        switch level {
        case .debug: return 0
        case .info:  return 1
        case .warn:  return 2
        case .error: return 3
        }
    }

    /// Minimum severity that is emitted at all, to either sink.
    ///
    /// Defaults:
    /// - Under XCTest (CI / `xcodebuild test`): `.error`. Keeps unit-test runs
    ///   from flooding captured output, and from churning the shared log file.
    /// - Otherwise: `.debug`. Full chatter, same as historical behavior.
    ///
    /// Override with the `WOLFWAVE_LOG_LEVEL` env var (`silent` / `error` /
    /// `warn` / `info` / `debug`). `silent` suppresses everything.
    ///
    /// This gates the **file sink as well as OSLog**. It used to gate only
    /// OSLog, which meant the variable could not actually reduce disk volume
    /// despite its name saying otherwise.
    nonisolated private static let minRank: Int = {
        let env = ProcessInfo.processInfo.environment
        if let raw = env["WOLFWAVE_LOG_LEVEL"]?.lowercased() {
            switch raw {
            case "silent": return Int.max
            case "error":  return rank(.error)
            case "warn":   return rank(.warn)
            case "info":   return rank(.info)
            case "debug":  return rank(.debug)
            default: break
            }
        }
        let underTest = env["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTest") != nil
        return underTest ? rank(.error) : rank(.debug)
    }()

    // MARK: - OSLog

    /// Subsystem identifier used for all OSLog entries.
    nonisolated private static let subsystem = "com.mrdemonwolf.wolfwave"

    /// Cache of per-category `os.Logger` instances keyed by category name.
    /// Read/written under `osLoggerLock`.
    nonisolated(unsafe) private static var osLoggers: [String: os.Logger] = [:]

    /// Guards `osLoggers` against concurrent access from the logging callers.
    nonisolated private static let osLoggerLock = NSLock()

    /// Returns a cached `os.Logger` for `category`, creating one on first use.
    ///
    /// Logs appear in Console.app and Instruments. Filter by subsystem
    /// `com.mrdemonwolf.wolfwave` and use the Category column to isolate
    /// specific areas (e.g. "Twitch", "Discord", "Music").
    ///
    /// - Parameter category: Free-form category tag (e.g. `"Twitch"`).
    /// - Returns: The shared logger for that category.
    nonisolated private static func osLogger(for category: String) -> os.Logger {
        osLoggerLock.lock()
        defer { osLoggerLock.unlock() }
        if let existing = osLoggers[category] { return existing }
        let logger = os.Logger(subsystem: subsystem, category: category)
        osLoggers[category] = logger
        return logger
    }

    // MARK: - File Logging

    /// Maximum log file size before rotation (5 MB).
    nonisolated private static let maxLogFileSize: UInt64 = 5 * 1024 * 1024

    /// Number of rotated backups retained alongside the live log.
    ///
    /// Three (so `wolfwave.log` plus `.1`/`.2`/`.3`, 20 MB worst case). One
    /// backup was not enough: a tight reconnect loop rotates twice in seconds
    /// and evicts the original failure entirely.
    nonisolated private static let rotationDepth = 3

    /// Serial queue protecting all file I/O state.
    nonisolated private static let fileQueue = DispatchQueue(label: "com.mrdemonwolf.wolfwave.logger", qos: .utility)

    /// File handle for the current log file. Only access on `fileQueue`.
    nonisolated(unsafe) private static var fileHandle: FileHandle?

    /// URL of the current log file. Only access on `fileQueue`.
    nonisolated(unsafe) private static var _logFileURL: URL?

    /// Inode `fileHandle` was opened against, used to detect the file being
    /// replaced underneath us. Only access on `fileQueue`.
    nonisolated(unsafe) private static var openedInode: UInt64?

    /// Whether the session banner still needs writing. Only access on `fileQueue`.
    ///
    /// Set back to `true` by ``rotateLogFile(at:)`` so the fresh file also
    /// carries a banner; otherwise a rotated log would have no build to
    /// attribute its lines to.
    nonisolated(unsafe) private static var bannerPending = true

    /// Memoized `(size, modified, lines)` for ``logLineCount()``.
    /// Only access on `fileQueue`.
    nonisolated(unsafe) private static var lineCountCache: (size: Int64, modified: Date, lines: Int)?

    /// Returns the log file URL, creating the directory and file if needed.
    /// Must be called on `fileQueue`.
    nonisolated private static var logFileURL: URL {
        if let url = _logFileURL { return url }

        let logsDir = AppContainer.directory("Logs")

        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let url = logsDir.appending(path: "wolfwave.log")
        _logFileURL = url

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        return url
    }

    /// Writes a formatted log line to the log file.
    nonisolated private static func writeToFile(_ line: String) {
        fileQueue.async {
            let url = logFileURL

            // One stat serves both the rotation check and the staleness check.
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)

            if let size = attrs?[.size] as? UInt64, size > maxLogFileSize {
                rotateLogFile(at: url)
            }

            // The file can be replaced underneath a live handle: a factory
            // reset wipes the whole container, and `logFileURL` then recreates
            // an empty file at the same path. The old handle still points at
            // the unlinked inode, so every subsequent line would be written
            // into a file nobody can open again. Compare inodes and reopen.
            if let inode = attrs?[.systemFileNumber] as? UInt64,
               let opened = openedInode,
               inode != opened
            {
                try? fileHandle?.close()
                fileHandle = nil
            }

            // Open file handle if needed. Throwing FileHandle APIs only: the
            // legacy seekToEndOfFile()/write(_:) raise uncatchable ObjC
            // exceptions on disk-full / I/O error / stale handle, which would
            // crash the app from any log call.
            if fileHandle == nil {
                fileHandle = FileHandle(forWritingAtPath: url.path)
                _ = try? fileHandle?.seekToEnd()
                let opened = try? FileManager.default.attributesOfItem(atPath: url.path)
                openedInode = opened?[.systemFileNumber] as? UInt64
            }

            if bannerPending {
                bannerPending = false
                appendLine(sessionBannerLine())
            }

            appendLine(frameContinuations(line))
        }
    }

    /// Appends one already-formatted record plus a newline. Call on `fileQueue`.
    nonisolated private static func appendLine(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        do {
            try fileHandle?.write(contentsOf: data)
            lineCountCache = nil
        } catch {
            // Self-heal: drop the stale handle so the next write
            // reopens it instead of failing forever.
            try? fileHandle?.close()
            fileHandle = nil
            openedInode = nil
        }
    }

    /// Indents every line after the first by two spaces.
    ///
    /// Upholds the column-0 invariant: a reader can trust that any line
    /// starting with whitespace belongs to the record above it. Without this,
    /// a multi-line `error.localizedDescription` or a `CrashReporter` reason
    /// produces orphan lines with no level, category, or timestamp.
    nonisolated private static func frameContinuations(_ line: String) -> String {
        guard line.contains("\n") else { return line }
        return line
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { $0.offset == 0 ? String($0.element) : "  " + $0.element }
            .joined(separator: "\n")
    }

    /// Builds the per-launch banner identifying the build that wrote what follows.
    nonisolated private static func sessionBannerLine() -> String {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let arch = "arm64"
        #elseif arch(x86_64)
        let arch = "x86_64"
        #else
        let arch = "unknown"
        #endif

        return formatFileLine(
            "WolfWave session start",
            level: .info,
            category: LogCategory.app.rawValue,
            location: "Logger.swift:0",
            fields: [
                "session": sessionID,
                "version": AppConstants.AppInfo.shortVersion,
                "build": AppConstants.AppInfo.buildNumber,
                "os": "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)",
                "arch": arch,
                "pid": ProcessInfo.processInfo.processIdentifier
            ]
        )
    }

    /// Rotates the log file by shifting backups and starting fresh.
    nonisolated private static func rotateLogFile(at url: URL) {
        try? fileHandle?.close()
        fileHandle = nil
        openedInode = nil

        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        let backup = { (index: Int) in directory.appending(path: "wolfwave.log.\(index)") }

        // Shift down from the oldest so nothing is overwritten out of order.
        try? manager.removeItem(at: backup(rotationDepth))
        for index in stride(from: rotationDepth - 1, through: 1, by: -1) {
            try? manager.moveItem(at: backup(index), to: backup(index + 1))
        }
        try? manager.moveItem(at: url, to: backup(1))
        manager.createFile(atPath: url.path, contents: nil)

        lineCountCache = nil
        // The fresh file needs its own banner, or its lines cannot be
        // attributed to a build.
        bannerPending = true

        cleanupOldLogs(in: directory)
    }

    /// Removes rotated logs beyond ``rotationDepth``.
    nonisolated private static func cleanupOldLogs(in directory: URL) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        let kept: Set<String> = Set(
            ["wolfwave.log"] + (1...rotationDepth).map { "wolfwave.log.\($0)" }
        )

        let stale = files.filter { file in
            let name = file.lastPathComponent
            return name.hasPrefix("wolfwave.log") && !kept.contains(name)
        }
        for file in stale {
            try? fileManager.removeItem(at: file)
        }
    }

    // MARK: - Public API

    /// Writes a log line at the given level. Prefer the convenience entry
    /// points (`debug`, `info`, `warn`, `error`) over calling `log` directly.
    ///
    /// The message and every field value are run through `redactSensitiveInfo`
    /// before either sink receives them; OSLog entries are marked `.public`
    /// because PII redaction has already happened.
    ///
    /// - Parameters:
    ///   - message: Free-form message body.
    ///   - level: Severity classification. Defaults to `.info`.
    ///   - category: Logical area tag for filtering in Console.app.
    ///   - fields: Optional ordered `key=value` pairs appended to the line.
    ///   - file: Auto-captured `#fileID`.
    ///   - line: Auto-captured `#line`.
    nonisolated static func log(
        _ message: String,
        level: LogLevel = .info,
        category: String = "App",
        fields: Fields = [:],
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        // Suppress .debug writes in release builds regardless of call-site entry
        // path. Log.debug() has its own @autoclosure guard, but a direct call to
        // Log.log(..., level: .debug) would otherwise bypass that suppression and
        // write to disk in a release build.
        if level == .debug && !isDebugLoggingEnabled { return }
        guard rank(level) >= minRank else { return }

        let redactedMessage = redactSensitiveInfo(message)
        let location = sourceLocation(file: file, line: line)
        let tail = renderFields(fields)

        writeToFile(
            formatFileLine(
                redactedMessage,
                level: level,
                category: category,
                location: location,
                renderedFields: tail
            )
        )

        // OSLog → Xcode console + Console.app + Instruments.
        // Source location appended so it's clickable in Xcode 16+.
        // Messages are marked .public since PII has already been redacted above.
        let logger = osLogger(for: category)
        let osMessage = "\(redactedMessage)\(tail)  (\(location))"
        switch level {
        case .debug: logger.debug("\(osMessage, privacy: .public)")
        case .info:  logger.info("\(osMessage, privacy: .public)")
        case .warn:  logger.warning("\(osMessage, privacy: .public)")
        case .error: logger.error("\(osMessage, privacy: .public)")
        }
    }

    /// Convenience entry point for `.debug` logs.
    ///
    /// The `@autoclosure` lets callers pass a string-interpolated expression
    /// that is only evaluated when DEBUG logging is enabled. Release builds
    /// skip the work entirely.
    nonisolated static func debug(
        _ message: @autoclosure () -> String,
        category: String = "App",
        fields: Fields = [:],
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        guard isDebugLoggingEnabled else { return }
        log(message(), level: .debug, category: category, fields: fields, file: file, line: line)
    }

    /// Convenience entry point for `.info` logs.
    nonisolated static func info(
        _ message: String,
        category: String = "App",
        fields: Fields = [:],
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        log(message, level: .info, category: category, fields: fields, file: file, line: line)
    }

    /// Convenience entry point for `.warn` logs.
    nonisolated static func warn(
        _ message: String,
        category: String = "App",
        fields: Fields = [:],
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        log(message, level: .warn, category: category, fields: fields, file: file, line: line)
    }

    /// Convenience entry point for `.error` logs. Schedules a flush so the
    /// entry survives a crash that follows the call site.
    nonisolated static func error(
        _ message: String,
        category: String = "App",
        fields: Fields = [:],
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        log(message, level: .error, category: category, fields: fields, file: file, line: line)
        scheduleFlush()
    }

    // MARK: - Typed-category overloads
    //
    // Forward to the string-keyed implementations. Prefer these at new call
    // sites so the category name is enum-checked rather than free-form string.

    nonisolated static func log(
        _ message: String,
        level: LogLevel = .info,
        category: LogCategory,
        fields: Fields = [:],
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        log(message, level: level, category: category.rawValue, fields: fields, file: file, line: line)
    }

    nonisolated static func debug(
        _ message: @autoclosure () -> String,
        category: LogCategory,
        fields: Fields = [:],
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        guard isDebugLoggingEnabled else { return }
        log(message(), level: .debug, category: category.rawValue, fields: fields, file: file, line: line)
    }

    nonisolated static func info(
        _ message: String,
        category: LogCategory,
        fields: Fields = [:],
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        log(message, level: .info, category: category.rawValue, fields: fields, file: file, line: line)
    }

    nonisolated static func warn(
        _ message: String,
        category: LogCategory,
        fields: Fields = [:],
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        log(message, level: .warn, category: category.rawValue, fields: fields, file: file, line: line)
    }

    nonisolated static func error(
        _ message: String,
        category: LogCategory,
        fields: Fields = [:],
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        log(message, level: .error, category: category.rawValue, fields: fields, file: file, line: line)
        scheduleFlush()
    }

    // MARK: - Line Format

    /// Column width of the padded level field.
    nonisolated static let levelWidth = 5

    /// Column width of the padded category field.
    nonisolated static let categoryWidth = 12

    /// Column width of the padded `File.swift:line` field.
    ///
    /// Longer locations overflow rather than truncate. Truncating would break
    /// the click-through to a source line, which is the whole point of the
    /// field; a handful of ragged lines is the cheaper cost.
    nonisolated static let locationWidth = 34

    /// Pads `value` to at least `width` characters. Never truncates.
    nonisolated private static func pad(_ value: String, to width: Int) -> String {
        let deficit = width - value.count
        guard deficit > 0 else { return value }
        return value + String(repeating: " ", count: deficit)
    }

    /// Builds the exact line written to the on-disk log file.
    ///
    /// `<ISO timestamp>  <LEVEL>  <Category>  <File.swift:line>  <message>[ k=v…]`
    ///
    /// Message is assumed already redacted by the caller; `renderedFields` is
    /// assumed already redacted and quoted by ``renderFields(_:)``.
    nonisolated private static func formatFileLine(
        _ redactedMessage: String,
        level: LogLevel,
        category: String,
        location: String,
        renderedFields: String = ""
    ) -> String {
        let timestamp = SharedFormatters.logTimestampISO.string(from: Date())
        let level = pad(level.rawValue, to: levelWidth)
        let category = pad(category, to: categoryWidth)
        let location = pad(location, to: locationWidth)
        return "\(timestamp)  \(level)  \(category)  \(location)  \(redactedMessage)\(renderedFields)"
    }

    /// Convenience overload taking unrendered fields.
    nonisolated private static func formatFileLine(
        _ redactedMessage: String,
        level: LogLevel,
        category: String,
        location: String,
        fields: Fields
    ) -> String {
        formatFileLine(
            redactedMessage,
            level: level,
            category: category,
            location: location,
            renderedFields: renderFields(fields)
        )
    }

    /// Renders ordered fields as a ` key=value` tail, redacting each value.
    nonisolated private static func renderFields(_ fields: Fields) -> String {
        guard !fields.isEmpty else { return "" }
        return fields.map { key, value in
            " \(key)=\(quoteIfNeeded(redactFieldValue(value.description, forKey: key)))"
        }
        .joined()
    }

    /// Wraps a field value in double quotes when it would otherwise break the
    /// `key=value` grammar (empty, or containing whitespace, `=`, or `"`).
    nonisolated private static func quoteIfNeeded(_ value: String) -> String {
        let needsQuoting = value.isEmpty
            || value.contains(where: { $0.isWhitespace })
            || value.contains("=")
            || value.contains("\"")
        guard needsQuoting else { return value }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    /// Formats `#fileID` + `#line` as `Module/File.swift:42` (just `File.swift:42` if no module prefix).
    nonisolated private static func sourceLocation(file: StaticString, line: UInt) -> String {
        let full = "\(file)"
        let name = full.split(separator: "/").last.map(String.init) ?? full
        return "\(name):\(line)"
    }

    /// Flushes any buffered log data to disk immediately, blocking the caller.
    ///
    /// Use for shutdown and export paths. Hot logging paths should prefer
    /// ``scheduleFlush()``.
    nonisolated static func flush() {
        fileQueue.sync {
            try? fileHandle?.synchronize()
        }
    }

    /// Queues a flush behind the pending writes without blocking the caller.
    ///
    /// `fileQueue` is serial, so this still lands after the line that asked for
    /// it; ordering is preserved and no caller stalls on an `fsync`.
    ///
    /// ponytail: accepts a millisecond-wide window where a hard crash lands
    /// between the write and the sync and loses the last error line. The
    /// alternative was `fileQueue.sync` on all 165 `Log.error` sites, which
    /// serialized every caller behind a disk sync during exactly the error
    /// bursts (reconnect loops, bind failures) where throughput matters most.
    /// `CrashReporter`'s NSException handler calls the blocking ``flush()``,
    /// which covers the crash path that can still run Swift code.
    nonisolated private static func scheduleFlush() {
        fileQueue.async {
            try? fileHandle?.synchronize()
        }
    }

    // MARK: - PII Redaction

    /// Field keys whose value is always replaced wholesale.
    nonisolated private static let sensitiveFieldKeys: Set<String> = [
        "token", "accesstoken", "refreshtoken", "secret", "password", "passwd",
        "auth", "authorization", "apikey", "clientsecret", "credential",
        "userid", "user_id", "channelid", "channel_id", "broadcasterid",
        "broadcaster_id", "moderatorid", "moderator_id"
    ]

    /// Field keys whose value is a legitimate large number and must survive the
    /// bare-digit rule.
    ///
    /// The old blanket `\b\d{6,}\b` rule rewrote byte counts, millisecond
    /// durations, ports, and epoch values to `[USER_ID_REDACTED]`, which is
    /// silent evidence destruction in the one artifact a user hands over.
    /// Naming the safe keys is what makes narrowing that rule defensible.
    nonisolated private static let numericSafeFieldKeys: Set<String> = [
        "bytes", "size", "length", "ms", "duration", "elapsed", "seconds", "after",
        "port", "count", "total", "attempt", "retries", "code", "status", "line",
        "offset", "limit", "remaining", "index", "position", "epoch", "timestamp"
    ]

    /// Redacts sensitive information from a free-form message body.
    nonisolated private static func redactSensitiveInfo(_ message: String) -> String {
        applyBaseRedactions(message)
            .replacing(#/\b\d{9,}\b/#, with: "[USER_ID_REDACTED]")
    }

    /// Redaction rules that never destroy legitimate numeric evidence.
    ///
    /// Ordering matters: the keyed-ID rule runs before the opaque-token rule so
    /// `user_id=123456789` keeps its key rather than becoming one long
    /// `[TOKEN_REDACTED]` blob.
    nonisolated private static func applyBaseRedactions(_ message: String) -> String {
        var out = message
        out = out.replacing(#/oauth_[a-zA-Z0-9_-]+/#, with: "oauth_[REDACTED]")
        out = out.replacing(#/Bearer\s+[a-zA-Z0-9_-]+/#, with: "Bearer [REDACTED]")
        out = out.replacing(#/Client-ID[:\s]+[a-zA-Z0-9]+/#, with: "Client-ID: [REDACTED]")

        // Digits in an identifier-ish context, whatever their length. Keeps the
        // key and separator so the line still reads, replaces only the value.
        out = out.replacing(
            #/(?i)\b([a-z_]*(?:user|broadcaster|moderator|channel|chatter|owner)[a-z_]*|id)([\s:="']+)\d{4,}\b/#
        ) { match in
            "\(match.output.1)\(match.output.2)[USER_ID_REDACTED]"
        }

        out = out.replacing(#/\b[a-zA-Z0-9_-]{30,}\b/#, with: "[TOKEN_REDACTED]")
        return out
    }

    /// Redacts a structured field value, using the key to decide how hard.
    ///
    /// - A key in ``sensitiveFieldKeys`` is replaced wholesale.
    /// - A key in ``numericSafeFieldKeys`` skips the bare-digit rule, so
    ///   `bytes=1048576` survives intact.
    /// - Anything else gets the full message-body treatment.
    ///
    /// Keys themselves are never redacted; they carry no user data and are what
    /// makes the line searchable.
    nonisolated private static func redactFieldValue(_ value: String, forKey key: String) -> String {
        let normalized = key.lowercased()
        if sensitiveFieldKeys.contains(normalized) { return "[REDACTED]" }
        if numericSafeFieldKeys.contains(normalized) { return applyBaseRedactions(value) }
        return redactSensitiveInfo(value)
    }

    /// Runs the PII redaction pipeline on an arbitrary string.
    ///
    /// Exposed at internal visibility so non-log code paths (e.g. ``CrashReporter``'s
    /// NSException handler) can redact user-supplied strings before writing them to
    /// disk, without duplicating the redaction rules.
    nonisolated static func redact(_ message: String) -> String {
        redactSensitiveInfo(message)
    }

    #if DEBUG
    /// Test-only hook exposing the PII redaction pipeline.
    ///
    /// Redaction is verified through this pure function instead of by writing
    /// to and reading back the app-wide on-disk log file. `Log` is a
    /// process-global singleton, so other suites (e.g. WebSocket integration
    /// tests that deliberately trigger bind errors) write into that same file
    /// concurrently. A burst large enough to rotate it mid-test made the
    /// file-readback assertions flaky in CI. Testing the function directly is
    /// deterministic and touches no file.
    nonisolated static func redactForTesting(_ message: String) -> String {
        redactSensitiveInfo(message)
    }

    /// Test-only hook exposing structured-field redaction.
    nonisolated static func redactFieldForTesting(_ value: String, key: String) -> String {
        redactFieldValue(value, forKey: key)
    }

    /// Test-only hook exposing the on-disk log line builder.
    ///
    /// Verifies the exact format written to the log file (redaction + level +
    /// category + message + fields) without reading back the app-wide on-disk
    /// log. `Log` is a process-global singleton; other suites write into the
    /// same file and can rotate it mid-test, deleting the line we just wrote.
    /// Building the line directly is deterministic and touches no shared file.
    /// The real disk-write path stays covered by `testLogFileExport`.
    nonisolated static func formatFileLineForTesting(
        _ message: String,
        level: LogLevel = .info,
        category: String = "App",
        fields: Fields = [:]
    ) -> String {
        formatFileLine(
            redactSensitiveInfo(message),
            level: level,
            category: category,
            location: "Test.swift:0",
            fields: fields
        )
    }

    /// Test-only hook exposing the session banner builder.
    nonisolated static func sessionBannerLineForTesting() -> String {
        sessionBannerLine()
    }

    /// Test-only hook exposing the continuation-line framer.
    nonisolated static func frameContinuationsForTesting(_ line: String) -> String {
        frameContinuations(line)
    }

    /// Test-only hook exposing the debug-logging build gate.
    ///
    /// `Log.debug` is dropped unless this is true (DEBUG builds only). Asserting
    /// the gate here is deterministic; the old approach wrote a debug line and
    /// read it back from the app-wide on-disk log, which other parallel suites
    /// could rotate away mid-test (same `Log` singleton hazard as the hooks
    /// above), making it flaky in CI.
    nonisolated static var debugLoggingEnabledForTesting: Bool {
        isDebugLoggingEnabled
    }
    #endif

    // MARK: - Export

    /// Returns the URL of the current log file for export/sharing.
    ///
    /// - Returns: The log file URL, or nil if logs directory could not be created.
    nonisolated static func exportLogFile() -> URL? {
        fileQueue.sync {
            let url = logFileURL
            try? fileHandle?.synchronize()
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }

    /// Returns the rotated backups that exist, oldest first.
    ///
    /// Export paths need these: if rotation just fired, the lines worth reading
    /// are in a backup and the live log is nearly empty.
    nonisolated static func rotatedLogFiles() -> [URL] {
        fileQueue.sync {
            let directory = logFileURL.deletingLastPathComponent()
            return stride(from: rotationDepth, through: 1, by: -1)
                .map { directory.appending(path: "wolfwave.log.\($0)") }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    // MARK: - Diagnostics

    /// Returns the byte size of the current log file, or 0 if unavailable.
    nonisolated static func logFileSize() -> Int64 {
        fileQueue.sync {
            let url = logFileURL
            try? fileHandle?.synchronize()
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? NSNumber else { return 0 }
            return size.int64Value
        }
    }

    /// Returns the number of newline-terminated lines in the current log file.
    ///
    /// Streams the file in chunks rather than loading it, and memoizes the
    /// result against the file's size and modification date. Settings panes
    /// poll this, and rescanning 5 MB on every refresh was the reason two call
    /// sites had to hop off the main thread to stay responsive.
    nonisolated static func logLineCount() -> Int {
        fileQueue.sync {
            let url = logFileURL
            try? fileHandle?.synchronize()

            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            let modified = (attrs?[.modificationDate] as? Date) ?? .distantPast

            if let cache = lineCountCache, cache.size == size, cache.modified == modified {
                return cache.lines
            }

            guard let handle = try? FileHandle(forReadingFrom: url) else { return 0 }
            defer { try? handle.close() }

            var count = 0
            let newline: UInt8 = 0x0A
            while let chunk = try? handle.read(upToCount: 65_536), !chunk.isEmpty {
                count += chunk.reduce(into: 0) { acc, byte in
                    if byte == newline { acc += 1 }
                }
            }

            lineCountCache = (size: size, modified: modified, lines: count)
            return count
        }
    }

    /// Truncates the current log file in place and writes a single header line.
    ///
    /// The header goes through the same builder as every other record, so the
    /// file never contains a second, incompatible line shape for a parser to
    /// choke on. The banner is re-armed so the next write re-identifies the
    /// build.
    nonisolated static func clearLogFile() {
        fileQueue.sync {
            let url = logFileURL

            // Drop the handle instead of seeking and truncating through it. A
            // retained handle keeps its old write offset, and if anything
            // restores that offset the next write lands past the end of the
            // freshly truncated file, re-extending it with a NUL gap the exact
            // size of the old log. Clearing a 300 KB log produced a 300 KB file
            // of zero bytes that still "passed" a line-count assertion, because
            // NULs contain no newlines.
            //
            // An atomic whole-file replace has no offset to get stale, and the
            // next write reopens and seeks to the real end.
            try? fileHandle?.close()
            fileHandle = nil
            openedInode = nil

            let header = formatFileLine(
                "Log cleared by user",
                level: .info,
                category: LogCategory.app.rawValue,
                location: "Logger.swift:0"
            )
            try? Data((header + "\n").utf8).write(to: url, options: .atomic)

            bannerPending = true
            lineCountCache = nil
        }
    }

    // MARK: - Cleanup

    /// Closes the log file handle. Called automatically at app termination.
    nonisolated static func shutdown() {
        fileQueue.sync {
            try? fileHandle?.synchronize()
            try? fileHandle?.close()
            fileHandle = nil
            openedInode = nil
        }
    }
}

// swiftlint:enable type_body_length
