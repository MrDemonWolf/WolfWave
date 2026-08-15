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

/// Comprehensive test suite for logging functionality.
///
/// Marked `.serialized` because every test in this suite reads and writes the
/// one process-global `Log` instance (there is no per-test log file). Swift
/// Testing runs a suite's tests in parallel by default, so without serialization
/// the log-clear tests and the file-readback tests inside *this* suite would
/// interleave: `clearLogFile()` can truncate the shared file while a readback is
/// in flight, evicting the unique message it just wrote.
///
/// The clear tests are direct members of this serialized suite rather than a
/// nested sub-suite on purpose: `.serialized` orders a suite's own tests but did
/// NOT serialize a nested sub-suite against the parent's tests, so the previous
/// `LoggerTests.ClearTests` sub-suite still raced the parent.
///
/// `.serialized` cannot fix the *cross-suite* case: tests in OTHER suites share
/// the same global `Log` and may rotate or append to the file concurrently with
/// this suite. Two things keep that tolerable now:
///
/// 1. Under XCTest the severity gate defaults to `.error` and applies to the
///    **file sink**, not just OSLog. Ordinary `.info` chatter from other suites
///    no longer reaches the file at all, which removes most of the churn that
///    used to rotate it mid-test.
/// 2. `readLogIncludingBackups` also checks the rotated backups, so a rotation
///    triggered elsewhere does not drop the message under test.
@MainActor
@Suite("Logger Tests", .serialized)
struct LoggerTests {

    // MARK: - Log Level Tests

    @Test("Log levels have bare, greppable raw values")
    func testLogLevelRawValues() async throws {
        // Deliberately not emoji-prefixed. An emoji is multi-codepoint and
        // variable-width in bytes, which makes the level column impossible to
        // align and `grep -c ERROR` ambiguous against message text.
        #expect(LogLevel.debug.rawValue == "DEBUG")
        #expect(LogLevel.info.rawValue == "INFO")
        #expect(LogLevel.warn.rawValue == "WARN")
        #expect(LogLevel.error.rawValue == "ERROR")
    }

    // MARK: - PII Redaction Tests
    //
    // Redaction is verified against the pure `Log.redactForTesting` pipeline
    // rather than by writing a line and reading it back from the on-disk log.
    // `Log` is a process-global singleton, so other suites write into the same
    // app-wide file concurrently. A large enough burst can rotate that file
    // mid-test and evict the line we just wrote, which made these readback
    // assertions flaky in CI. Testing the redaction function directly is
    // deterministic and needs no file at all.

    // Token fixtures below are synthetic placeholders, not real credentials.
    // The redaction rules key on the `oauth_` / `Bearer ` prefixes (see
    // Logger.swift), so low-entropy readable values exercise them fully while
    // keeping secret scanners (GitGuardian) quiet. Avoid random/UUID suffixes.

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
        // No digit runs in an ID context, no 9+ digit run, and no 30+ char
        // token, so nothing should match a rule.
        let message = "Normal log message with no sensitive data here"

        #expect(Log.redactForTesting(message) == message,
            "Normal text should pass through redaction unchanged")
    }

    // MARK: - Redaction: identifiers still die
    //
    // The numeric rule was narrowed from a blanket `\b\d{6,}\b`. These cases
    // pin the sensitive half of that narrowing: an identifier must still be
    // unreadable in an exported log.

    @Test("Redacts identifiers in a keyed context", arguments: [
        "user_id: 123456789",
        "userID=123456789",
        "broadcaster_user_id=123456789",
        "channel_id: 44322889",
        "moderator_id=1234567",
        "id=987654321",
        "chatterId: 5551234"
    ])
    func testKeyedIdentifierRedaction(_ input: String) {
        let redacted = Log.redactForTesting(input)

        #expect(redacted.contains("[USER_ID_REDACTED]"),
            "Keyed identifier should be redacted: \(input) → \(redacted)")
        #expect(!redacted.contains("123456789") && !redacted.contains("44322889"),
            "Identifier digits must not survive: \(redacted)")
    }

    @Test("Keyed redaction keeps the key so the line still reads")
    func testKeyedRedactionPreservesKey() {
        let redacted = Log.redactForTesting("Resolved broadcaster_user_id=123456789 for channel")

        #expect(redacted.contains("broadcaster_user_id"),
            "Key should survive, only the value is sensitive: \(redacted)")
        #expect(redacted.contains("[USER_ID_REDACTED]"))
    }

    @Test("Redacts very long bare digit runs")
    func testLongBareDigitRunRedaction() {
        // 12 digits with no key. Nothing legitimate in this app logs a bare
        // number that long, so it is assumed to be an identifier.
        let redacted = Log.redactForTesting("Saw 123456789012 in the payload")

        #expect(redacted.contains("[USER_ID_REDACTED]"))
        #expect(!redacted.contains("123456789012"))
    }

    // MARK: - Redaction: evidence survives
    //
    // The other half of the narrowing. The old blanket rule rewrote every 6+
    // digit number, so byte counts, durations, ports, and epoch values all came
    // back as `[USER_ID_REDACTED]` in the one artifact a user hands over. These
    // cases pin that this no longer happens.

    @Test("Does not redact legitimate numbers in prose", arguments: [
        "Wrote 524288 bytes to the socket",
        "Request completed in 145200 microseconds",
        "Bound to port 8765 successfully",
        "Cache holds 12345 tracks"
    ])
    func testLegitimateNumbersSurvive(_ input: String) {
        #expect(Log.redactForTesting(input) == input,
            "Diagnostic numbers must survive redaction: \(input)")
    }

    @Test("Numeric-safe field keys survive the bare-digit rule")
    func testNumericSafeFieldValuesSurvive() {
        // 10 digits: past the bare-digit threshold, but `bytes` is a known-safe
        // key so the value is evidence, not an identifier.
        #expect(Log.redactFieldForTesting("1073741824", key: "bytes") == "1073741824")
        #expect(Log.redactFieldForTesting("1755180000", key: "epoch") == "1755180000")
        #expect(Log.redactFieldForTesting("8765", key: "port") == "8765")
    }

    @Test("Sensitive field keys are redacted wholesale")
    func testSensitiveFieldValuesRedacted() {
        #expect(Log.redactFieldForTesting("anything-at-all", key: "token") == "[REDACTED]")
        #expect(Log.redactFieldForTesting("123456789", key: "user_id") == "[REDACTED]")
        #expect(Log.redactFieldForTesting("hunter2", key: "password") == "[REDACTED]")
    }

    @Test("Unknown field keys get the full prose treatment")
    func testUnknownFieldValuesRedactedAsProse() {
        // Not a known-safe key, so the bare-digit rule still applies.
        #expect(Log.redactFieldForTesting("123456789012", key: "mystery")
            == "[USER_ID_REDACTED]")
    }

    // MARK: - Line Format

    @Test("Log line starts with an ISO-8601 timestamp at column 0")
    func testLineStartsWithISOTimestamp() {
        let line = Log.formatFileLineForTesting("Hello", level: .info, category: "App")

        // The single invariant every reader depends on.
        let head = String(line.prefix(29))
        #expect(LogRecord.parse(line) != nil, "Own output must parse: \(line)")
        #expect(head.contains("T"), "Expected an ISO stamp, got: \(head)")
        #expect(line.first?.isNumber == true, "Timestamp must be at column 0")
    }

    @Test("Log file line contains expected content")
    func testLogFileContent() async throws {
        // Build the exact line the file sink would write, rather than reading
        // back the process-global log. Other suites share that file and can
        // rotate it mid-test, which made the readback assertion flaky in CI.
        // The real disk-write path stays covered by `testLogFileExport`.
        //
        // Marker is a fixed, non-numeric token so no redaction rule can touch
        // it: no digit run in a keyed context, no 9+ digit run, and no 30+ char
        // alphanumeric run.
        let testMessage = "Test log message marker-AB12-CD34-EF56"
        let line = Log.formatFileLineForTesting(testMessage, level: .info, category: "TestCategory")

        #expect(line.contains(testMessage))
        #expect(line.contains("INFO"))
        #expect(line.contains("TestCategory"))
    }

    @Test("Structured fields render as a quoted key=value tail")
    func testStructuredFieldRendering() {
        let line = Log.formatFileLineForTesting(
            "Reconnect failed",
            level: .error,
            category: "Twitch",
            fields: ["attempt": 3, "code": 4003, "reason": "transport closed"]
        )

        #expect(line.contains("attempt=3"))
        #expect(line.contains("code=4003"))
        // Value contains a space, so it must be quoted or the grammar breaks.
        #expect(line.contains(#"reason="transport closed""#))
    }

    @Test("Field values are redacted but field keys are not")
    func testFieldRedactionInRenderedLine() {
        let line = Log.formatFileLineForTesting(
            "Authenticated",
            level: .info,
            category: "Twitch",
            fields: ["user_id": 123456789, "bytes": 1048576]
        )

        #expect(line.contains("user_id=[REDACTED]"), "Sensitive value must go: \(line)")
        #expect(line.contains("bytes=1048576"), "Safe numeric value must stay: \(line)")
    }

    @Test("Continuation lines are indented so they cannot be mistaken for records")
    func testContinuationFraming() {
        let framed = Log.frameContinuationsForTesting("first\nsecond\nthird")

        let lines = framed.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 3)
        #expect(lines[0] == "first", "First line keeps column 0")
        #expect(lines[1] == "  second")
        #expect(lines[2] == "  third")
    }

    @Test("Session banner identifies the build")
    func testSessionBanner() {
        let banner = Log.sessionBannerLineForTesting()

        guard let record = LogRecord.parse(banner) else {
            Issue.record("Session banner must parse as a record: \(banner)")
            return
        }

        let keys = Set(record.fields.map(\.key))
        #expect(keys.isSuperset(of: ["session", "version", "build", "os", "arch"]),
            "Banner is what attributes a log to a build, got keys: \(keys)")
        #expect(record.level == .info)
        #expect(record.category == LogCategory.app.rawValue)
    }

    // MARK: - Log File Tests

    @Test("Log file can be exported")
    func testLogFileExport() async throws {
        // `.error` rather than `.info`: under XCTest the severity gate defaults
        // to `.error` and now covers the file sink, so info lines never land.
        Log.error("Test log entry 1", category: .dev)
        Log.error("Test log entry 2", category: .dev)
        Log.flush()

        let logURL = Log.exportLogFile()

        #expect(logURL != nil)

        if let url = logURL {
            let fileExists = FileManager.default.fileExists(atPath: url.path)
            #expect(fileExists)
        }
    }

    // MARK: - Debug Logging Tests

    @Test("Debug logs are gated to debug builds")
    func testDebugLogging() {
        // The build gate decides whether Log.debug emits at all. Assert it
        // directly. The old version wrote a debug line and read it back from
        // the app-wide on-disk log, which parallel suites can rotate away
        // mid-test (Log is a process-global singleton), making it flaky in CI.
        #if DEBUG
        #expect(Log.debugLoggingEnabledForTesting, "Debug logging must be on in DEBUG builds")
        #endif

        // The real write path must not crash under the active gate.
        Log.debug("Debug message \(UUID().uuidString)", category: .dev)
        Log.flush()
    }

    // MARK: - Concurrent Logging Tests

    @Test("Concurrent logging is thread-safe")
    func testConcurrentLogging() async {
        let iterations = 100
        let uniquePrefix = UUID().uuidString

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    // `.error` so the line survives the XCTest severity gate.
                    Log.error("Concurrent log \(uniquePrefix)_\(i)", category: .dev)
                }
            }
        }

        // Log writes are dispatched async onto the file queue. Drain it
        // before reading so CI doesn't see a half-flushed snapshot.
        Log.flush()

        // Thread-safety means the concurrent burst neither crashes nor corrupts
        // the file. Reaching here proves no crash. We do NOT require our exact
        // lines to survive: Log is a process-global singleton, so parallel
        // suites can rotate or truncate the shared file mid-test, which made the
        // old line-survival assertions flaky in CI. Instead we verify that any
        // of our markers that DID land are intact, never spliced together by a
        // data race.
        guard let logURL = Log.exportLogFile() else {
            Issue.record("Failed to export log file")
            return
        }
        let combined = readLogIncludingBackups(at: logURL)
        let marker = "Concurrent log \(uniquePrefix)_"

        for line in combined.split(separator: "\n") where line.contains(marker) {
            let parts = line.components(separatedBy: marker)
            #expect(parts.count == 2, "Torn or interleaved concurrent write: \(line)")
            let indexToken = (parts.last ?? "").prefix(while: { $0.isNumber })
            #expect(!indexToken.isEmpty && Int(indexToken) != nil,
                "Concurrent marker index not intact: \(line)")
        }
    }

    /// Reads the current log file plus every rotated backup, concatenated.
    /// Tolerates a rotation that happened mid-test run.
    private func readLogIncludingBackups(at url: URL) -> String {
        var content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        for index in 1...3 {
            let backupURL = url.deletingLastPathComponent().appending(path: "wolfwave.log.\(index)")
            if FileManager.default.fileExists(atPath: backupURL.path),
               let backup = try? String(contentsOf: backupURL, encoding: .utf8) {
                content += backup
            }
        }
        return content
    }

    // MARK: - Category Tests

    @Test("Different categories are logged correctly")
    func testCategories() async throws {
        // Assert against the pure line builder. Reading these back from the
        // shared on-disk log raced other suites; the category column is a pure
        // formatting concern and needs no file.
        for category in ["App", "Network", "Twitch", "OAuth"] {
            let line = Log.formatFileLineForTesting("message", category: category)
            guard let record = LogRecord.parse(line) else {
                Issue.record("Line did not parse for category \(category): \(line)")
                continue
            }
            #expect(record.category == category)
        }
    }

    @Test("Every LogCategory case round-trips through the line format")
    func testAllCategoriesRoundTrip() {
        for category in LogCategory.allCases {
            let line = Log.formatFileLineForTesting("message", category: category.rawValue)
            #expect(LogRecord.parse(line)?.category == category.rawValue,
                "Category \(category.rawValue) failed to round-trip")
        }
    }

    @Test("Category raw values fit the aligned column")
    func testCategoryRawValuesFitColumn() {
        // A raw value longer than the column width overflows and ragged-edges
        // the message column for every line in that category. Caught here rather
        // than by squinting at a log file.
        for category in LogCategory.allCases {
            #expect(category.rawValue.count <= Log.categoryWidth,
                "\(category.rawValue) is \(category.rawValue.count) chars, over the \(Log.categoryWidth) column")
        }
    }

    @Test("Category raw values are unique and contain no spaces")
    func testCategoryRawValuesAreDistinct() {
        // Two cases sharing a raw value would silently merge in Console.app's
        // Category filter; a space would break the line's field separation.
        let values = LogCategory.allCases.map(\.rawValue)
        #expect(Set(values).count == values.count, "Duplicate raw values in LogCategory")

        for value in values {
            #expect(!value.contains(" "), "Category '\(value)' contains a space")
            #expect(!value.isEmpty)
        }
    }

    // MARK: - Log Clearing Tests
    //
    // Direct members of this `.serialized` suite (not a nested sub-suite) so the
    // truncating `clearLogFile()` never runs concurrently with the file-readback
    // tests above. See the suite doc comment for why nesting was insufficient.

    @Test("Log file size is non-negative")
    func logFileSizeIsNonNegative() {
        #expect(Log.logFileSize() >= 0)
    }

    @Test("Log line count is non-negative")
    func logLineCountIsNonNegative() {
        #expect(Log.logLineCount() >= 0)
    }

    @Test("Clearing the log truncates the file and writes a parseable header")
    func clearLogFileTruncatesAndWritesHeader() {
        Log.error("Pre-clear marker", category: .dev)
        Log.error("Another line", category: .dev)
        Log.flush()

        let sizeBefore = Log.logFileSize()
        Log.clearLogFile()
        let sizeAfter = Log.logFileSize()

        #expect(sizeAfter < sizeBefore + 1)
        #expect(sizeAfter > 0, "header line should be written")

        // The header used to be hand-built in a second, incompatible shape
        // (`[stamp] emoji LEVEL [Cat] msg`), which broke any parser reading the
        // file. It now goes through the same builder as every other record.
        guard let url = Log.exportLogFile(),
              let contents = try? String(contentsOf: url, encoding: .utf8),
              let firstLine = contents.split(separator: "\n").first
        else {
            Issue.record("Could not read back the cleared log")
            return
        }

        guard let record = LogRecord.parse(String(firstLine)) else {
            Issue.record("Clear header is not a parseable record: \(firstLine)")
            return
        }
        #expect(record.message == "Log cleared by user")
        #expect(record.level == .info)
    }

    @Test("Clearing the log leaves no NUL padding behind")
    func clearLogFileLeavesNoNulGap() {
        // Regression: `clearLogFile` used to seek + truncate through the live
        // file handle. The handle kept its old write offset, so a write landing
        // at that offset re-extended the freshly truncated file with a NUL gap
        // exactly the size of the old log. A 300 KB log cleared to a 300 KB
        // file of zero bytes, and the old `lineCount == 1` assertion still
        // passed because NUL bytes contain no newlines.
        Log.error("Fill the log with something", category: .dev)
        Log.flush()

        Log.clearLogFile()

        guard let url = Log.exportLogFile(),
              let data = try? Data(contentsOf: url)
        else {
            Issue.record("Could not read back the cleared log")
            return
        }

        #expect(!data.contains(0), "Cleared log must not contain NUL padding")
        #expect(data.count < 512, "Cleared log should hold only the header, got \(data.count) bytes")
    }
}
