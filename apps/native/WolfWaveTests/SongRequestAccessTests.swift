//
//  SongRequestAccessTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 5/22/26.
//

import XCTest

@testable import WolfWave

// MARK: - RequestAudience

final class RequestAudienceTests: XCTestCase {

    func testEveryonePermitsAnyViewer() {
        XCTAssertTrue(
            RequestAudience.everyone.permits(
                isSubscriber: false, isVIP: false, isModerator: false, isBroadcaster: false))
    }

    func testSubscribersBlocksRegularViewer() {
        XCTAssertFalse(
            RequestAudience.subscribers.permits(
                isSubscriber: false, isVIP: false, isModerator: false, isBroadcaster: false))
    }

    func testSubscribersAllowsSubscriber() {
        XCTAssertTrue(
            RequestAudience.subscribers.permits(
                isSubscriber: true, isVIP: false, isModerator: false, isBroadcaster: false))
    }

    func testSubscribersBlocksVIP() {
        XCTAssertFalse(
            RequestAudience.subscribers.permits(
                isSubscriber: false, isVIP: true, isModerator: false, isBroadcaster: false))
    }

    func testVipsAndSubsAllowsVIPAndSubscriber() {
        let audience = RequestAudience.vipsAndSubs
        XCTAssertTrue(
            audience.permits(
                isSubscriber: false, isVIP: true, isModerator: false, isBroadcaster: false))
        XCTAssertTrue(
            audience.permits(
                isSubscriber: true, isVIP: false, isModerator: false, isBroadcaster: false))
    }

    func testVipsAndSubsBlocksRegularViewer() {
        XCTAssertFalse(
            RequestAudience.vipsAndSubs.permits(
                isSubscriber: false, isVIP: false, isModerator: false, isBroadcaster: false))
    }

    func testModsOnlyBlocksSubscriberAndVIP() {
        XCTAssertFalse(
            RequestAudience.modsOnly.permits(
                isSubscriber: true, isVIP: true, isModerator: false, isBroadcaster: false))
    }

    func testModeratorAlwaysPermittedRegardlessOfAudience() {
        for audience in RequestAudience.allCases {
            XCTAssertTrue(
                audience.permits(
                    isSubscriber: false, isVIP: false, isModerator: true, isBroadcaster: false),
                "Moderator should bypass \(audience.rawValue)")
        }
    }

    func testBroadcasterAlwaysPermittedRegardlessOfAudience() {
        for audience in RequestAudience.allCases {
            XCTAssertTrue(
                audience.permits(
                    isSubscriber: false, isVIP: false, isModerator: false, isBroadcaster: true),
                "Broadcaster should bypass \(audience.rawValue)")
        }
    }

    func testRawValueRoundTrips() {
        for audience in RequestAudience.allCases {
            XCTAssertEqual(RequestAudience(rawValue: audience.rawValue), audience)
        }
    }
}

// MARK: - SongRequestPreset

final class SongRequestPresetTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SongRequestPresetTests")
        defaults.removePersistentDomain(forName: "SongRequestPresetTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "SongRequestPresetTests")
        defaults = nil
        super.tearDown()
    }

    func testApplyOpenPresetWritesExpectedKeys() {
        SongRequestPreset.open.apply(to: defaults)

        XCTAssertEqual(defaults.bool(forKey: AppConstants.UserDefaults.srCommandEnabled), true)
        XCTAssertEqual(
            defaults.string(forKey: AppConstants.UserDefaults.songRequestChatAudience),
            RequestAudience.everyone.rawValue)
        XCTAssertTrue(
            defaults.bool(forKey: AppConstants.UserDefaults.songRequestChannelPointsEnabled))
        XCTAssertTrue(defaults.bool(forKey: AppConstants.UserDefaults.songRequestBitsEnabled))
    }

    func testApplyPaidOnlyDisablesChatCommand() {
        SongRequestPreset.paidOnly.apply(to: defaults)
        XCTAssertFalse(defaults.bool(forKey: AppConstants.UserDefaults.srCommandEnabled))
        XCTAssertTrue(
            defaults.bool(forKey: AppConstants.UserDefaults.songRequestChannelPointsEnabled))
    }

    func testApplySubsStrictDisablesRedemptions() {
        SongRequestPreset.subsStrict.apply(to: defaults)
        XCTAssertEqual(
            defaults.string(forKey: AppConstants.UserDefaults.songRequestChatAudience),
            RequestAudience.subscribers.rawValue)
        XCTAssertFalse(
            defaults.bool(forKey: AppConstants.UserDefaults.songRequestChannelPointsEnabled))
        XCTAssertFalse(defaults.bool(forKey: AppConstants.UserDefaults.songRequestBitsEnabled))
    }

    func testCurrentDetectsAppliedPreset() {
        for preset in SongRequestPreset.allCases {
            preset.apply(to: defaults)
            XCTAssertEqual(
                SongRequestPreset.current(in: defaults), preset,
                "current() should detect \(preset.rawValue) after apply()")
        }
    }

    func testCurrentReturnsNilForCustomConfiguration() {
        SongRequestPreset.open.apply(to: defaults)
        // Diverge from every preset: open audience but redemptions off.
        defaults.set(false, forKey: AppConstants.UserDefaults.songRequestChannelPointsEnabled)
        defaults.set(false, forKey: AppConstants.UserDefaults.songRequestBitsEnabled)
        XCTAssertNil(SongRequestPreset.current(in: defaults))
    }
}

// MARK: - RedemptionStatus

final class RedemptionStatusTests: XCTestCase {

    func testOkHasNoBanner() {
        XCTAssertNil(RedemptionStatus.ok.bannerMessage)
    }

    func testProblemStatusesHaveBanner() {
        XCTAssertNotNil(RedemptionStatus.scopeMissing.bannerMessage)
        XCTAssertNotNil(RedemptionStatus.botAccount.bannerMessage)
        XCTAssertNotNil(RedemptionStatus.subscribeFailed.bannerMessage)
    }

    func testRawValueRoundTrips() {
        XCTAssertEqual(RedemptionStatus(rawValue: "ok"), .ok)
        XCTAssertEqual(RedemptionStatus(rawValue: "botAccount"), .botAccount)
    }
}
