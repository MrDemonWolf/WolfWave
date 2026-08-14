//
//  UserFacingErrorTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-14.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

final class UserFacingErrorTests: XCTestCase {

    // MARK: - Message Composition

    func testMessageJoinsCauseAndFix() {
        let error = UserFacingError(
            id: "twitch.signInExpired",
            title: "Twitch sign-in expired",
            cause: "Twitch rejected the saved sign-in.",
            fix: "Reconnect and WolfWave picks up where it left off."
        )
        XCTAssertEqual(
            error.message,
            "Twitch rejected the saved sign-in. Reconnect and WolfWave picks up where it left off."
        )
    }

    func testMessageOmitsMissingParts() {
        let causeOnly = UserFacingError(id: "a", title: "T", cause: "Because.")
        let fixOnly = UserFacingError(id: "b", title: "T", fix: "Do this.")
        let neither = UserFacingError(id: "c", title: "T")

        XCTAssertEqual(causeOnly.message, "Because.")
        XCTAssertEqual(fixOnly.message, "Do this.")
        XCTAssertEqual(neither.message, "")
    }

    // MARK: - Accessibility

    /// The originating bug put the real reason in a `.help()` tooltip, which
    /// VoiceOver reached only by accident. The spoken label must carry it.
    func testAccessibilityLabelCarriesTheRealReason() {
        let error = UserFacingError(
            id: "twitch.rateLimited",
            title: "Your sign-in is fine, we're being rate limited",
            cause: "Twitch is throttling requests.",
            severity: .warning
        )
        XCTAssertEqual(
            error.accessibilityLabel,
            "Your sign-in is fine, we're being rate limited. Twitch is throttling requests."
        )
    }

    func testAccessibilityLabelFallsBackToTitle() {
        let error = UserFacingError(id: "x", title: "Something broke")
        XCTAssertEqual(error.accessibilityLabel, "Something broke")
    }

    /// Every rendered state gets an identifier derived from `id`, so a state
    /// with no render path fails its test instead of passing invisibly.
    func testAccessibilityIdentifierIsDerivedFromID() {
        let error = UserFacingError(id: "music.automationDenied", title: "T")
        XCTAssertEqual(error.accessibilityIdentifier, "errorCallout.music.automationDenied")
    }

    // MARK: - Action Ordering

    func testPrimaryActionIsFirstAndSecondariesFollow() {
        let error = UserFacingError(
            id: "twitch.keychainWriteFailed",
            title: "Couldn't save your Twitch sign-in",
            actions: [.retry, .reportBug, .openDocs(anchor: "keychain")]
        )
        XCTAssertEqual(error.primaryAction, .retry)
        XCTAssertEqual(error.secondaryActions, [.reportBug, .openDocs(anchor: "keychain")])
    }

    func testNoActionsYieldsNoPrimary() {
        let error = UserFacingError(id: "x", title: "T")
        XCTAssertNil(error.primaryAction)
        XCTAssertTrue(error.secondaryActions.isEmpty)
    }

    // MARK: - ErrorAction

    /// macOS uses title-style capitalization for controls, and the app already
    /// ships "Check Again" / "Open System Settings" / "Set Up Song Requests".
    /// A lowercased word here would read as a web button, not a Mac one.
    func testActionLabelsUseTitleCase() {
        let labels: [String] = [
            ErrorAction.reconnectTwitch.label,
            ErrorAction.signInAsBroadcaster.label,
            ErrorAction.retry.label,
            ErrorAction.openAutomationSettings.label,
            ErrorAction.openLoginItems.label,
            ErrorAction.openSongRequestSetup(step: nil).label,
            ErrorAction.checkForUpdates.label,
            ErrorAction.chooseAnotherFile.label,
            ErrorAction.openDocs(anchor: "a").label,
            ErrorAction.reportBug.label
        ]

        // Words that stay lowercase in title case.
        let minorWords: Set<String> = ["a", "an", "and", "as", "at", "for", "in", "of", "on", "or", "the", "to", "with"]

        for label in labels {
            let words = label.split(separator: " ").map(String.init)
            XCTAssertFalse(words.isEmpty, "Label should not be empty")
            for (index, word) in words.enumerated() {
                let bare = word.trimmingCharacters(in: CharacterSet.letters.inverted)
                guard let first = bare.first, first.isLetter else { continue }
                if index > 0 && minorWords.contains(bare.lowercased()) { continue }
                XCTAssertTrue(
                    first.isUppercase,
                    "\"\(label)\" should use title case, but \"\(word)\" is lowercase"
                )
            }
        }
    }

    func testRetryAfterCarriesTheDelayInLabelAndID() {
        let action = ErrorAction.retryAfter(seconds: 30)
        XCTAssertEqual(action.label, "Try Again in 30s")
        XCTAssertEqual(action.id, "retryAfter.30")
        XCTAssertTrue(action.isWaiting)
    }

    func testOnlyRetryAfterIsWaiting() {
        XCTAssertFalse(ErrorAction.retry.isWaiting)
        XCTAssertFalse(ErrorAction.reconnectTwitch.isWaiting)
        XCTAssertFalse(ErrorAction.reportBug.isWaiting)
    }

    func testActionIDsAreUniqueAcrossCases() {
        let actions: [ErrorAction] = [
            .reconnectTwitch, .signInAsBroadcaster, .retry, .retryAfter(seconds: 5),
            .openAutomationSettings, .openLoginItems, .openNotificationSettings,
            .openSongRequestSetup(step: nil), .openSongRequestSetup(step: 2),
            .checkForUpdates, .chooseAnotherFile, .openDocs(anchor: "twitch"), .reportBug
        ]
        XCTAssertEqual(Set(actions.map(\.id)).count, actions.count)
    }

    func testReportBugKeepsItsEllipsis() {
        XCTAssertTrue(ErrorAction.reportBug.label.hasSuffix("\u{2026}"))
    }

    // MARK: - Sendable Boundary

    /// The model is built off the main actor in services and read on it in
    /// views, so it has to cross without a copy-out.
    func testCrossesActorBoundaries() async {
        let error = UserFacingError(
            id: "twitch.offline",
            title: "You're offline",
            fix: "Check your internet, then try again.",
            severity: .warning,
            actions: [.retry]
        )
        let received = await Task.detached { error }.value
        XCTAssertEqual(received, error)
    }
}
