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
    
    nonisolated static func log(_ message: String, level: LogLevel = .info, category: String = "App") {
        let timestamp = formatter.string(from: Date())
        print("[\(level.rawValue)] [\(category)] [\(timestamp)] \(message)")
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
}
