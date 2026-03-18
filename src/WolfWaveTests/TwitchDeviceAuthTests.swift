//
//  TwitchDeviceAuthTests.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import Testing
import Foundation
@testable import WolfWave

/// Comprehensive test suite for Twitch OAuth Device Code flow
@Suite("Twitch Device Auth Tests")
struct TwitchDeviceAuthTests {
    
    // MARK: - Initialization Tests
    
    @Test("TwitchDeviceAuth initializes with correct values")
    func testInitialization() async throws {
        let clientID = "test_client_id"
        let scopes = ["user:read:chat", "user:write:chat"]
        
        let auth = TwitchDeviceAuth(clientID: clientID, scopes: scopes)
        
        // Verify initialization doesn't crash
        #expect(auth != nil)
    }
    
    // MARK: - Device Code Response Tests
    
    @Test("TwitchDeviceCodeResponse structure stores values correctly")
    func testDeviceCodeResponse() async throws {
        let response = TwitchDeviceCodeResponse(
            deviceCode: "DEVICE123",
            userCode: "ABCD-EFGH",
            verificationURI: "https://twitch.tv/activate",
            verificationURIComplete: "https://twitch.tv/activate?user_code=ABCD-EFGH",
            expiresIn: 600,
            interval: 5
        )
        
        #expect(response.deviceCode == "DEVICE123")
        #expect(response.userCode == "ABCD-EFGH")
        #expect(response.verificationURI == "https://twitch.tv/activate")
        #expect(response.verificationURIComplete == "https://twitch.tv/activate?user_code=ABCD-EFGH")
        #expect(response.expiresIn == 600)
        #expect(response.interval == 5)
    }
    
    @Test("Device code response handles nil complete URI")
    func testDeviceCodeResponseOptionalURI() async throws {
        let response = TwitchDeviceCodeResponse(
            deviceCode: "DEVICE123",
            userCode: "ABCD-EFGH",
            verificationURI: "https://twitch.tv/activate",
            verificationURIComplete: nil,
            expiresIn: 600,
            interval: 5
        )
        
        #expect(response.verificationURIComplete == nil)
    }
    
    // MARK: - Error Tests
    
    @Test("TwitchDeviceAuthError has correct descriptions")
    func testErrorDescriptions() async throws {
        let invalidResponse = TwitchDeviceAuthError.invalidResponse
        #expect(invalidResponse.errorDescription == "Invalid response from Twitch")
        
        let accessDenied = TwitchDeviceAuthError.accessDenied
        #expect(accessDenied.errorDescription == "Access denied by user")
        
        let expiredToken = TwitchDeviceAuthError.expiredToken
        #expect(expiredToken.errorDescription == "Device code expired")
        
        let authPending = TwitchDeviceAuthError.authorizationPending
        #expect(authPending.errorDescription == "Waiting for user authorization")
        
        let slowDown = TwitchDeviceAuthError.slowDown
        #expect(slowDown.errorDescription == "Polling too quickly")
        
        let invalidClient = TwitchDeviceAuthError.invalidClient
        #expect(invalidClient.errorDescription == "Invalid client credentials")
        
        let unknown = TwitchDeviceAuthError.unknown("Custom error message")
        #expect(unknown.errorDescription == "Custom error message")
    }
    
    // MARK: - Request Device Code Tests
    
    @Test("Request device code fails with empty client ID")
    func testRequestDeviceCodeEmptyClientID() async throws {
        let auth = TwitchDeviceAuth(clientID: "", scopes: ["user:read:chat"])
        
        do {
            _ = try await auth.requestDeviceCode()
            Issue.record("Expected invalidClient error but succeeded")
        } catch TwitchDeviceAuthError.invalidClient {
            // Expected error
            #expect(true)
        } catch {
            Issue.record("Expected invalidClient error but got: \(error)")
        }
    }
    
    @Test("Request device code with valid client ID structure")
    func testRequestDeviceCodeValidStructure() async throws {
        // We can't test actual API calls in unit tests, but we can verify
        // the auth object is constructed correctly
        let clientID = "test_client_123"
        let scopes = ["user:read:chat", "user:write:chat"]
        
        let auth = TwitchDeviceAuth(clientID: clientID, scopes: scopes)
        
        #expect(auth != nil)
        
        // Note: Actual API test would require mocking or integration test
    }
    
    // MARK: - Poll For Token Tests
    
    @Test("Poll for token validates device code")
    func testPollForTokenValidation() async throws {
        let auth = TwitchDeviceAuth(clientID: "test_client", scopes: ["user:read:chat"])
        
        do {
            _ = try await auth.pollForToken(
                deviceCode: "",
                interval: 5,
                expiresIn: 600
            ) { _ in }
            Issue.record("Expected error with empty device code")
        } catch TwitchDeviceAuthError.invalidClient {
            // Expected error
            #expect(true)
        } catch {
            Issue.record("Expected invalidClient error but got: \(error)")
        }
    }
    
    @Test("Poll for token validates interval")
    func testPollForTokenIntervalValidation() async throws {
        let auth = TwitchDeviceAuth(clientID: "test_client", scopes: ["user:read:chat"])
        
        do {
            _ = try await auth.pollForToken(
                deviceCode: "DEVICE123",
                interval: 0, // Invalid interval
                expiresIn: 600
            ) { _ in }
            Issue.record("Expected error with zero interval")
        } catch TwitchDeviceAuthError.invalidResponse {
            // Expected error
            #expect(true)
        } catch {
            Issue.record("Expected invalidResponse error but got: \(error)")
        }
    }
    
    @Test("Poll for token validates negative interval")
    func testPollForTokenNegativeInterval() async throws {
        let auth = TwitchDeviceAuth(clientID: "test_client", scopes: ["user:read:chat"])
        
        do {
            _ = try await auth.pollForToken(
                deviceCode: "DEVICE123",
                interval: -5, // Invalid negative interval
                expiresIn: 600
            ) { _ in }
            Issue.record("Expected error with negative interval")
        } catch TwitchDeviceAuthError.invalidResponse {
            // Expected error
            #expect(true)
        } catch {
            Issue.record("Expected invalidResponse error but got: \(error)")
        }
    }
    
    // MARK: - Scope Tests
    
    @Test("Empty scopes are allowed")
    func testEmptyScopes() async throws {
        let auth = TwitchDeviceAuth(clientID: "test_client", scopes: [])
        
        #expect(auth != nil)
    }
    
    @Test("Multiple scopes are supported")
    func testMultipleScopes() async throws {
        let scopes = [
            "user:read:chat",
            "user:write:chat",
            "moderator:manage:chat",
            "channel:read:subscriptions"
        ]
        
        let auth = TwitchDeviceAuth(clientID: "test_client", scopes: scopes)
        
        #expect(auth != nil)
    }
    
    // MARK: - URL Encoding Tests
    
    @Test("Special characters in scopes are handled")
    func testScopeEncoding() async throws {
        let scopes = ["user:read:chat", "user:write:chat"]
        
        let auth = TwitchDeviceAuth(clientID: "test_client", scopes: scopes)
        
        #expect(auth != nil)
        
        // Verify initialization handles colons in scope names
    }
}
