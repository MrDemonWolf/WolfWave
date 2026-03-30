//
//  LoggerTests.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import Testing
import Foundation
@testable import WolfWave

/// Comprehensive test suite for logging functionality
@Suite("Logger Tests")
struct LoggerTests {
    
    // MARK: - Log Level Tests
    
    @Test("Log levels have correct raw values")
    func testLogLevelRawValues() async throws {
        #expect(LogLevel.debug.rawValue == "🐛 DEBUG")
        #expect(LogLevel.info.rawValue == "ℹ️ INFO")
        #expect(LogLevel.warn.rawValue == "⚠️ WARN")
        #expect(LogLevel.error.rawValue == "🛑 ERROR")
    }
    
    // MARK: - PII Redaction Tests
    
    @Test("Redacts OAuth tokens from log messages")
    func testOAuthTokenRedaction() async throws {
        let uniqueID = UUID().uuidString
        let message = "User token: oauth_abc123def456ghi789_\(uniqueID)"
        Log.info(message, category: "Test")

        guard let logURL = Log.exportLogFile() else {
            Issue.record("Failed to export log file")
            return
        }
        let logData = try Data(contentsOf: logURL)
        let content = String(decoding: logData, as: UTF8.self)

        // The raw OAuth token should not appear in the log output
        #expect(!content.contains("oauth_abc123def456ghi789_\(uniqueID)"),
            "OAuth token should be redacted from log output")
    }

    @Test("Redacts Bearer tokens from log messages")
    func testBearerTokenRedaction() async throws {
        let uniqueID = UUID().uuidString
        let message = "Authorization: Bearer abc123def456ghi789jkl012_\(uniqueID)"
        Log.info(message, category: "Test")

        guard let logURL = Log.exportLogFile() else {
            Issue.record("Failed to export log file")
            return
        }
        let logData = try Data(contentsOf: logURL)
        let content = String(decoding: logData, as: UTF8.self)

        #expect(!content.contains("Bearer abc123def456ghi789jkl012_\(uniqueID)"),
            "Bearer token should be redacted from log output")
    }

    @Test("Redacts long alphanumeric tokens")
    func testLongTokenRedaction() async throws {
        let uniqueID = UUID().uuidString
        let longToken = "abcdefghijklmnopqrstuvwxyz1234567890abcdefghijklmnopqrstuvwxyz\(uniqueID)"
        let message = "Token value: \(longToken)"
        Log.info(message, category: "Test")

        guard let logURL = Log.exportLogFile() else {
            Issue.record("Failed to export log file")
            return
        }
        let logData = try Data(contentsOf: logURL)
        let content = String(decoding: logData, as: UTF8.self)

        #expect(!content.contains(longToken),
            "Long alphanumeric token should be redacted from log output")
    }

    @Test("Redacts Client-ID values")
    func testClientIDRedaction() async throws {
        let uniqueID = UUID().uuidString
        let message = "Client-ID: abc123def456_\(uniqueID)"
        Log.info(message, category: "Test")

        guard let logURL = Log.exportLogFile() else {
            Issue.record("Failed to export log file")
            return
        }
        let logData = try Data(contentsOf: logURL)
        let content = String(decoding: logData, as: UTF8.self)

        #expect(!content.contains("Client-ID: abc123def456_\(uniqueID)"),
            "Client-ID value should be redacted from log output")
    }

    @Test("Does not redact normal text")
    func testNormalTextNotRedacted() async throws {
        let uniqueID = UUID().uuidString
        let message = "Normal log message with no sensitive data \(uniqueID)"
        Log.info(message, category: "Test")

        guard let logURL = Log.exportLogFile() else {
            Issue.record("Failed to export log file")
            return
        }
        let logData = try Data(contentsOf: logURL)
        let content = String(decoding: logData, as: UTF8.self)

        #expect(content.contains(message),
            "Normal text should not be redacted from log output")
    }
    
    // MARK: - Log File Tests
    
    @Test("Log file can be exported")
    func testLogFileExport() async throws {
        // Write some test logs
        Log.info("Test log entry 1", category: "Test")
        Log.info("Test log entry 2", category: "Test")
        
        // Export log file
        let logURL = Log.exportLogFile()
        
        // Verify URL is not nil
        #expect(logURL != nil)
        
        // Verify file exists
        if let url = logURL {
            let fileExists = FileManager.default.fileExists(atPath: url.path)
            #expect(fileExists)
        }
    }
    
    @Test("Log file contains expected content")
    func testLogFileContent() async throws {
        let testMessage = "Test log message \(UUID().uuidString)"
        
        Log.info(testMessage, category: "TestCategory")
        
        // Export and read log file
        guard let logURL = Log.exportLogFile() else {
            Issue.record("Failed to export log file")
            return
        }
        
        let logData = try Data(contentsOf: logURL)
        let logContent = String(decoding: logData, as: UTF8.self)

        // Verify test message is in log file
        #expect(logContent.contains(testMessage))
        #expect(logContent.contains("INFO"))
        #expect(logContent.contains("TestCategory"))
    }
    
    // MARK: - Debug Logging Tests
    
    @Test("Debug logs are only written in debug builds")
    func testDebugLogging() async throws {
        let debugMessage = "Debug message \(UUID().uuidString)"
        
        Log.debug(debugMessage, category: "Test")
        
        // In release builds, this should not be written
        // In debug builds, it should be written
        #if DEBUG
        if let logURL = Log.exportLogFile() {
            let logData = try Data(contentsOf: logURL)
            let content = String(decoding: logData, as: UTF8.self)
            #expect(content.contains(debugMessage))
        }
        #else
        if let logURL = Log.exportLogFile() {
            let logData = try Data(contentsOf: logURL)
            let content = String(decoding: logData, as: UTF8.self)
            #expect(!content.contains(debugMessage))
        }
        #endif
    }
    
    // MARK: - Concurrent Logging Tests
    
    @Test("Concurrent logging is thread-safe")
    func testConcurrentLogging() async throws {
        let iterations = 100
        let uniquePrefix = UUID().uuidString

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    Log.info("Concurrent log \(uniquePrefix)_\(i)", category: "Concurrency")
                }
            }
        }

        // Verify at least some of the concurrent messages were written
        guard let logURL = Log.exportLogFile() else {
            Issue.record("Failed to export log file")
            return
        }
        let logData = try Data(contentsOf: logURL)
        let content = String(decoding: logData, as: UTF8.self)

        // Check that a sample of messages appear in the log
        #expect(content.contains("Concurrent log \(uniquePrefix)_0"),
            "First concurrent log message should be present")
        #expect(content.contains("Concurrent log \(uniquePrefix)_\(iterations - 1)"),
            "Last concurrent log message should be present")
    }
    
    // MARK: - Category Tests
    
    @Test("Different categories are logged correctly")
    func testCategories() async throws {
        Log.info("App message", category: "App")
        Log.info("Network message", category: "Network")
        Log.info("Twitch message", category: "Twitch")
        Log.info("OAuth message", category: "OAuth")
        
        guard let logURL = Log.exportLogFile() else {
            Issue.record("Failed to export log file")
            return
        }
        
        let logData = try Data(contentsOf: logURL)
        let content = String(decoding: logData, as: UTF8.self)

        #expect(content.contains("[App]"))
        #expect(content.contains("[Network]"))
        #expect(content.contains("[Twitch]"))
        #expect(content.contains("[OAuth]"))
    }
    
    // MARK: - Performance Tests
    
    @Test("Logging performance is acceptable")
    func testLoggingPerformance() async throws {
        let start = Date()
        
        for i in 0..<1000 {
            Log.info("Performance test message \(i)", category: "Performance")
        }
        
        let duration = Date().timeIntervalSince(start)
        
        // 1000 log messages should complete in less than 2 seconds (generous for CI)
        #expect(duration < 2.0)
    }
}
