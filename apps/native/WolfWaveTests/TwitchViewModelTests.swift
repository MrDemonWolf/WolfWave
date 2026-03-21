//
//  TwitchViewModelTests.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import Testing
import Foundation
import SwiftUI
@testable import WolfWave

/// Comprehensive test suite for TwitchViewModel
@Suite("Twitch ViewModel Tests")
@MainActor
struct TwitchViewModelTests {
    
    // MARK: - Initialization Tests
    
    @Test("ViewModel initializes with default state")
    func testInitialization() async throws {
        let viewModel = TwitchViewModel()
        
        #expect(viewModel.botUsername == "")
        #expect(viewModel.oauthToken == "")
        #expect(viewModel.channelID == "")
        #expect(viewModel.credentialsSaved == false)
        #expect(viewModel.channelConnected == false)
        #expect(viewModel.isConnecting == false)
        #expect(viewModel.reauthNeeded == false)
        #expect(viewModel.statusMessage == "")
        #expect(viewModel.channelValidationState == .idle)
        #expect(viewModel.testAuthResult == .idle)
        #expect(viewModel.authState == .idle)
    }
    
    // MARK: - Auth State Tests
    
    @Test("Auth state isInProgress computed property works")
    func testAuthStateIsInProgress() async throws {
        let viewModel = TwitchViewModel()
        
        // Idle should not be in progress
        viewModel.authState = .idle
        #expect(!viewModel.authState.isInProgress)
        
        // Requesting code should be in progress
        viewModel.authState = .requestingCode
        #expect(viewModel.authState.isInProgress)
        
        // Waiting for auth should be in progress
        viewModel.authState = .waitingForAuth(userCode: "ABC123", verificationURI: "https://twitch.tv/activate")
        #expect(viewModel.authState.isInProgress)
        
        // In progress should be in progress
        viewModel.authState = .inProgress
        #expect(viewModel.authState.isInProgress)
        
        // Error should not be in progress
        viewModel.authState = .error("Test error")
        #expect(!viewModel.authState.isInProgress)
    }
    
    @Test("Auth state userCode extraction works")
    func testAuthStateUserCode() async throws {
        let viewModel = TwitchViewModel()
        
        // No user code when idle
        viewModel.authState = .idle
        #expect(viewModel.authState.userCode == "")
        
        // User code present when waiting
        viewModel.authState = .waitingForAuth(userCode: "ABCD-1234", verificationURI: "https://twitch.tv/activate")
        #expect(viewModel.authState.userCode == "ABCD-1234")
        
        // No user code in error state
        viewModel.authState = .error("Test error")
        #expect(viewModel.authState.userCode == "")
    }
    
    @Test("Auth state verificationURI extraction works")
    func testAuthStateVerificationURI() async throws {
        let viewModel = TwitchViewModel()
        
        // No URI when idle
        viewModel.authState = .idle
        #expect(viewModel.authState.verificationURI == "")
        
        // URI present when waiting
        viewModel.authState = .waitingForAuth(userCode: "ABCD-1234", verificationURI: "https://twitch.tv/activate")
        #expect(viewModel.authState.verificationURI == "https://twitch.tv/activate")
        
        // No URI in error state
        viewModel.authState = .error("Test error")
        #expect(viewModel.authState.verificationURI == "")
    }
    
    // MARK: - Integration State Tests
    
    @Test("Integration state reflects connection status")
    func testIntegrationStateConnected() async throws {
        let viewModel = TwitchViewModel()
        
        // Not connected initially
        switch viewModel.integrationState {
        case .notConnected:
            #expect(true)
        default:
            Issue.record("Expected notConnected state")
        }
        
        // Connected when channel is connected
        viewModel.channelConnected = true
        switch viewModel.integrationState {
        case .connected:
            #expect(true)
        default:
            Issue.record("Expected connected state")
        }
    }
    
    @Test("Integration state reflects auth progress")
    func testIntegrationStateAuthorizing() async throws {
        let viewModel = TwitchViewModel()
        
        // Authorizing when requesting code
        viewModel.authState = .requestingCode
        switch viewModel.integrationState {
        case .authorizing:
            #expect(true)
        default:
            Issue.record("Expected authorizing state")
        }
        
        // Authorizing when waiting for auth
        viewModel.authState = .waitingForAuth(userCode: "ABC", verificationURI: "https://test.com")
        switch viewModel.integrationState {
        case .authorizing:
            #expect(true)
        default:
            Issue.record("Expected authorizing state")
        }
    }
    
    @Test("Integration state reflects errors")
    func testIntegrationStateError() async throws {
        let viewModel = TwitchViewModel()
        
        viewModel.authState = .error("Test error message")
        
        switch viewModel.integrationState {
        case .error(let message):
            #expect(message == "Test error message")
        default:
            Issue.record("Expected error state")
        }
    }
    
    @Test("Integration color matches state")
    func testIntegrationColor() async throws {
        let viewModel = TwitchViewModel()
        
        // Not connected = secondary
        #expect(viewModel.integrationColor == .secondary)
        
        // Authorizing = orange
        viewModel.authState = .requestingCode
        #expect(viewModel.integrationColor == .orange)
        
        // Connected = green
        viewModel.authState = .idle
        viewModel.channelConnected = true
        #expect(viewModel.integrationColor == .green)
        
        // Error = red
        viewModel.channelConnected = false
        viewModel.authState = .error("Test error")
        #expect(viewModel.integrationColor == .red)
    }
    
    // MARK: - Status Chip Tests
    
    @Test("Status chip text reflects state")
    func testStatusChipText() async throws {
        let viewModel = TwitchViewModel()
        
        // Not signed in
        #expect(viewModel.statusChipText == "Not signed in")
        
        // Signed in
        viewModel.credentialsSaved = true
        #expect(viewModel.statusChipText == "Signed in")
        
        // Connected
        viewModel.channelConnected = true
        #expect(viewModel.statusChipText == "Connected")
        
        // Reauth needed (highest priority)
        viewModel.reauthNeeded = true
        #expect(viewModel.statusChipText == "Reauth needed")
    }
    
    @Test("Status chip color reflects state")
    func testStatusChipColor() async throws {
        let viewModel = TwitchViewModel()
        
        // Not signed in = gray
        #expect(viewModel.statusChipColor == Color.gray.opacity(0.55))
        
        // Signed in = blue
        viewModel.credentialsSaved = true
        #expect(viewModel.statusChipColor == .blue)
        
        // Connected = green
        viewModel.channelConnected = true
        #expect(viewModel.statusChipColor == .green)
        
        // Reauth needed = yellow (highest priority)
        viewModel.reauthNeeded = true
        #expect(viewModel.statusChipColor == .yellow)
    }
    
    // MARK: - Channel Validation State Tests
    
    @Test("Channel validation state enum equality works")
    func testChannelValidationStateEquality() async throws {
        #expect(TwitchViewModel.ChannelValidationState.idle == .idle)
        #expect(TwitchViewModel.ChannelValidationState.validating == .validating)
        #expect(TwitchViewModel.ChannelValidationState.valid == .valid)
        #expect(TwitchViewModel.ChannelValidationState.invalid == .invalid)
        #expect(TwitchViewModel.ChannelValidationState.error("msg1") == .error("msg1"))
        #expect(TwitchViewModel.ChannelValidationState.error("msg1") != .error("msg2"))
    }
    
    // MARK: - Test Auth Result Tests
    
    @Test("Test auth result enum equality works")
    func testTestAuthResultEquality() async throws {
        #expect(TwitchViewModel.TestAuthResult.idle == .idle)
        #expect(TwitchViewModel.TestAuthResult.testing == .testing)
        #expect(TwitchViewModel.TestAuthResult.success == .success)
        #expect(TwitchViewModel.TestAuthResult.failure == .failure)
    }
    
    // MARK: - Clear Credentials Tests
    
    @Test("Clear credentials resets all state")
    func testClearCredentials() async throws {
        let viewModel = TwitchViewModel()
        
        // Set some state
        viewModel.botUsername = "testbot"
        viewModel.oauthToken = "test_token"
        viewModel.channelID = "testchannel"
        viewModel.credentialsSaved = true
        viewModel.reauthNeeded = true
        viewModel.statusMessage = "Test status"
        viewModel.authState = .inProgress
        viewModel.channelValidationState = .valid
        
        // Clear credentials
        viewModel.clearCredentials()
        
        // Verify all state is reset
        #expect(viewModel.botUsername == "")
        #expect(viewModel.oauthToken == "")
        #expect(viewModel.channelID == "")
        #expect(viewModel.credentialsSaved == false)
        #expect(viewModel.reauthNeeded == false)
        #expect(viewModel.statusMessage == "")
        #expect(viewModel.authState == .idle)
        #expect(viewModel.channelValidationState == .idle)
    }
    
    // MARK: - Save Credentials Tests
    
    @Test("Save credentials validates empty token")
    func testSaveCredentialsEmptyToken() async throws {
        let viewModel = TwitchViewModel()
        
        viewModel.oauthToken = ""
        viewModel.channelID = "testchannel"
        
        viewModel.saveCredentials()
        
        #expect(viewModel.statusMessage == "❌ No OAuth token to save")
        #expect(viewModel.credentialsSaved == false)
    }
    
    @Test("Save credentials validates empty channel")
    func testSaveCredentialsEmptyChannel() async throws {
        let viewModel = TwitchViewModel()
        
        viewModel.oauthToken = "test_token"
        viewModel.channelID = ""
        
        viewModel.saveCredentials()
        
        #expect(viewModel.statusMessage == "❌ Please enter a channel name")
        #expect(viewModel.credentialsSaved == false)
    }
    
    // MARK: - Cancel OAuth Tests
    
    @Test("Cancel OAuth resets state")
    func testCancelOAuth() async throws {
        let viewModel = TwitchViewModel()
        
        viewModel.authState = .waitingForAuth(userCode: "ABC123", verificationURI: "https://test.com")
        viewModel.statusMessage = "Waiting for auth..."
        
        viewModel.cancelOAuth()
        
        #expect(viewModel.authState == .idle)
        #expect(viewModel.statusMessage == "")
    }
}
