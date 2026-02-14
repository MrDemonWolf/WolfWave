//
//  TwitchViewModelTests.swift
//  WolfWaveTests
//
//  Created by Claude on 2/13/26.
//

import XCTest
@testable import WolfWave

final class TwitchViewModelTests: XCTestCase {
    var viewModel: TwitchViewModel!

    override func setUp() {
        super.setUp()
        viewModel = TwitchViewModel()
    }

    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }

    // MARK: - AuthState Computed Properties

    func testAuthStateIdleNotInProgress() {
        let state = TwitchViewModel.AuthState.idle
        XCTAssertFalse(state.isInProgress)
    }

    func testAuthStateIdleEmptyUserCode() {
        let state = TwitchViewModel.AuthState.idle
        XCTAssertEqual(state.userCode, "")
    }

    func testAuthStateIdleEmptyVerificationURI() {
        let state = TwitchViewModel.AuthState.idle
        XCTAssertEqual(state.verificationURI, "")
    }

    func testAuthStateRequestingCodeIsInProgress() {
        let state = TwitchViewModel.AuthState.requestingCode
        XCTAssertTrue(state.isInProgress)
    }

    func testAuthStateWaitingForAuthIsInProgress() {
        let state = TwitchViewModel.AuthState.waitingForAuth(
            userCode: "ABC123",
            verificationURI: "https://twitch.tv/activate"
        )
        XCTAssertTrue(state.isInProgress)
    }

    func testAuthStateWaitingForAuthUserCode() {
        let state = TwitchViewModel.AuthState.waitingForAuth(
            userCode: "ABC123",
            verificationURI: "https://twitch.tv/activate"
        )
        XCTAssertEqual(state.userCode, "ABC123")
    }

    func testAuthStateWaitingForAuthVerificationURI() {
        let state = TwitchViewModel.AuthState.waitingForAuth(
            userCode: "ABC123",
            verificationURI: "https://twitch.tv/activate"
        )
        XCTAssertEqual(state.verificationURI, "https://twitch.tv/activate")
    }

    func testAuthStateInProgressIsInProgress() {
        let state = TwitchViewModel.AuthState.inProgress
        XCTAssertTrue(state.isInProgress)
    }

    func testAuthStateErrorNotInProgress() {
        let state = TwitchViewModel.AuthState.error("Something went wrong")
        XCTAssertFalse(state.isInProgress)
    }

    // MARK: - IntegrationState Tests

    func testIntegrationStateErrorWhenAuthError() {
        viewModel.authState = .error("Test error")
        if case .error = viewModel.integrationState {
            // Expected
        } else {
            XCTFail("Expected .error integration state")
        }
    }

    func testIntegrationStateConnectedWhenChannelConnected() {
        viewModel.authState = .idle
        viewModel.channelConnected = true
        if case .connected = viewModel.integrationState {
            // Expected
        } else {
            XCTFail("Expected .connected integration state")
        }
    }

    func testIntegrationStateConnectedWhenCredentialsSaved() {
        viewModel.authState = .idle
        viewModel.credentialsSaved = true
        if case .connected = viewModel.integrationState {
            // Expected
        } else {
            XCTFail("Expected .connected integration state")
        }
    }

    func testIntegrationStateAuthorizingWhenRequestingCode() {
        viewModel.authState = .requestingCode
        if case .authorizing = viewModel.integrationState {
            // Expected
        } else {
            XCTFail("Expected .authorizing integration state")
        }
    }

    func testIntegrationStateAuthorizingWhenWaitingForAuth() {
        viewModel.authState = .waitingForAuth(userCode: "X", verificationURI: "Y")
        if case .authorizing = viewModel.integrationState {
            // Expected
        } else {
            XCTFail("Expected .authorizing integration state")
        }
    }

    func testIntegrationStateAuthorizingWhenInProgress() {
        viewModel.authState = .inProgress
        if case .authorizing = viewModel.integrationState {
            // Expected
        } else {
            XCTFail("Expected .authorizing integration state")
        }
    }

    func testIntegrationStateNotConnectedDefault() {
        viewModel.authState = .idle
        viewModel.channelConnected = false
        viewModel.credentialsSaved = false
        if case .notConnected = viewModel.integrationState {
            // Expected
        } else {
            XCTFail("Expected .notConnected integration state")
        }
    }

    // MARK: - Status Chip Text Tests

    func testStatusChipTextReauthNeeded() {
        viewModel.reauthNeeded = true
        XCTAssertEqual(viewModel.statusChipText, "Reauth needed")
    }

    func testStatusChipTextConnected() {
        viewModel.reauthNeeded = false
        viewModel.channelConnected = true
        XCTAssertEqual(viewModel.statusChipText, "Connected")
    }

    func testStatusChipTextSignedIn() {
        viewModel.reauthNeeded = false
        viewModel.channelConnected = false
        viewModel.credentialsSaved = true
        XCTAssertEqual(viewModel.statusChipText, "Signed in")
    }

    func testStatusChipTextNotSignedIn() {
        viewModel.reauthNeeded = false
        viewModel.channelConnected = false
        viewModel.credentialsSaved = false
        XCTAssertEqual(viewModel.statusChipText, "Not signed in")
    }

    // MARK: - Cancel OAuth Tests

    func testCancelOAuthResetsAuthState() {
        viewModel.authState = .requestingCode
        viewModel.statusMessage = "Some status"
        viewModel.cancelOAuth()
        if case .idle = viewModel.authState {
            // Expected
        } else {
            XCTFail("Expected authState to be .idle after cancel")
        }
    }

    func testCancelOAuthClearsStatusMessage() {
        viewModel.statusMessage = "Authorizing..."
        viewModel.cancelOAuth()
        XCTAssertEqual(viewModel.statusMessage, "")
    }

    // MARK: - ChannelValidationState Tests

    func testChannelValidationStateDefaultIsIdle() {
        XCTAssertEqual(viewModel.channelValidationState, .idle)
    }

    func testChannelValidationStateEquatableIdle() {
        XCTAssertEqual(TwitchViewModel.ChannelValidationState.idle, .idle)
    }

    func testChannelValidationStateEquatableError() {
        let state1 = TwitchViewModel.ChannelValidationState.error("test")
        let state2 = TwitchViewModel.ChannelValidationState.error("test")
        XCTAssertEqual(state1, state2)
    }

    func testChannelValidationStateNotEqual() {
        XCTAssertNotEqual(TwitchViewModel.ChannelValidationState.idle, .validating)
    }
}
