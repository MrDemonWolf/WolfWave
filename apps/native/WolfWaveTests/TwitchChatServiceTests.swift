//
//  TwitchChatServiceTests.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import Testing
import Foundation
@testable import WolfWave

/// Comprehensive test suite for TwitchChatService
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

        #expect(service.commandsEnabled == true)
        #expect(service.debugLoggingEnabled == false)
        #expect(service.isConnected == false)
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
        #expect(service.commandsEnabled == true)
        service.commandsEnabled = false
        #expect(service.commandsEnabled == false)
        service.commandsEnabled = true
        #expect(service.commandsEnabled == true)
    }

    @Test("Debug logging enabled toggle works")
    func testDebugLoggingEnabledToggle() async throws {
        let service = TwitchChatService()
        #expect(service.debugLoggingEnabled == false)
        service.debugLoggingEnabled = true
        #expect(service.debugLoggingEnabled == true)
        service.debugLoggingEnabled = false
        #expect(service.debugLoggingEnabled == false)
    }

    // MARK: - Re-initialization Tests

    @Test("Service re-initialization does not crash")
    func testServiceReInitialization() async throws {
        var service: TwitchChatService? = TwitchChatService()
        #expect(service != nil)
        service = nil
        service = TwitchChatService()
        #expect(service?.isConnected == false)
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
}
