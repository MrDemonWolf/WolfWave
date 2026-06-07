//
//  SongRequestAccessTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

@testable import WolfWave

// MARK: - RequestAudience

@MainActor
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

@MainActor
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

        XCTAssertEqual(
            defaults.string(forKey: AppConstants.UserDefaults.songRequestPolicyMode),
            SongRequestPreset.open.rawValue)
        XCTAssertEqual(defaults.bool(forKey: AppConstants.UserDefaults.srCommandEnabled), true)
        XCTAssertEqual(
            defaults.string(forKey: AppConstants.UserDefaults.songRequestChatAudience),
            RequestAudience.everyone.rawValue)
        // Open opts bits into "boost the cheerer's song" behavior.
        XCTAssertTrue(defaults.bool(forKey: AppConstants.UserDefaults.songRequestBitsBoostEnabled))
    }

    func testApplySubOnlyTargetsSubscribers() {
        SongRequestPreset.subsOnly.apply(to: defaults)
        XCTAssertTrue(defaults.bool(forKey: AppConstants.UserDefaults.srCommandEnabled))
        XCTAssertEqual(
            defaults.string(forKey: AppConstants.UserDefaults.songRequestChatAudience),
            RequestAudience.subscribers.rawValue)
    }

    func testApplyChannelPointsOnlyDisablesChatEnablesReward() {
        SongRequestPreset.channelPointsOnly.apply(to: defaults)
        XCTAssertFalse(defaults.bool(forKey: AppConstants.UserDefaults.srCommandEnabled))
        XCTAssertTrue(
            defaults.bool(forKey: AppConstants.UserDefaults.songRequestChannelPointsEnabled))
    }

    func testCurrentDefaultsToOpenWhenUnset() {
        XCTAssertEqual(SongRequestPreset.current(in: defaults), .open)
    }

    func testCurrentReadsStoredModeForEveryPreset() {
        for preset in SongRequestPreset.allCases {
            preset.apply(to: defaults)
            XCTAssertEqual(
                SongRequestPreset.current(in: defaults), preset,
                "current() should read back \(preset.rawValue) after apply()")
        }
    }

    func testCurrentInfersCustomForElevatedAudienceWithoutStoredMode() {
        // No stored policy mode (pre-upgrade), but an audience only reachable via
        // Custom: current() should resolve to .custom.
        defaults.set(true, forKey: AppConstants.UserDefaults.srCommandEnabled)
        defaults.set(
            RequestAudience.modsOnly.rawValue,
            forKey: AppConstants.UserDefaults.songRequestChatAudience)
        XCTAssertEqual(SongRequestPreset.current(in: defaults), .custom)
    }
}

// MARK: - SongRequestLimits

@MainActor
final class SongRequestLimitsTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SongRequestLimitsTests")
        defaults.removePersistentDomain(forName: "SongRequestLimitsTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "SongRequestLimitsTests")
        defaults = nil
        super.tearDown()
    }

    private func setLimits(everyone: Int, sub: Int, vip: Int, mod: Int) {
        defaults.set(everyone, forKey: AppConstants.UserDefaults.songRequestPerUserLimit)
        defaults.set(sub, forKey: AppConstants.UserDefaults.songRequestLimitSubscriber)
        defaults.set(vip, forKey: AppConstants.UserDefaults.songRequestLimitVIP)
        defaults.set(mod, forKey: AppConstants.UserDefaults.songRequestLimitModerator)
    }

    func testDefaultsToHighestMode() {
        XCTAssertEqual(SongRequestLimits.mode(in: defaults), .highest)
    }

    func testHighestModeTakesBestTier() {
        defaults.set(QueueLimitMode.highest.rawValue, forKey: AppConstants.UserDefaults.songRequestLimitStackMode)
        setLimits(everyone: 2, sub: 3, vip: 5, mod: 10)

        // A plain viewer only gets the everyone tier.
        XCTAssertEqual(
            SongRequestLimits.effectiveLimit(
                isSubscriber: false, isVIP: false, isModerator: false, isBroadcaster: false, in: defaults),
            2)
        // A subscriber gets the larger of everyone/sub.
        XCTAssertEqual(
            SongRequestLimits.effectiveLimit(
                isSubscriber: true, isVIP: false, isModerator: false, isBroadcaster: false, in: defaults),
            3)
        // A sub + VIP gets the best single tier, not the sum.
        XCTAssertEqual(
            SongRequestLimits.effectiveLimit(
                isSubscriber: true, isVIP: true, isModerator: false, isBroadcaster: false, in: defaults),
            5)
        // The broadcaster counts as a moderator.
        XCTAssertEqual(
            SongRequestLimits.effectiveLimit(
                isSubscriber: false, isVIP: false, isModerator: false, isBroadcaster: true, in: defaults),
            10)
    }

    func testStackedModeSumsApplicableTiers() {
        defaults.set(QueueLimitMode.stacked.rawValue, forKey: AppConstants.UserDefaults.songRequestLimitStackMode)
        setLimits(everyone: 2, sub: 3, vip: 5, mod: 10)

        XCTAssertEqual(
            SongRequestLimits.effectiveLimit(
                isSubscriber: false, isVIP: false, isModerator: false, isBroadcaster: false, in: defaults),
            2)
        // everyone + sub
        XCTAssertEqual(
            SongRequestLimits.effectiveLimit(
                isSubscriber: true, isVIP: false, isModerator: false, isBroadcaster: false, in: defaults),
            5)
        // everyone + sub + vip + mod
        XCTAssertEqual(
            SongRequestLimits.effectiveLimit(
                isSubscriber: true, isVIP: true, isModerator: true, isBroadcaster: false, in: defaults),
            20)
    }

    func testNonChatLimitUsesEveryoneTier() {
        setLimits(everyone: 4, sub: 9, vip: 9, mod: 9)
        XCTAssertEqual(SongRequestLimits.nonChatLimit(in: defaults), 4)
    }
}

// MARK: - RedemptionStatus

@MainActor
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
