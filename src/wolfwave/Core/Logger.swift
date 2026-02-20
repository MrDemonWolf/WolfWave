//
//  Logger.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import Foundation

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
/// Usage:
/// ```swift
/// Log.info("Message", category: "Category")
/// Log.error("Error message", category: "Network")
/// Log.debug("Debug info", category: "Dev")  // Only in development
/// ```
enum Log {

    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
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

    // MARK: - File Logging

    /// Maximum log file size before rotation (5 MB).
    nonisolated private static let maxLogFileSize: UInt64 = 5 * 1024 * 1024

    /// Lock protecting file write operations.
    nonisolated private static let fileLock = NSLock()

    /// File handle for the current log file.
    nonisolated(unsafe) private static var fileHandle: FileHandle?

    /// URL of the current log file.
    nonisolated(unsafe) private static var _logFileURL: URL?

    /// Returns the log file URL, creating the directory and file if needed.
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
        fileLock.lock()
        defer { fileLock.unlock() }

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

    /// Rotates the log file by renaming the current file and starting fresh.
    nonisolated private static func rotateLogFile(at url: URL) {
        fileHandle?.closeFile()
        fileHandle = nil

        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("wolfwave.log.1")
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.moveItem(at: url, to: backupURL)
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }

    // MARK: - Public API

    nonisolated static func log(_ message: String, level: LogLevel = .info, category: String = "App") {
        let timestamp = formatter.string(from: Date())
        let line = "[\(level.rawValue)] [\(category)] [\(timestamp)] \(message)"
        print(line)
        writeToFile(line)
    }

    nonisolated static func debug(_ message: String, category: String = "App") {
        guard isDebugLoggingEnabled else { return }
        log(message, level: .debug, category: category)
    }

    nonisolated static func info(_ message: String, category: String = "App") {
        log(message, level: .info, category: category)
    }

    nonisolated static func warn(_ message: String, category: String = "App") {
        log(message, level: .warn, category: category)
    }

    nonisolated static func error(_ message: String, category: String = "App") {
        log(message, level: .error, category: category)
    }

    // MARK: - Export

    /// Returns the URL of the current log file for export/sharing.
    ///
    /// - Returns: The log file URL, or nil if logs directory could not be created.
    nonisolated static func exportLogFile() -> URL? {
        let url = logFileURL
        // Flush any pending writes
        fileLock.lock()
        fileHandle?.synchronizeFile()
        fileLock.unlock()
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
