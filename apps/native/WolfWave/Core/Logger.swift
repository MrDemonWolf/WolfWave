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
enum LogCategory: String {
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

/// Severity classification used by every log line. The raw value is the
/// emoji-prefixed string that appears in both the on-disk log file and the
/// macOS unified logging system.
///
/// Severity ordering (lowest → highest): `.debug`, `.info`, `.warn`, `.error`.
enum LogLevel: String {
    /// Verbose developer-only information. Suppressed in release builds.
    case debug = "🐛 DEBUG"

    /// Informational events that are useful at all times (lifecycle, state
    /// transitions, connection success).
    case info  = "ℹ️ INFO"

    /// Recoverable problems or unexpected conditions that did not interrupt
    /// the user-visible flow.
    case warn  = "⚠️ WARN"

    /// Failures that produced an error result or aborted an operation.
    case error = "🛑 ERROR"
}

/// Structured logging utility with emoji prefixes and categories.
///
/// Debug logs are only emitted in development builds (#DEBUG flag).
/// Production builds only emit info, warning, and error logs.
///
/// Logs are written to both the console and a rotating log file in the
/// app's Application Support directory. Use `exportLogFile()` to get
/// the log file URL for sharing.
///
/// Thread Safety:
/// All mutable file state (`fileHandle`, `_logFileURL`) is accessed
/// exclusively on `fileQueue`, a serial dispatch queue.
///
/// Usage:
/// ```swift
/// Log.info("Message", category: "Category")
/// Log.error("Error message", category: "Network")
/// Log.debug("Debug info", category: "Dev")  // Only in development
/// ```
enum Log {

    /// Shared timestamp formatter used by every log line. Locale-stable
    /// HH:mm:ss.SSS so file output collates correctly in any timezone.
    nonisolated private static var formatter: DateFormatter { SharedFormatters.logTimestamp }

    /// Whether debug logging is enabled (only in DEBUG builds)
    nonisolated private static var isDebugLoggingEnabled: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    // MARK: - OSLog Level Gate

    /// Numeric severity rank for `LogLevel`. Higher = more severe.
    nonisolated private static func rank(_ level: LogLevel) -> Int {
        switch level {
        case .debug: return 0
        case .info:  return 1
        case .warn:  return 2
        case .error: return 3
        }
    }

    /// Minimum severity that reaches `os.Logger`. File writes are unaffected.
    ///
    /// Defaults:
    /// - Under XCTest (CI / `xcodebuild test`): `.error`. Keeps unit-test runs
    ///   from flooding the captured xcodebuild output with thousands of info
    ///   lines per suite while still surfacing real failures.
    /// - Otherwise: `.debug`. Full chatter, same as historical behavior.
    ///
    /// Override with the `WOLFWAVE_LOG_LEVEL` env var (`silent` / `error` /
    /// `warn` / `info` / `debug`). `silent` suppresses every OSLog dispatch
    /// including errors.
    nonisolated private static let minOSLogRank: Int = {
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

    /// Returns a cached `os.Logger` for the given category.
    ///
    /// Logs appear in Console.app and Instruments. Filter by subsystem
    /// `com.mrdemonwolf.wolfwave` and use the Category column to isolate
    /// specific areas (e.g. "Twitch", "Discord", "Music").
    /// Cache of per-category `os.Logger` instances keyed by category name.
    /// Read/written under `osLoggerLock`.
    nonisolated(unsafe) private static var osLoggers: [String: os.Logger] = [:]

    /// Guards `osLoggers` against concurrent access from the logging callers.
    nonisolated private static let osLoggerLock = NSLock()

    /// Returns a cached `os.Logger` for `category`, creating one on first use.
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

    /// Serial queue protecting all file I/O state.
    nonisolated private static let fileQueue = DispatchQueue(label: "com.mrdemonwolf.wolfwave.logger", qos: .utility)

    /// File handle for the current log file. Only access on `fileQueue`.
    nonisolated(unsafe) private static var fileHandle: FileHandle?

    /// URL of the current log file. Only access on `fileQueue`.
    nonisolated(unsafe) private static var _logFileURL: URL?

    /// Returns the log file URL, creating the directory and file if needed.
    /// Must be called on `fileQueue`.
    nonisolated private static var logFileURL: URL {
        if let url = _logFileURL { return url }

        let logsDir = AppContainer.directory("Logs")

        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let url = logsDir.appending(path: "wolfwave.log")
        _logFileURL = url

        // Create the file if it doesn't exist
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        return url
    }

    /// Writes a formatted log line to the log file.
    nonisolated private static func writeToFile(_ line: String) {
        fileQueue.async {
            let url = logFileURL

            // Rotate if file exceeds max size
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? UInt64,
               size > maxLogFileSize
            {
                rotateLogFile(at: url)
            }

            // Open file handle if needed
            if fileHandle == nil {
                fileHandle = FileHandle(forWritingAtPath: url.path)
                fileHandle?.seekToEndOfFile()
            }

            if let data = (line + "\n").data(using: .utf8) {
                fileHandle?.write(data)
            }
        }
    }

    /// Rotates the log file by renaming the current file and starting fresh.
    nonisolated private static func rotateLogFile(at url: URL) {
        fileHandle?.closeFile()
        fileHandle = nil

        let backupURL = url.deletingLastPathComponent()
            .appending(path: "wolfwave.log.1")
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.moveItem(at: url, to: backupURL)
        FileManager.default.createFile(atPath: url.path, contents: nil)

        // Clean up old log files (keep only the most recent backup)
        cleanupOldLogs(in: url.deletingLastPathComponent())
    }

    /// Removes old log files beyond the most recent backup
    nonisolated private static func cleanupOldLogs(in directory: URL) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        // Find all .log files except the current one
        let logFiles = files.filter { url in
            let name = url.lastPathComponent
            return name.hasPrefix("wolfwave.log") && name != "wolfwave.log" && name != "wolfwave.log.1"
        }

        // Delete old log files
        for file in logFiles {
            try? fileManager.removeItem(at: file)
        }
    }

    // MARK: - Public API

    /// Writes a log line at the given level. Prefer the convenience entry
    /// points (`debug`, `info`, `warn`, `error`) over calling `log` directly.
    ///
    /// The message is run through `redactSensitiveInfo` before either sink
    /// receives it; OSLog entries are marked `.public` because PII redaction
    /// has already happened.
    ///
    /// - Parameters:
    ///   - message: Free-form message body.
    ///   - level: Severity classification. Defaults to `.info`.
    ///   - category: Logical area tag for filtering in Console.app.
    ///   - file: Auto-captured `#fileID`.
    ///   - line: Auto-captured `#line`.
    nonisolated static func log(
        _ message: String,
        level: LogLevel = .info,
        category: String = "App",
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        // Suppress .debug writes in release builds regardless of call-site entry
        // path. Log.debug() has its own @autoclosure guard, but a direct call to
        // Log.log(..., level: .debug) would otherwise bypass that suppression and
        // write to disk in a release build.
        if level == .debug && !isDebugLoggingEnabled { return }

        let redactedMessage = redactSensitiveInfo(message)
        let location = sourceLocation(file: file, line: line)

        // File log keeps emoji + timestamp + location for human grep-ing.
        let fileLine = formatFileLine(redactedMessage, level: level, category: category, location: location)
        writeToFile(fileLine)

        // OSLog → Xcode console + Console.app + Instruments.
        // Source location appended so it's clickable in Xcode 16+.
        // Messages are marked .public since PII has already been redacted above.
        // Gate by minOSLogRank so XCTest runs / CI don't flood captured stdout.
        guard rank(level) >= minOSLogRank else { return }
        let logger = osLogger(for: category)
        let osMessage = "\(redactedMessage)  (\(location))"
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
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        guard isDebugLoggingEnabled else { return }
        log(message(), level: .debug, category: category, file: file, line: line)
    }

    /// Convenience entry point for `.info` logs.
    nonisolated static func info(
        _ message: String,
        category: String = "App",
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        log(message, level: .info, category: category, file: file, line: line)
    }

    /// Convenience entry point for `.warn` logs.
    nonisolated static func warn(
        _ message: String,
        category: String = "App",
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        log(message, level: .warn, category: category, file: file, line: line)
    }

    /// Convenience entry point for `.error` logs. Flushes the file handle
    /// immediately so the entry survives a crash that follows the call site.
    nonisolated static func error(
        _ message: String,
        category: String = "App",
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        log(message, level: .error, category: category, file: file, line: line)
        // Flush immediately for errors to ensure they're written if app crashes
        flush()
    }

    // MARK: - Typed-category overloads
    //
    // Forward to the string-keyed implementations. Prefer these at new call
    // sites so the category name is enum-checked rather than free-form string.

    nonisolated static func log(
        _ message: String,
        level: LogLevel = .info,
        category: LogCategory,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        log(message, level: level, category: category.rawValue, file: file, line: line)
    }

    nonisolated static func debug(
        _ message: @autoclosure () -> String,
        category: LogCategory,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        guard isDebugLoggingEnabled else { return }
        log(message(), level: .debug, category: category.rawValue, file: file, line: line)
    }

    nonisolated static func info(
        _ message: String,
        category: LogCategory,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        log(message, level: .info, category: category.rawValue, file: file, line: line)
    }

    nonisolated static func warn(
        _ message: String,
        category: LogCategory,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        log(message, level: .warn, category: category.rawValue, file: file, line: line)
    }

    nonisolated static func error(
        _ message: String,
        category: LogCategory,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        log(message, level: .error, category: category.rawValue, file: file, line: line)
        flush()
    }

    /// Builds the exact line written to the on-disk log file:
    /// `<level emoji> <LEVEL>  [<category>] <timestamp>  <location>  <message>`.
    /// Message is assumed already redacted by the caller.
    nonisolated private static func formatFileLine(
        _ redactedMessage: String,
        level: LogLevel,
        category: String,
        location: String
    ) -> String {
        let timestamp = formatter.string(from: Date())
        return "\(level.rawValue)  [\(category)] \(timestamp)  \(location)  \(redactedMessage)"
    }

    /// Formats `#fileID` + `#line` as `Module/File.swift:42` (just `File.swift:42` if no module prefix).
    nonisolated private static func sourceLocation(file: StaticString, line: UInt) -> String {
        let full = "\(file)"
        let name = full.split(separator: "/").last.map(String.init) ?? full
        return "\(name):\(line)"
    }

    /// Flushes any buffered log data to disk immediately.
    nonisolated static func flush() {
        fileQueue.sync {
            fileHandle?.synchronizeFile()
        }
    }

    // MARK: - PII Redaction

    // Compile-checked regex literals, no runtime parsing or `try!`.
    nonisolated(unsafe) private static let redactionRules: [(Regex<Substring>, String)] = [
        (#/oauth_[a-zA-Z0-9_-]+/#, "oauth_[REDACTED]"),
        (#/Bearer\s+[a-zA-Z0-9_-]+/#, "Bearer [REDACTED]"),
        (#/\b[a-zA-Z0-9_-]{30,}\b/#, "[TOKEN_REDACTED]"),
        (#/Client-ID[:\s]+[a-zA-Z0-9]+/#, "Client-ID: [REDACTED]"),
        (#/\b\d{6,}\b/#, "[USER_ID_REDACTED]"),
    ]

    /// Redacts sensitive information from log messages
    nonisolated private static func redactSensitiveInfo(_ message: String) -> String {
        redactionRules.reduce(message) { current, rule in
            current.replacing(rule.0, with: rule.1)
        }
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

    /// Test-only hook exposing the on-disk log line builder.
    ///
    /// Verifies the exact format written to the log file (redaction + level +
    /// category + message) without reading back the app-wide on-disk log. `Log`
    /// is a process-global singleton; other suites write into the same file and
    /// can rotate it mid-test, deleting the line we just wrote (rotation keeps
    /// only the single `.1` backup, so a burst large enough to rotate twice
    /// evicts our message entirely). Building the line directly is deterministic
    /// and touches no shared file. The real disk-write path stays covered by
    /// `testLogFileExport`.
    nonisolated static func formatFileLineForTesting(
        _ message: String,
        level: LogLevel = .info,
        category: String = "App"
    ) -> String {
        formatFileLine(
            redactSensitiveInfo(message),
            level: level,
            category: category,
            location: "Test.swift:0"
        )
    }
    #endif

    // MARK: - Export

    /// Returns the URL of the current log file for export/sharing.
    ///
    /// - Returns: The log file URL, or nil if logs directory could not be created.
    nonisolated static func exportLogFile() -> URL? {
        fileQueue.sync {
            let url = logFileURL
            fileHandle?.synchronizeFile()
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }

    // MARK: - Diagnostics

    /// Returns the byte size of the current log file, or 0 if unavailable.
    nonisolated static func logFileSize() -> Int64 {
        fileQueue.sync {
            let url = logFileURL
            fileHandle?.synchronizeFile()
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? NSNumber else { return 0 }
            return size.int64Value
        }
    }

    /// Returns the number of newline-terminated lines in the current log file.
    /// Streams the file in chunks to avoid loading the whole file into memory.
    nonisolated static func logLineCount() -> Int {
        fileQueue.sync {
            let url = logFileURL
            fileHandle?.synchronizeFile()
            guard let handle = try? FileHandle(forReadingFrom: url) else { return 0 }
            defer { try? handle.close() }

            var count = 0
            let newline: UInt8 = 0x0A
            while let chunk = try? handle.read(upToCount: 65_536), !chunk.isEmpty {
                count += chunk.reduce(into: 0) { acc, byte in
                    if byte == newline { acc += 1 }
                }
            }
            return count
        }
    }

    /// Truncates the current log file in place and writes a single header line.
    nonisolated static func clearLogFile() {
        fileQueue.sync {
            let url = logFileURL

            if fileHandle == nil {
                fileHandle = FileHandle(forWritingAtPath: url.path)
            }

            try? fileHandle?.seek(toOffset: 0)
            try? fileHandle?.truncate(atOffset: 0)

            let stamp = formatter.string(from: Date())
            let header = "[\(stamp)] ℹ️ INFO [App] Log cleared by user\n"
            if let data = header.data(using: .utf8) {
                fileHandle?.write(data)
            }
            fileHandle?.synchronizeFile()
        }
    }

    // MARK: - Cleanup

    /// Closes the log file handle. Called automatically at app termination.
    nonisolated static func shutdown() {
        fileQueue.sync {
            fileHandle?.synchronizeFile()
            fileHandle?.closeFile()
            fileHandle = nil
        }
    }
}
