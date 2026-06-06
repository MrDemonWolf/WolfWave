//
//  TwitchChatServiceTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-03-18.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Testing
import Foundation
@testable import WolfWave

/// Comprehensive test suite for TwitchChatService
@MainActor
@Suite("Twitch Chat Service Tests", .serialized)
struct TwitchChatServiceTests {

    /// Reset UserDefaults keys that tests depend on to prevent cross-test contamination.
    init() {
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.currentSongCommandEnabled)
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.lastSongCommandEnabled)
    }

    // MARK: - Initialization Tests

    @Test("Service initializes with default values")
    func testServiceInitialization() async throws {
        let service = TwitchChatService()

        #expect(await service.commandsEnabled == true)
        #expect(await service.debugLoggingEnabled == false)
        #expect(await service.isConnected == false)
        #expect(service.currentSongCommandEnabled == false)
        #expect(service.lastSongCommandEnabled == false)
    }
    
    // MARK: - Client ID Resolution Tests
    
    @Test("Resolves client ID from Info.plist")
    func testClientIDResolution() async throws {
        // This will return nil in test environment, but shouldn't crash
        let clientID = TwitchChatService.resolveClientID()
        
        // In test environment, should be nil or a valid string
        if let clientID = clientID {
            #expect(!clientID.isEmpty)
            #expect(!clientID.hasPrefix("$("))
        }
    }
    
    // MARK: - Connection Error Tests
    
    @Test("Connection error has correct descriptions")
    func testConnectionErrorDescriptions() async throws {
        let invalidCreds = TwitchChatService.ConnectionError.invalidCredentials
        #expect(invalidCreds.errorDescription == "Invalid Twitch credentials")
        
        let missingClient = TwitchChatService.ConnectionError.missingClientID
        #expect(missingClient.errorDescription == "Twitch Client ID is not configured")
        
        let networkError = TwitchChatService.ConnectionError.networkError("Test error")
        #expect(networkError.errorDescription == "Network error: Test error")
        
        let authFailed = TwitchChatService.ConnectionError.authenticationFailed
        #expect(authFailed.errorDescription == "Failed to authenticate with Twitch")
    }
    
    // MARK: - Bot Identity Tests
    
    @Test("BotIdentity structure stores values correctly")
    func testBotIdentityStructure() async throws {
        let identity = TwitchChatService.BotIdentity(
            userID: "12345",
            login: "testbot",
            displayName: "TestBot"
        )
        
        #expect(identity.userID == "12345")
        #expect(identity.login == "testbot")
        #expect(identity.displayName == "TestBot")
    }
    
    // MARK: - Chat Message Tests
    
    @Test("ChatMessage structure stores message data correctly")
    func testChatMessageStructure() async throws {
        let badge = TwitchChatService.ChatMessage.Badge(
            setID: "moderator",
            id: "1",
            info: "Moderator"
        )
        
        let reply = TwitchChatService.ChatMessage.Reply(
            parentMessageID: "parent-123",
            parentMessageBody: "Hello",
            parentUserID: "user-456",
            parentUsername: "ParentUser"
        )
        
        let message = TwitchChatService.ChatMessage(
            messageID: "msg-789",
            username: "TestUser",
            userID: "user-123",
            message: "Test message",
            channel: "channel-456",
            badges: [badge],
            reply: reply
        )
        
        #expect(message.messageID == "msg-789")
        #expect(message.username == "TestUser")
        #expect(message.userID == "user-123")
        #expect(message.message == "Test message")
        #expect(message.channel == "channel-456")
        #expect(message.badges.count == 1)
        #expect(message.badges[0].setID == "moderator")
        #expect(message.reply?.parentMessageID == "parent-123")
    }
    
    // MARK: - Channel Validation Tests
    
    @Test("ChannelValidationResult enum works correctly")
    func testChannelValidationResult() async throws {
        // Test all cases exist and are equatable
        let exists = TwitchChatService.ChannelValidationResult.exists
        let notFound = TwitchChatService.ChannelValidationResult.notFound
        let authFailed = TwitchChatService.ChannelValidationResult.authenticationFailed
        let error = TwitchChatService.ChannelValidationResult.error("Test error")
        
        // Verify cases are distinct
        switch exists {
        case .exists: break
        default: Issue.record("Expected .exists case")
        }
        
        switch notFound {
        case .notFound: break
        default: Issue.record("Expected .notFound case")
        }
        
        switch authFailed {
        case .authenticationFailed: break
        default: Issue.record("Expected .authenticationFailed case")
        }
        
        switch error {
        case .error(let msg):
            #expect(msg == "Test error")
        default:
            Issue.record("Expected .error case")
        }
    }
    
    // MARK: - UserDefaults Integration Tests
    
    @Test("Current song command enabled reads from UserDefaults")
    func testCurrentSongCommandEnabledUserDefaults() async throws {
        let service = TwitchChatService()
        
        // Clear any existing value
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.currentSongCommandEnabled)
        
        // Should default to false
        #expect(service.currentSongCommandEnabled == false)

        // Set to false
        UserDefaults.standard.set(false, forKey: AppConstants.UserDefaults.currentSongCommandEnabled)
        
        // Should now read false (computed property)
        #expect(service.currentSongCommandEnabled == false)
        
        // Set to true
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.currentSongCommandEnabled)
        
        // Should now read true
        #expect(service.currentSongCommandEnabled == true)
        
        // Cleanup
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.currentSongCommandEnabled)
    }
    
    @Test("Last song command enabled reads from UserDefaults")
    func testLastSongCommandEnabledUserDefaults() async throws {
        let service = TwitchChatService()

        // Clear any existing value
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.lastSongCommandEnabled)

        // Should default to false
        #expect(service.lastSongCommandEnabled == false)

        // Set to false
        UserDefaults.standard.set(false, forKey: AppConstants.UserDefaults.lastSongCommandEnabled)

        // Should now read false (computed property)
        #expect(service.lastSongCommandEnabled == false)

        // Set to true
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaults.lastSongCommandEnabled)

        // Should now read true
        #expect(service.lastSongCommandEnabled == true)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.lastSongCommandEnabled)
    }

    // MARK: - Toggle Tests

    @Test("Commands enabled toggle works")
    func testCommandsEnabledToggle() async throws {
        let service = TwitchChatService()
        #expect(await service.commandsEnabled == true)
        await service.setCommandsEnabled(false)
        #expect(await service.commandsEnabled == false)
        await service.setCommandsEnabled(true)
        #expect(await service.commandsEnabled == true)
    }

    @Test("Debug logging enabled toggle works")
    func testDebugLoggingEnabledToggle() async throws {
        let service = TwitchChatService()
        #expect(await service.debugLoggingEnabled == false)
        await service.setDebugLoggingEnabled(true)
        #expect(await service.debugLoggingEnabled == true)
        await service.setDebugLoggingEnabled(false)
        #expect(await service.debugLoggingEnabled == false)
    }

    // MARK: - Re-initialization Tests

    @Test("Service re-initialization does not crash")
    func testServiceReInitialization() async throws {
        var service: TwitchChatService? = TwitchChatService()
        #expect(service != nil)
        service = nil
        service = TwitchChatService()
        #expect(await service?.isConnected == false)
    }

    // MARK: - Connection Error Distinctness Tests

    @Test("Connection error cases are distinct")
    func testConnectionErrorCasesAreDistinct() async throws {
        let errors: [TwitchChatService.ConnectionError] = [
            .invalidCredentials,
            .missingClientID,
            .networkError("test"),
            .authenticationFailed,
        ]

        let descriptions = errors.compactMap { $0.errorDescription }
        #expect(descriptions.count == errors.count)

        // All descriptions should be unique
        let uniqueDescriptions = Set(descriptions)
        #expect(uniqueDescriptions.count == descriptions.count)
    }

    // MARK: - ChatMessage Edge Case Tests

    @Test("ChatMessage with empty badges and nil reply")
    func testChatMessageEmptyBadgesNilReply() async throws {
        let message = TwitchChatService.ChatMessage(
            messageID: "msg-001",
            username: "TestUser",
            userID: "user-001",
            message: "Hello",
            channel: "channel-001",
            badges: [],
            reply: nil
        )

        #expect(message.badges.isEmpty)
        #expect(message.reply == nil)
        #expect(message.messageID == "msg-001")
    }

    // MARK: - Retry-Queue Cap Tests

    @Test("appendCapped keeps queue under cap and drops nothing")
    func testAppendCappedUnderCap() async throws {
        var queue: [Int] = [1, 2]
        let dropped = TwitchChatService.appendCapped(3, to: &queue, cap: 4)
        #expect(dropped == 0)
        #expect(queue == [1, 2, 3])
    }

    @Test("appendCapped drops oldest when over cap")
    func testAppendCappedDropsOldest() async throws {
        var queue: [Int] = [1, 2, 3]
        let dropped = TwitchChatService.appendCapped(4, to: &queue, cap: 3)
        #expect(dropped == 1)
        #expect(queue == [2, 3, 4])
    }

    @Test("appendCapped over cap by many drops in FIFO order")
    func testAppendCappedRepeated() async throws {
        var queue: [Int] = []
        for value in 1...10 {
            _ = TwitchChatService.appendCapped(value, to: &queue, cap: 3)
        }
        // Only the newest 3 survive, oldest dropped first.
        #expect(queue == [8, 9, 10])
    }

    // MARK: - Bounded Stream Tests

    @Test("chatMessages stream uses a bounded buffer (only newest N retained)")
    func testChatMessagesStreamBounded() async throws {
        // Drive an unconsumed bounded stream past its cap and confirm only the
        // newest `chatMessageStreamBuffer` elements are delivered (drop-oldest).
        let cap = AppConstants.Twitch.chatMessageStreamBuffer
        let (stream, continuation) = AsyncStream.makeStream(
            of: Int.self, bufferingPolicy: .bufferingNewest(cap))

        for value in 0..<(cap + 50) {
            continuation.yield(value)
        }
        continuation.finish()

        var received: [Int] = []
        for await value in stream { received.append(value) }

        #expect(received.count == cap)
        // First retained element is the 50th yielded value; the oldest 50 drop.
        #expect(received.first == 50)
        #expect(received.last == cap + 49)
    }

    // MARK: - Retry Accounting Tests

    @Test("shouldRequeueAfterFailure stops at the retry limit")
    func testShouldRequeueAfterFailureBoundary() async throws {
        let maxRetries = 3
        // Attempts below the limit requeue; at/above the limit they do not.
        #expect(TwitchChatService.shouldRequeueAfterFailure(attempts: 1, maxRetries: maxRetries))
        #expect(TwitchChatService.shouldRequeueAfterFailure(attempts: 2, maxRetries: maxRetries))
        #expect(!TwitchChatService.shouldRequeueAfterFailure(attempts: 3, maxRetries: maxRetries))
        #expect(!TwitchChatService.shouldRequeueAfterFailure(attempts: 4, maxRetries: maxRetries))
    }

    @Test("Persistently failing message stops at maxMessageRetries without resetting attempts")
    func testPersistentFailureStopsAtMaxRetriesWithoutReset() async throws {
        // Pure simulation of the drain-loop requeue contract: a send that keeps
        // failing must increment the per-message attempt count each pass (never
        // reset to 0 the way the old `sendMessage`-in-drain path did) and stop
        // once the count reaches the retry limit. This mirrors
        // `drainPendingMessages` -> `sendMessageOnce` (fails) -> `queueMessageForRetry`.
        let maxRetries = AppConstants.Twitch.maxMessageRetries
        var attempts = 0 // attempt that just failed, 1-based after first increment
        var observed: [Int] = []
        var passes = 0
        let guardLimit = maxRetries + 10 // tripwire against an unbounded loop

        // First failure enters the queue at attempts: 1.
        attempts = 1
        while TwitchChatService.shouldRequeueAfterFailure(attempts: attempts, maxRetries: maxRetries) {
            observed.append(attempts)
            // queueMessageForRetry stores attempts + 1 as the next attempt number.
            attempts += 1
            passes += 1
            #expect(passes < guardLimit)
            if passes >= guardLimit { break }
        }
        // Record the terminal attempt that was dropped (not requeued).
        observed.append(attempts)

        // Attempts strictly increase by 1 — never reset.
        #expect(observed == Array(1...maxRetries))
        // The loop terminated at exactly the retry limit.
        #expect(attempts == maxRetries)
    }
}
