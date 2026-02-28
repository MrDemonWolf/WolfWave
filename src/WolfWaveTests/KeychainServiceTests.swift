//
//  KeychainServiceTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 2/27/26.
//

import XCTest
@testable import WolfWave

final class KeychainServiceTests: XCTestCase {

    // MARK: - Error Description Tests

    func testSaveFailedErrorDescription() throws {
        let error = KeychainService.KeychainError.saveFailed(-25300)
        let description = try XCTUnwrap(error.errorDescription)
        XCTAssertTrue(description.contains("-25300"))
    }

    func testInvalidDataErrorDescription() throws {
        let error = KeychainService.KeychainError.invalidData
        let description = try XCTUnwrap(error.errorDescription)
        XCTAssertTrue(description.contains("Invalid"))
    }

    func testSaveFailedWithDifferentStatus() {
        let error1 = KeychainService.KeychainError.saveFailed(-25299)
        let error2 = KeychainService.KeychainError.saveFailed(-25300)
        XCTAssertNotEqual(error1.errorDescription, error2.errorDescription)
    }

    // MARK: - Save If Changed Tests

    func testSaveTwitchUsernameIfChangedSavesNew() throws {
        // Clean up any existing value first
        KeychainService.deleteTwitchUsername()

        try KeychainService.saveTwitchUsernameIfChanged("testuser")
        XCTAssertEqual(KeychainService.loadTwitchUsername(), "testuser")

        // Clean up
        KeychainService.deleteTwitchUsername()
    }

    func testSaveTwitchUsernameIfChangedSkipsSameValue() throws {
        KeychainService.deleteTwitchUsername()

        try KeychainService.saveTwitchUsername("testuser")
        // Should not throw even when value is the same
        try KeychainService.saveTwitchUsernameIfChanged("testuser")
        XCTAssertEqual(KeychainService.loadTwitchUsername(), "testuser")

        KeychainService.deleteTwitchUsername()
    }

    func testSaveTwitchUsernameIfChangedUpdatesOnChange() throws {
        KeychainService.deleteTwitchUsername()

        try KeychainService.saveTwitchUsername("olduser")
        try KeychainService.saveTwitchUsernameIfChanged("newuser")
        XCTAssertEqual(KeychainService.loadTwitchUsername(), "newuser")

        KeychainService.deleteTwitchUsername()
    }

    // MARK: - Load Missing Key Tests

    func testLoadMissingKeyReturnsNil() {
        // Use a unique account that definitely doesn't exist
        KeychainService.deleteTwitchChannelID()
        XCTAssertNil(KeychainService.loadTwitchChannelID())
    }

    // MARK: - Delete Tests

    func testDeleteNonexistentKeyDoesNotThrow() {
        // Should succeed silently
        KeychainService.deleteTwitchChannelID()
        KeychainService.deleteTwitchChannelID()
    }
}
