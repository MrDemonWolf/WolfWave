//
//  Logger.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/8/26.
//

import Foundation

enum LogLevel: String {
    case debug = "🐛 DEBUG"
    case info  = "ℹ️ INFO"
    case warn  = "⚠️ WARN"
    case error = "🛑 ERROR"
}

enum Log {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func log(_ message: String, level: LogLevel = .info, category: String = "App") {
        let timestamp = formatter.string(from: Date())
        print("[\(level.rawValue)] [\(category)] [\(timestamp)] \(message)")
    }

    static func debug(_ message: String, category: String = "App") {
        log(message, level: .debug, category: category)
    }

    static func info(_ message: String, category: String = "App") {
        log(message, level: .info, category: category)
    }

    static func warn(_ message: String, category: String = "App") {
        log(message, level: .warn, category: category)
    }

    static func error(_ message: String, category: String = "App") {
        log(message, level: .error, category: category)
    }
}
