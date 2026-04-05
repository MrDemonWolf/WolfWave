//
//  Logger.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import Foundation
import os

enum LogLevel: String {
    case debug = "🐛 DEBUG"
    case info  = "ℹ️ INFO"
    case warn  = "⚠️ WARN"
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

    nonisolated private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    /// Whether debug logging is enabled (only in DEBUG builds)
    nonisolated private static var isDebugLoggingEnabled: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    // MARK: - OSLog

    /// Subsystem identifier used for all OSLog entries.
    private static let subsystem = "com.mrdemonwolf.wolfwave"

    /// Returns a cached `os.Logger` for the given category.
    ///
    /// Logs appear in Console.app and Instruments — filter by subsystem
    /// `com.mrdemonwolf.wolfwave` and use the Category column to isolate
    /// specific areas (e.g. "Twitch", "Discord", "Music").
    nonisolated(unsafe) private static var osLoggers: [String: os.Logger] = [:]
    nonisolated private static let osLoggerLock = NSLock()

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

        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else {
            let fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent("wolfwave.log")
            _logFileURL = fallback
            return fallback
        }
        let logsDir = appSupport.appendingPathComponent("WolfWave/Logs", isDirectory: true)

        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let url = logsDir.appendingPathComponent("wolfwave.log")
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
            .appendingPathComponent("wolfwave.log.1")
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

    nonisolated static func log(_ message: String, level: LogLevel = .info, category: String = "App") {
        let redactedMessage = redactSensitiveInfo(message)
        let timestamp = formatter.string(from: Date())
        let line = "\(level.rawValue)  [\(category)] \(timestamp)  \(redactedMessage)"
        print(line)
        writeToFile(line)

        // Route to OSLog so logs appear in Console.app and Instruments.
        // Messages are marked .public since PII has already been redacted above.
        let logger = osLogger(for: category)
        switch level {
        case .debug: logger.debug("\(redactedMessage, privacy: .public)")
        case .info:  logger.info("\(redactedMessage, privacy: .public)")
        case .warn:  logger.warning("\(redactedMessage, privacy: .public)")
        case .error: logger.error("\(redactedMessage, privacy: .public)")
        }
    }

    nonisolated static func debug(_ message: @autoclosure () -> String, category: String = "App") {
        guard isDebugLoggingEnabled else { return }
        log(message(), level: .debug, category: category)
    }

    nonisolated static func info(_ message: String, category: String = "App") {
        log(message, level: .info, category: category)
    }

    nonisolated static func warn(_ message: String, category: String = "App") {
        log(message, level: .warn, category: category)
    }

    nonisolated static func error(_ message: String, category: String = "App") {
        log(message, level: .error, category: category)
        // Flush immediately for errors to ensure they're written if app crashes
        flush()
    }

    /// Flushes any buffered log data to disk immediately.
    nonisolated static func flush() {
        fileQueue.sync {
            fileHandle?.synchronizeFile()
        }
    }

    // MARK: - PII Redaction

    /// Redacts sensitive information from log messages
    nonisolated private static func redactSensitiveInfo(_ message: String) -> String {
        var redacted = message

        // Redact OAuth tokens (oauth_XXXX or Bearer XXXX patterns)
        if let result = try? NSRegularExpression(pattern: #"oauth_[a-zA-Z0-9_-]+"#)
            .stringByReplacingMatches(in: redacted, range: NSRange(redacted.startIndex..., in: redacted), withTemplate: "oauth_[REDACTED]") {
            redacted = result
        }

        if let result = try? NSRegularExpression(pattern: #"Bearer\s+[a-zA-Z0-9_-]+"#)
            .stringByReplacingMatches(in: redacted, range: NSRange(redacted.startIndex..., in: redacted), withTemplate: "Bearer [REDACTED]") {
            redacted = result
        }

        // Redact what looks like access tokens (long alphanumeric strings)
        if let result = try? NSRegularExpression(pattern: #"\b[a-zA-Z0-9]{30,}\b"#)
            .stringByReplacingMatches(in: redacted, range: NSRange(redacted.startIndex..., in: redacted), withTemplate: "[TOKEN_REDACTED]") {
            redacted = result
        }

        // Redact Client-ID values
        if let result = try? NSRegularExpression(pattern: #"Client-ID[:\s]+[a-zA-Z0-9]+"#)
            .stringByReplacingMatches(in: redacted, range: NSRange(redacted.startIndex..., in: redacted), withTemplate: "Client-ID: [REDACTED]") {
            redacted = result
        }

        // Redact numeric user IDs (Twitch user IDs are 8+ digit numbers)
        if let result = try? NSRegularExpression(pattern: #"\b\d{8,}\b"#)
            .stringByReplacingMatches(in: redacted, range: NSRange(redacted.startIndex..., in: redacted), withTemplate: "[USER_ID_REDACTED]") {
            redacted = result
        }

        return redacted
    }

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
