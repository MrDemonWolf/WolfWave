//
//  Logger.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/13/26.
//

import Foundation

// MARK: - Log Level

/// Represents the severity level of a log message.
enum LogLevel: String {
    /// Debug-level logs for development and troubleshooting
    case debug = "🐛 DEBUG"
    
    /// Informational logs for general application flow
    case info  = "ℹ️ INFO"
    
    /// Warning logs for potentially problematic situations
    case warn  = "⚠️ WARN"
    
    /// Error logs for failures and exceptions
    case error = "🛑 ERROR"
}

// MARK: - Logger

/// A centralized logging utility for consistent, structured logging throughout the application.
///
/// The logger provides emoji-prefixed, timestamped log messages with category support
/// for easy filtering and debugging. In production, consider replacing this
/// implementation with `os_log`/`OSLog` or another structured logging backend.
///
/// **Usage:**
/// ```swift
/// Log.info("Application started", category: "App")
/// Log.debug("Processing track: \(trackName)", category: "MusicMonitor")
/// Log.error("Failed to connect: \(error)", category: "Network")
/// ```
///
/// **Output Format:**
/// ```
/// [ℹ️ INFO] [App] [2026-01-12T15:30:45.123Z] Application started
/// ```
enum Log {
    
    // MARK: - Properties
    
    /// ISO8601 date formatter with fractional seconds for precise timestamps
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    // MARK: - Public Methods
    
    /// Logs a message with the specified level and category.
    ///
    /// - Parameters:
    ///   - message: The message to log.
    ///   - level: The severity level (default: `.info`).
    ///   - category: The category or subsystem (default: `"App"`).
    static func log(_ message: String, level: LogLevel = .info, category: String = "App") {
        let timestamp = formatter.string(from: Date())
        print("[\(level.rawValue)] [\(category)] [\(timestamp)] \(message)")
    }
    
    /// Logs a debug-level message.
    ///
    /// Use for detailed information useful during development and troubleshooting.
    ///
    /// - Parameters:
    ///   - message: The message to log.
    ///   - category: The category or subsystem (default: `"App"`).
    static func debug(_ message: String, category: String = "App") {
        log(message, level: .debug, category: category)
    }
    
    /// Logs an info-level message.
    ///
    /// Use for general informational messages about application flow.
    ///
    /// - Parameters:
    ///   - message: The message to log.
    ///   - category: The category or subsystem (default: `"App"`).
    static func info(_ message: String, category: String = "App") {
        log(message, level: .info, category: category)
    }
    
    /// Logs a warning-level message.
    ///
    /// Use for potentially problematic situations that don't prevent execution.
    ///
    /// - Parameters:
    ///   - message: The message to log.
    ///   - category: The category or subsystem (default: `"App"`).
    static func warn(_ message: String, category: String = "App") {
        log(message, level: .warn, category: category)
    }
    
    /// Logs an error-level message.
    ///
    /// Use for failures, exceptions, and critical issues.
    ///
    /// - Parameters:
    ///   - message: The message to log.
    ///   - category: The category or subsystem (default: `"App"`).
    static func error(_ message: String, category: String = "App") {
        log(message, level: .error, category: category)
    }
}
