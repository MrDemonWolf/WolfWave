//
//  LoggerTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-03-18.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Testing
import Foundation
@testable import WolfWave

/// Comprehensive test suite for logging functionality
@MainActor
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
    //
    // Redaction is verified against the pure `Log.redactForTesting` pipeline
    // rather than by writing a line and reading it back from the on-disk log.
    // `Log` is a process-global singleton, so other suites write into the same
    // app-wide file concurrently (e.g. WebSocketServerIntegrationTests
    // deliberately double-binds a port to assert `.error`, emitting
    // "🛑 ERROR [WebSocket] ... Address already in use"). A large enough burst
    // can rotate that file mid-test and evict the line we just wrote, which
    // made these readback assertions flaky in CI. Testing the redaction
    // function directly is deterministic and needs no file at all.

    // Token fixtures below are synthetic placeholders, not real credentials.
    // The redaction rules key on the `oauth_` / `Bearer ` prefixes (see
    // Logger.swift), so low-entropy readable values exercise them fully while
    // keeping secret scanners (GitGuardian) quiet — avoid random/UUID suffixes.

    @Test("Redacts OAuth tokens from log messages")
    func testOAuthTokenRedaction() {
        let token = "oauth_example_placeholder_not_a_real_token"
        let redacted = Log.redactForTesting("User token: \(token)")

        #expect(!redacted.contains(token), "OAuth token should be redacted")
    }

    @Test("Redacts Bearer tokens from log messages")
    func testBearerTokenRedaction() {
        let token = "Bearer example_placeholder_not_a_real_token"
        let redacted = Log.redactForTesting("Authorization: \(token)")

        #expect(!redacted.contains(token), "Bearer token should be redacted")
    }

    @Test("Redacts long alphanumeric tokens")
    func testLongTokenRedaction() {
        // 60-char alphanumeric run (> the 30-char redaction threshold).
        let longToken = "abcdefghijklmnopqrstuvwxyz1234567890abcdefghijklmnopqrstuvwxyz"
        let redacted = Log.redactForTesting("Token value: \(longToken)")

        #expect(!redacted.contains(longToken),
            "Long alphanumeric token should be redacted")
    }

    @Test("Redacts Client-ID values")
    func testClientIDRedaction() {
        let value = "Client-ID: abc123def456789"
        let redacted = Log.redactForTesting(value)

        #expect(!redacted.contains(value), "Client-ID value should be redacted")
    }

    @Test("Does not redact normal text")
    func testNormalTextNotRedacted() {
        // No 8+ digit runs or 30+ char tokens, so nothing should match a rule.
        let message = "Normal log message with no sensitive data here"

        #expect(Log.redactForTesting(message) == message,
            "Normal text should pass through redaction unchanged")
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
        Log.flush()

        // Export and read log file
        guard let logURL = Log.exportLogFile() else {
            Issue.record("Failed to export log file")
            return
        }

        // Concurrent suites write into the same global log; a burst can rotate
        // it and move our line into the .1 backup, so scan both.
        let logContent = readLogIncludingBackup(at: logURL)

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
        Log.flush()

        // In release builds, this should not be written
        // In debug builds, it should be written
        #if DEBUG
        if let logURL = Log.exportLogFile() {
            let content = readLogIncludingBackup(at: logURL)
            #expect(content.contains(debugMessage))
        }
        #else
        if let logURL = Log.exportLogFile() {
            let content = readLogIncludingBackup(at: logURL)
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

        // Log writes are dispatched async onto the file queue — drain it
        // before reading so CI doesn't see a half-flushed snapshot.
        Log.flush()

        // Verify at least some of the concurrent messages were written.
        // Log rotation (>5MB) can split writes between wolfwave.log and the
        // rotated wolfwave.log.1 backup if a prior test pushed the file near
        // the limit, so scan both files when checking for our markers.
        guard let logURL = Log.exportLogFile() else {
            Issue.record("Failed to export log file")
            return
        }
        let combined = readLogIncludingBackup(at: logURL)

        #expect(combined.contains("Concurrent log \(uniquePrefix)_0"),
            "First concurrent log message should be present")
        #expect(combined.contains("Concurrent log \(uniquePrefix)_\(iterations - 1)"),
            "Last concurrent log message should be present")
    }

    /// Reads the current log file plus its rotated `.1` backup if present,
    /// concatenated. Tolerates a rotation that happened mid-test run.
    private func readLogIncludingBackup(at url: URL) -> String {
        var content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let backupURL = url.deletingLastPathComponent().appending(path: "wolfwave.log.1")
        if FileManager.default.fileExists(atPath: backupURL.path),
           let backup = try? String(contentsOf: backupURL, encoding: .utf8) {
            content += backup
        }
        return content
    }
    
    // MARK: - Category Tests
    
    @Test("Different categories are logged correctly")
    func testCategories() async throws {
        Log.info("App message", category: "App")
        Log.info("Network message", category: "Network")
        Log.info("Twitch message", category: "Twitch")
        Log.info("OAuth message", category: "OAuth")
        Log.flush()

        guard let logURL = Log.exportLogFile() else {
            Issue.record("Failed to export log file")
            return
        }

        let content = readLogIncludingBackup(at: logURL)

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
