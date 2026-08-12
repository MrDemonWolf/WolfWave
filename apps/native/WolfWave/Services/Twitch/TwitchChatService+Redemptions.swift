//
//  TwitchChatService+Redemptions.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-07-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Process-local lifecycle fence for reward setup and unpersisted redemption
/// containment. Disk remains authoritative for persisted work; this gate only
/// supplies the bounded ordering that UserDefaults and task dictionaries cannot.
nonisolated enum TwitchRedemptionTeardownGate {
    struct SetupLease: @unchecked Sendable {
        let id: UUID
        fileprivate let owner: Owner
        fileprivate let generation: UInt64
    }

    fileprivate struct Owner: Hashable {
        let serviceID: ObjectIdentifier
        let broadcasterID: String
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var setups: [UUID: SetupLease] = [:]
    private nonisolated(unsafe) static var teardownGenerations: [Owner: UInt64] = [:]
    private nonisolated(unsafe) static var containments: [UUID: Owner] = [:]

    static func beginSetup(
        serviceID: ObjectIdentifier,
        broadcasterID: String,
        generation: UInt64
    ) -> SetupLease? {
        lock.withLock {
            let owner = Owner(
                serviceID: serviceID,
                broadcasterID: broadcasterID)
            if let teardownGeneration = teardownGenerations[owner] {
                guard generation > teardownGeneration else { return nil }
                teardownGenerations[owner] = nil
            }
            let lease = SetupLease(
                id: UUID(),
                owner: owner,
                generation: generation)
            setups[lease.id] = lease
            return lease
        }
    }

    static func endSetup(_ lease: SetupLease) {
        lock.withLock {
            guard setups[lease.id]?.generation == lease.generation else {
                return
            }
            setups[lease.id] = nil
        }
    }

    static func beginTeardown(
        serviceID: ObjectIdentifier,
        broadcasterID: String,
        generation: UInt64
    ) -> Bool {
        lock.withLock {
            let owner = Owner(
                serviceID: serviceID,
                broadcasterID: broadcasterID)
            if let existing = teardownGenerations[owner],
               existing > generation {
                return false
            }
            teardownGenerations[owner] = generation
            return true
        }
    }

    static func teardownIsCurrent(
        serviceID: ObjectIdentifier,
        broadcasterID: String,
        generation: UInt64
    ) -> Bool {
        lock.withLock {
            teardownGenerations[
                Owner(
                    serviceID: serviceID,
                    broadcasterID: broadcasterID)
            ] == generation
        }
    }

    static func cancelTeardown(
        serviceID: ObjectIdentifier,
        broadcasterID: String,
        generation: UInt64
    ) {
        lock.withLock {
            let owner = Owner(
                serviceID: serviceID,
                broadcasterID: broadcasterID)
            guard teardownGenerations[owner] == generation else { return }
            teardownGenerations[owner] = nil
        }
    }

    static func hasActiveSetup(
        serviceID: ObjectIdentifier,
        broadcasterID: String,
        through generation: UInt64
    ) -> Bool {
        lock.withLock {
            setups.values.contains {
                $0.owner.serviceID == serviceID
                    && $0.owner.broadcasterID == broadcasterID
                    && $0.generation <= generation
            }
        }
    }

    static func beginContainment(
        id: UUID,
        serviceID: ObjectIdentifier,
        broadcasterID: String
    ) {
        lock.withLock {
            containments[id] = Owner(
                serviceID: serviceID,
                broadcasterID: broadcasterID)
        }
    }

    static func endContainment(id: UUID) {
        lock.withLock {
            containments[id] = nil
        }
    }

    static func removeService(serviceID: ObjectIdentifier) {
        lock.withLock {
            setups = setups.filter {
                $0.value.owner.serviceID != serviceID
            }
            teardownGenerations = teardownGenerations.filter {
                $0.key.serviceID != serviceID
            }
            containments = containments.filter {
                $0.value.serviceID != serviceID
            }
        }
    }

    static func hasContainment(
        serviceID: ObjectIdentifier,
        broadcasterID: String
    ) -> Bool {
        lock.withLock {
            containments.values.contains {
                $0.serviceID == serviceID
                    && $0.broadcasterID == broadcasterID
            }
        }
    }
}

extension TwitchChatService {

    // MARK: - Redemption EventSub Subscriptions

    /// Subscribes to channel-point and/or bit EventSub events when the matching
    /// song-request features are enabled. Channel-point and bit subscriptions
    /// require the signed-in account to be the broadcaster. When a separate bot
    /// account is in use they are skipped and the UI is notified.
    func subscribeToRedemptionsIfEnabled(
        receiveContext: EventSubReceiveContext? = nil
    ) async {
        guard receiveContextIsCurrent(receiveContext) else { return }
        let defaults = UserDefaults.standard

        // Channel-point and bit toggles are independent of the master switch, so
        // skip every redemption subscription while the feature as a whole is off.
        // Pause the managed reward first so it can't be redeemed at the source.
        guard defaults.bool(forKey: AppConstants.UserDefaults.songRequestEnabled) else {
            await pauseManagedRewardIfPossible(receiveContext: receiveContext)
            guard receiveContextIsCurrent(receiveContext) else { return }
            setRedemptionStatus(.ok)
            return
        }

        let channelPointsEnabled = defaults.bool(
            forKey: AppConstants.UserDefaults.songRequestChannelPointsEnabled)
        let bitsEnabled = defaults.bool(forKey: AppConstants.UserDefaults.songRequestBitsEnabled)

        // Channel points off but a reward may still exist on the channel: pause it
        // so viewers can't spend points on a request WolfWave would only refund.
        if !channelPointsEnabled {
            await pauseManagedRewardIfPossible(receiveContext: receiveContext)
            guard receiveContextIsCurrent(receiveContext) else { return }
        }

        guard channelPointsEnabled || bitsEnabled else {
            setRedemptionStatus(.ok)
            return
        }

        // Channel-point and bit EventSub require the broadcaster's own token.
        guard let broadcasterID, let botID, broadcasterID == botID else {
            Log.warn(
                "TwitchChatService: Redemption events need the broadcaster account, skipping",
                category: "Twitch")
            setRedemptionStatus(.botAccount)
            return
        }

        var intakeStorageAvailable = true
        if channelPointsEnabled {
            do {
                try redemptionResolutionOutbox.verifyIntakeStorage()
            } catch {
                intakeStorageAvailable = false
                setRedemptionStatus(.storageUnavailable)
                Log.error(
                    "TwitchChatService: Channel-point reward held because redemption "
                        + "storage is unavailable - \(error.localizedDescription)",
                    category: "Twitch")
                await pauseManagedRewardIfPossible(receiveContext: receiveContext)
                guard receiveContextIsCurrent(receiveContext) else { return }
            }
        }

        if intakeStorageAvailable {
            setRedemptionStatus(.ok)
        }

        if channelPointsEnabled, intakeStorageAvailable {
            await ensureSongRequestRewardAndSubscribe(receiveContext: receiveContext)
            guard receiveContextIsCurrent(receiveContext) else { return }
        }
        if bitsEnabled {
            await subscribeToBitsUse(receiveContext: receiveContext)
            guard receiveContextIsCurrent(receiveContext) else { return }
        }
        if channelPointsEnabled,
           intakeStorageAvailable,
           await holdManagedRewardIfIntakeStorageUnavailable(receiveContext: receiveContext) {
            return
        }

        // A bits-subscription failure may set its own shared redemption status.
        // The unsafe channel-point intake state is the more urgent condition and
        // must stay visible until a later storage probe succeeds.
        if !intakeStorageAvailable {
            setRedemptionStatus(.storageUnavailable)
        }
    }

    /// Re-evaluates redemption subscriptions against the current settings.
    /// Called by the settings UI after the streamer changes a redemption toggle.
    func refreshRedemptionSubscriptions() async {
        guard isConnected, let webSocketTask else { return }
        let receiveContext = EventSubReceiveContext(
            generation: connectionGeneration,
            webSocketTask: webSocketTask
        )
        await subscribeToRedemptionsIfEnabled(receiveContext: receiveContext)
    }

    /// Ensures the WolfWave channel-point reward exists, syncs its cost, and
    /// subscribes to its redemption events.
    private func ensureSongRequestRewardAndSubscribe(
        receiveContext: EventSubReceiveContext? = nil
    ) async {
        guard receiveContextIsCurrent(receiveContext) else { return }
        guard let credentials = currentChannelPointCredentials() else { return }
        let setupGeneration = channelOwnershipGeneration
        guard let setupLease = TwitchRedemptionTeardownGate.beginSetup(
            serviceID: ObjectIdentifier(self),
            broadcasterID: credentials.broadcasterID,
            generation: setupGeneration
        ) else {
            return
        }
        defer { TwitchRedemptionTeardownGate.endSetup(setupLease) }

        guard await pauseStoredManagedRewardForReconciliation(
            credentials: credentials,
            receiveContext: receiveContext
        ) else {
            guard receiveContextIsCurrent(receiveContext) else { return }
            guard channelPointCredentialsAreCurrent(credentials) else { return }
            setRedemptionStatus(.subscribeFailed)
            return
        }
        guard receiveContextIsCurrent(receiveContext) else { return }
        guard channelPointCredentialsAreCurrent(credentials) else { return }

        let cost = channelPointsCostSetting()
        do {
            guard let prepared = try await prepareManagedRewardForSubscription(
                credentials: credentials,
                cost: cost,
                receiveContext: receiveContext
            ) else { return }
            try await activateManagedRewardSubscription(
                credentials: prepared.credentials,
                rewardID: prepared.rewardID,
                receiveContext: receiveContext)
        } catch {
            guard receiveContextIsCurrent(receiveContext) else { return }
            guard channelPointCredentialsAreCurrent(credentials) else { return }
            if await holdManagedRewardIfIntakeStorageUnavailable(
                receiveContext: receiveContext) { return }
            Log.error(
                "TwitchChatService: Failed to set up channel-point reward - \(error.localizedDescription)",
                category: "Twitch")
            setRedemptionStatus(.subscribeFailed)
        }
    }

    private func prepareManagedRewardForSubscription(
        credentials: TwitchChannelPointsService.Credentials,
        cost: Int,
        receiveContext: EventSubReceiveContext?
    ) async throws -> (
        credentials: TwitchChannelPointsService.Credentials,
        rewardID: String
    )? {
        let rewardID = try await channelPointsService.ensureReward(
            credentials: credentials,
            cost: cost)
        guard receiveContextIsCurrent(receiveContext),
              channelPointCredentialsAreCurrent(
                credentials,
                rewardID: rewardID) else { return nil }

        // Every fresh session starts from a held reward. EventSub reconnects do
        // not replay notifications missed while disconnected, so reconcile
        // pending Helix state before live intake.
        try await channelPointsService.setRewardPaused(
            credentials: credentials,
            rewardID: rewardID,
            paused: true)
        guard receiveContextIsCurrent(receiveContext),
              channelPointCredentialsAreCurrent(
                credentials,
                rewardID: rewardID) else { return nil }
        if await holdManagedRewardIfIntakeStorageUnavailable(
            receiveContext: receiveContext) { return nil }

        guard let reconciledCredentials = await reconcileManagedRewardRedemptions(
            credentials: credentials,
            rewardID: rewardID,
            receiveContext: receiveContext
        ) else { return nil }
        guard receiveContextIsCurrent(receiveContext),
              channelPointCredentialsAreCurrent(
                reconciledCredentials,
                rewardID: rewardID) else { return nil }

        do {
            try await channelPointsService.updateRewardCost(
                credentials: reconciledCredentials,
                rewardID: rewardID,
                cost: cost)
            guard receiveContextIsCurrent(receiveContext) else { return nil }
        } catch {
            guard receiveContextIsCurrent(receiveContext) else { return nil }
            Log.warn(
                "TwitchChatService: Couldn't sync channel-point reward cost; "
                    + "the reward still works at its current cost - "
                    + error.localizedDescription,
                category: "Twitch")
        }
        guard channelPointCredentialsAreCurrent(
            reconciledCredentials,
            rewardID: rewardID) else { return nil }
        if await holdManagedRewardIfIntakeStorageUnavailable(
            receiveContext: receiveContext) { return nil }
        return (reconciledCredentials, rewardID)
    }

    private func activateManagedRewardSubscription(
        credentials: TwitchChannelPointsService.Credentials,
        rewardID: String,
        receiveContext: EventSubReceiveContext?
    ) async throws {
        let subscribed = await subscribeToChannelPointsRedemption(
            receiveContext: receiveContext)
        guard receiveContextIsCurrent(receiveContext),
              channelPointCredentialsAreCurrent(
                credentials,
                rewardID: rewardID) else { return }
        guard subscribed else {
            setRedemptionStatus(.subscribeFailed)
            return
        }
        if await holdManagedRewardIfIntakeStorageUnavailable(
            receiveContext: receiveContext) { return }
        guard channelPointCredentialsAreCurrent(
            credentials,
            rewardID: rewardID) else { return }

        try await channelPointsService.setRewardPaused(
            credentials: credentials,
            rewardID: rewardID,
            paused: false)
        guard receiveContextIsCurrent(receiveContext),
              channelPointCredentialsAreCurrent(
                credentials,
                rewardID: rewardID) else { return }
        if await holdManagedRewardIfIntakeStorageUnavailable(
            receiveContext: receiveContext) { return }
        setRedemptionStatus(.ok)
    }

    /// Best-effort closes the gap before `ensureReward` resolves the canonical
    /// managed reward ID. A missing stale ID is safe to continue because the
    /// resolved reward is held again before reconciliation starts.
    private func pauseStoredManagedRewardForReconciliation(
        credentials: TwitchChannelPointsService.Credentials,
        receiveContext: EventSubReceiveContext?
    ) async -> Bool {
        do {
            guard let identity = try await channelPointsService
                .managedRewardIdentity(credentials: credentials) else {
                return true
            }
            do {
                try await channelPointsService.setRewardPaused(
                    credentials: credentials,
                    rewardID: identity.rewardID,
                    paused: true)
            } catch let TwitchChannelPointsService.RewardError.http(status, _)
                where status == 404 {
                guard receiveContextIsCurrent(receiveContext),
                      channelPointCredentialsAreCurrent(
                        credentials,
                        rewardID: identity.rewardID),
                      TwitchManagedRewardStore.matches(identity) else {
                    return false
                }
                guard await settleRedemptionWorkBeforeCredentialTeardown(
                    broadcasterID: identity.broadcasterID) else {
                    return false
                }
                return TwitchManagedRewardStore.remove(matching: identity)
            }
            return receiveContextIsCurrent(receiveContext)
                && channelPointCredentialsAreCurrent(
                    credentials,
                    rewardID: identity.rewardID)
        } catch {
            guard receiveContextIsCurrent(receiveContext) else { return false }
            Log.error(
                "TwitchChatService: Could not hold stored channel-point reward before recovery - "
                    + error.localizedDescription,
                category: "Twitch")
            return false
        }
    }

    /// Fetches, persists, and drains every unresolved managed redemption before
    /// the fresh EventSub session may subscribe or make the reward redeemable.
    /// Existing outbox items are included so duplicate Helix results remain
    /// idempotent and prior crash recovery completes under the same hold.
    private func reconcileManagedRewardRedemptions(
        credentials: TwitchChannelPointsService.Credentials,
        rewardID: String,
        receiveContext: EventSubReceiveContext?
    ) async -> TwitchChannelPointsService.Credentials? {
        guard let redemptionIDs = await fetchUnfulfilledRedemptionsForRecovery(
            credentials: credentials,
            rewardID: rewardID,
            receiveContext: receiveContext
        ) else { return nil }
        guard receiveContextIsCurrent(receiveContext),
              channelPointCredentialsAreCurrent(
                credentials,
                rewardID: rewardID
              ) else { return nil }

        do {
            for redemptionID in redemptionIDs {
                _ = try redemptionResolutionOutbox.enqueueIntake(
                    broadcasterID: credentials.broadcasterID,
                    rewardID: rewardID,
                    redemptionID: redemptionID)
            }
        } catch {
            setRedemptionStatus(.storageUnavailable)
            Log.error(
                "TwitchChatService: Could not persist missed redemption recovery - "
                    + error.localizedDescription,
                category: "Twitch")
            return nil
        }

        let recoveryItems = redemptionResolutionOutbox.pendingItems().filter {
            $0.broadcasterID == credentials.broadcasterID
                && $0.rewardID == rewardID
        }
        let recoveryItemIDs = Set(recoveryItems.map(\.id))
        if !recoveryItemIDs.isEmpty {
            replayPendingRedemptionResolutions()
            let workers = recoveryItemIDs.compactMap {
                redemptionResolutionTasks[$0]
            }
            for worker in workers {
                await worker.value
            }
        }

        guard receiveContextIsCurrent(receiveContext),
              channelPointCredentialsAreCurrent(
                credentials,
                rewardID: rewardID
              ) else { return nil }
        let recoveryIncomplete = redemptionResolutionOutbox.pendingItems().contains {
            recoveryItemIDs.contains($0.id)
        }
        guard !recoveryIncomplete else {
            if redemptionResolutionOutbox.intakeStorageIsUnavailable() {
                setRedemptionStatus(.storageUnavailable)
            } else {
                setRedemptionStatus(.subscribeFailed)
            }
            Log.error(
                "TwitchChatService: Managed redemption recovery remains incomplete; keeping reward paused",
                category: "Twitch")
            return nil
        }
        guard !redemptionResolutionOutbox.intakeStorageIsUnavailable() else {
            setRedemptionStatus(.storageUnavailable)
            return nil
        }
        if redemptionResolutionOutbox.hasOpaqueRecoveryRisk() {
            do {
                try redemptionResolutionOutbox
                    .clearOpaqueRecoveryRiskAfterReconciliation()
            } catch {
                setRedemptionStatus(.storageUnavailable)
                Log.error(
                    "TwitchChatService: Held redemption recovery could not clear quarantined data - "
                        + error.localizedDescription,
                    category: "Twitch")
                return nil
            }
        }
        return credentials
    }

    /// Applies the same expectation-bound 401 handling as other live Twitch
    /// requests. A refresh starts a fresh socket instead of continuing recovery
    /// on a session authenticated with the rejected token.
    private func fetchUnfulfilledRedemptionsForRecovery(
        credentials: TwitchChannelPointsService.Credentials,
        rewardID: String,
        receiveContext: EventSubReceiveContext?
    ) async -> [String]? {
        let expectedCredential = TwitchCredentialStore.shared
            .connectionSnapshot(matchingAccessToken: credentials.token)?
            .accessExpectation
        do {
            return try await channelPointsService.unfulfilledRedemptionIDs(
                credentials: credentials,
                rewardID: rewardID)
        } catch let TwitchChannelPointsService.RewardError.http(status, _)
            where status == 401 {
            guard receiveContextIsCurrent(receiveContext),
                  let expectedCredential else { return nil }
            let generation = receiveContext?.generation ?? connectionGeneration
            let recovery = await recoverRejectedAccessToken(
                expectedCredential,
                clientID: credentials.clientID,
                generation: generation,
                broadcasterID: credentials.broadcasterID)
            guard receiveContextIsCurrent(receiveContext) else { return nil }
            switch recovery {
            case .refreshed?:
                disconnectFromEventSub()
                if isNetworkReachable { scheduleReconnect() }
            case .invalid?:
                signalReauthNeededAndStop()
            case .temporarilyUnavailable?:
                disconnectFromEventSub()
                if isNetworkReachable { scheduleReconnect() }
            case .superseded?, nil:
                break
            }
            return nil
        } catch {
            guard receiveContextIsCurrent(receiveContext) else { return nil }
            guard channelPointCredentialsAreCurrent(
                credentials,
                rewardID: rewardID
            ) else { return nil }
            Log.error(
                "TwitchChatService: Could not reconcile unfulfilled channel-point redemptions - "
                    + error.localizedDescription,
                category: "Twitch")
            setRedemptionStatus(.subscribeFailed)
            return nil
        }
    }

    /// Revalidates every identity component after a setup suspension. The
    /// stored reward ID is part of the guard so a concurrent recreation cannot
    /// authorize recovery or unpause against the wrong reward.
    private func channelPointCredentialsAreCurrent(
        _ credentials: TwitchChannelPointsService.Credentials,
        rewardID: String
    ) -> Bool {
        let identity = TwitchManagedRewardStore.Identity(
            rewardID: rewardID,
            broadcasterID: credentials.broadcasterID)
        return channelPointCredentialsAreCurrent(credentials)
            && TwitchManagedRewardStore.matches(identity)
    }

    /// Revalidates the account independently of reward storage, for failures
    /// that occur before `ensureReward` has resolved a canonical reward ID.
    private func channelPointCredentialsAreCurrent(
        _ credentials: TwitchChannelPointsService.Credentials
    ) -> Bool {
        return !Task.isCancelled
            && broadcasterID == credentials.broadcasterID
            && botID == credentials.broadcasterID
            && oauthToken == credentials.token
            && clientID == credentials.clientID
    }

    /// Returns credentials only when the live actor and atomic Keychain grant
    /// agree with the expected managed-reward owner.
    private func managedRewardTeardownCredentials(
        expectedBroadcasterID: String?
    ) -> TwitchChannelPointsService.Credentials? {
        if let currentCredentials = currentChannelPointCredentials(),
           botID == currentCredentials.broadcasterID,
           expectedBroadcasterID == nil
                || expectedBroadcasterID == currentCredentials.broadcasterID {
            return currentCredentials
        }

        guard let snapshot = TwitchCredentialStore.shared.accessSnapshot(),
              let resolvedClientID = clientID ?? reconnectClientID
                ?? redemptionClientIDProvider(),
              !resolvedClientID.isEmpty,
              expectedBroadcasterID == nil
                || expectedBroadcasterID == snapshot.userID else {
            return nil
        }
        let actorBroadcasterID = broadcasterID.flatMap { $0.isEmpty ? nil : $0 }
        let actorBotID = botID.flatMap { $0.isEmpty ? nil : $0 }
        guard actorBroadcasterID == nil || actorBroadcasterID == snapshot.userID,
              actorBotID == nil || actorBotID == snapshot.userID else {
            return nil
        }
        return TwitchChannelPointsService.Credentials(
            broadcasterID: snapshot.userID,
            token: snapshot.accessToken,
            clientID: resolvedClientID)
    }

    /// Re-probes transient write failures but never treats opaque quarantined
    /// bytes as an empty queue during the last credential teardown boundary.
    private func redemptionStorageIsSafeForCredentialTeardown() -> Bool {
        do {
            try redemptionResolutionOutbox.verifyIntakeStorage()
        } catch {
            Log.error(
                "TwitchChatService: Refusing credential teardown because redemption storage cannot be verified - "
                    + error.localizedDescription,
                category: "Twitch")
            return false
        }
        guard !redemptionResolutionOutbox.hasOpaqueRecoveryRisk() else {
            Log.error(
                "TwitchChatService: Refusing credential teardown while quarantined redemption recovery data remains",
                category: "Twitch")
            return false
        }
        return true
    }

    /// Waits for setup work from this ownership generation to finish so its
    /// create or unpause response cannot land after teardown's final pause.
    private func awaitManagedRewardSetupsBeforeCredentialTeardown(
        broadcasterID: String,
        generation: UInt64,
        timeout: Duration = .seconds(5)
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while TwitchRedemptionTeardownGate.hasActiveSetup(
            serviceID: ObjectIdentifier(self),
            broadcasterID: broadcasterID,
            through: generation
        ) {
            guard clock.now < deadline else {
                Log.error(
                    "TwitchChatService: Timed out waiting for managed reward setup before credential teardown",
                    category: "Twitch")
                return false
            }
            do {
                try await Task.sleep(for: .milliseconds(25))
            } catch {
                return false
            }
        }
        return TwitchRedemptionTeardownGate.teardownIsCurrent(
            serviceID: ObjectIdentifier(self),
            broadcasterID: broadcasterID,
            generation: generation)
            && channelOwnershipGeneration == generation
    }

    /// Waits for live intake to record an outcome, then replays and drains the
    /// durable work for one broadcaster. Polling task ownership keeps this
    /// boundary bounded even when a network worker is sleeping or wedged.
    func settleRedemptionWorkBeforeCredentialTeardown(
        broadcasterID: String,
        timeout: Duration = .seconds(5)
    ) async -> Bool {
        guard !broadcasterID.isEmpty else { return false }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        replayPendingBitsEvents()

        while true {
            let pendingItems = redemptionResolutionOutbox.pendingItems().filter {
                $0.broadcasterID == broadcasterID
            }
            let pendingBits = redemptionResolutionOutbox.pendingBitsItems(
                broadcasterID: broadcasterID)
            let volatileBits = pendingVolatileBitsFallbackItems(
                broadcasterID: broadcasterID)
            let hasContainment = TwitchRedemptionTeardownGate.hasContainment(
                serviceID: ObjectIdentifier(self),
                broadcasterID: broadcasterID)
            if pendingItems.isEmpty,
               pendingBits.isEmpty,
               volatileBits.isEmpty,
               !hasContainment {
                return true
            }
            let hasLiveIntake = pendingItems.contains {
                redemptionTasks[$0.id] != nil
            }
            let hasBitsWorker = pendingBits.contains {
                paidRedemptionTasks[$0.id] != nil
            }
            let hasVolatileBitsWorker = volatileBits.contains {
                paidRedemptionTasks[$0.id] != nil
            }
            guard hasLiveIntake
                    || hasBitsWorker
                    || hasVolatileBitsWorker
                    || hasContainment else {
                break
            }
            guard clock.now < deadline else {
                Log.error(
                    "TwitchChatService: Timed out waiting for live paid-event intake before credential teardown",
                    category: "Twitch")
                return false
            }
            do {
                try await Task.sleep(for: .milliseconds(25))
            } catch {
                return false
            }
        }

        // Wake only this broadcaster's durable work. Replacing a sleeping
        // redemption worker is safe because disk remains authoritative.
        let replayItems = redemptionResolutionOutbox.pendingItems().filter {
            $0.broadcasterID == broadcasterID
        }
        for item in replayItems {
            redemptionResolutionTasks[item.id]?.cancel()
            redemptionResolutionTasks[item.id] = nil
            redemptionResolutionWorkerIDs[item.id] = nil
            if item.isIntake {
                resolveUnknownRedemptionIntake(item)
            } else {
                startPersistedRedemptionResolution(item)
            }
        }
        replayPendingBitsEvents()

        while true {
            let pendingItems = redemptionResolutionOutbox.pendingItems().filter {
                $0.broadcasterID == broadcasterID
            }
            let pendingBits = redemptionResolutionOutbox.pendingBitsItems(
                broadcasterID: broadcasterID)
            let volatileBits = pendingVolatileBitsFallbackItems(
                broadcasterID: broadcasterID)
            let hasContainment = TwitchRedemptionTeardownGate.hasContainment(
                serviceID: ObjectIdentifier(self),
                broadcasterID: broadcasterID)
            if pendingItems.isEmpty,
               pendingBits.isEmpty,
               volatileBits.isEmpty,
               !hasContainment {
                return true
            }

            let hasLiveIntake = pendingItems.contains {
                redemptionTasks[$0.id] != nil
            }
            let hasResolutionWorker = pendingItems.contains {
                redemptionResolutionTasks[$0.id] != nil
            }
            let hasBitsWorker = pendingBits.contains {
                paidRedemptionTasks[$0.id] != nil
            }
            let hasVolatileBitsWorker = volatileBits.contains {
                paidRedemptionTasks[$0.id] != nil
            }
            guard hasLiveIntake
                    || hasResolutionWorker
                    || hasBitsWorker
                    || hasVolatileBitsWorker
                    || hasContainment else {
                Log.error(
                    "TwitchChatService: Persisted paid-event work could not be drained before credential teardown",
                    category: "Twitch")
                return false
            }
            guard clock.now < deadline else {
                Log.error(
                    "TwitchChatService: Timed out draining persisted paid-event work before credential teardown",
                    category: "Twitch")
                return false
            }
            do {
                try await Task.sleep(for: .milliseconds(25))
            } catch {
                return false
            }
        }
    }

    /// Holds the managed reward while a verified actor or stored grant still owns
    /// the credentials that can mutate it. Account deletion/replacement awaits
    /// this bounded attempt before clearing actor or Keychain state; transport
    /// reconnects do not call it and continue to rely on fresh-session reconciliation.
    func pauseManagedRewardBeforeCredentialTeardown(
        allowDiscardingOpaqueRedemptionRecovery: Bool = false
    ) async -> Bool {
        // Probe before any fast path. If a reward can still be proven below we
        // pause it first, but no branch may clear credentials while this is false.
        let redemptionStorageIsSafe = allowDiscardingOpaqueRedemptionRecovery
            || redemptionStorageIsSafeForCredentialTeardown()

        guard let credentials = managedRewardTeardownCredentials(
            expectedBroadcasterID: nil
        ) else {
            let rewardSnapshot = TwitchManagedRewardStore.snapshot()
            let hasPendingWork =
                !redemptionResolutionOutbox.pendingItems().isEmpty
                    || !redemptionResolutionOutbox.pendingBitsItems().isEmpty
                    || !pendingVolatileBitsFallbackItems().isEmpty
            let hasManagedReward = rewardSnapshot != .none
            if !hasManagedReward, !hasPendingWork {
                return redemptionStorageIsSafe
            }
            Log.error(
                "TwitchChatService: Refusing credential teardown because the "
                    + "old broadcaster credentials cannot be proven",
                category: "Twitch")
            return false
        }

        let serviceID = ObjectIdentifier(self)
        let teardownGeneration = channelOwnershipGeneration
        guard TwitchRedemptionTeardownGate.beginTeardown(
            serviceID: serviceID,
            broadcasterID: credentials.broadcasterID,
            generation: teardownGeneration
        ) else {
            return false
        }
        var teardownSucceeded = false
        defer {
            if !teardownSucceeded {
                TwitchRedemptionTeardownGate.cancelTeardown(
                    serviceID: serviceID,
                    broadcasterID: credentials.broadcasterID,
                    generation: teardownGeneration)
            }
        }

        guard await awaitManagedRewardSetupsBeforeCredentialTeardown(
            broadcasterID: credentials.broadcasterID,
            generation: teardownGeneration) else {
            return false
        }

        // Setup may have created or migrated the reward while teardown waited,
        // so identity and durable ownership must be read only after that fence.
        let rewardSnapshot = TwitchManagedRewardStore.snapshot()
        guard rewardSnapshot != .corrupt else {
            Log.error(
                "TwitchChatService: Refusing credential teardown because the managed reward identity is corrupt",
                category: "Twitch")
            return false
        }

        let pendingBroadcasterIDs = Set(
            redemptionResolutionOutbox.pendingItems().map(\.broadcasterID)
                + redemptionResolutionOutbox.pendingBitsItems()
                    .map(\.broadcasterID)
                + pendingVolatileBitsFallbackItems()
                    .map(\.broadcasterID))
        guard pendingBroadcasterIDs.count <= 1,
              pendingBroadcasterIDs.first == nil
                || pendingBroadcasterIDs.first == credentials.broadcasterID else {
            Log.error(
                "TwitchChatService: Refusing credential teardown because "
                    + "persisted redemption ownership conflicts with the old broadcaster",
                category: "Twitch")
            return false
        }

        guard rewardSnapshot != .none else {
            guard redemptionStorageIsSafe else {
                return false
            }
            let settled = await settleRedemptionWorkBeforeCredentialTeardown(
                broadcasterID: credentials.broadcasterID)
            teardownSucceeded = settled
            return settled
        }

        let identity: TwitchManagedRewardStore.Identity
        do {
            guard let resolvedIdentity = try await channelPointsService
                .managedRewardIdentity(credentials: credentials),
                  resolvedIdentity.broadcasterID == credentials.broadcasterID,
                  TwitchManagedRewardStore.matches(resolvedIdentity) else {
                return false
            }
            identity = resolvedIdentity
        } catch {
            Log.error(
                "TwitchChatService: Refusing credential teardown because "
                    + "managed reward ownership could not be verified - "
                    + error.localizedDescription,
                category: "Twitch")
            return false
        }

        // A caller canceling its UI task must not cancel the last request that
        // can make the old account reward safe. Waiting for the setup lease
        // above makes this pause the final mutation from the old generation.
        let channelPointsService = self.channelPointsService
        let result = await Task.detached(priority: .userInitiated) {
            do {
                try await channelPointsService.setRewardPaused(
                    credentials: credentials,
                    rewardID: identity.rewardID,
                    paused: true,
                    requestTimeout: 5)
                return (
                    safe: true,
                    rewardMissing: false,
                    failureDescription: nil as String?)
            } catch let error as TwitchChannelPointsService.RewardError {
                if case .http(status: 404, body: _) = error {
                    return (
                        safe: true,
                        rewardMissing: true,
                        failureDescription: nil as String?)
                }
                return (
                    safe: false,
                    rewardMissing: false,
                    failureDescription: error.localizedDescription)
            } catch {
                return (
                    safe: false,
                    rewardMissing: false,
                    failureDescription: error.localizedDescription)
            }
        }.value

        guard result.safe else {
            Log.error(
                "TwitchChatService: Could not pause managed reward before credential teardown - "
                    + (result.failureDescription ?? "unknown failure"),
                category: "Twitch")
            return false
        }
        guard redemptionStorageIsSafe else {
            return false
        }
        if !result.rewardMissing {
            do {
                let unfulfilledIDs = try await channelPointsService
                    .unfulfilledRedemptionIDs(
                        credentials: credentials,
                        rewardID: identity.rewardID,
                        requestTimeout: 5)
                for redemptionID in unfulfilledIDs {
                    guard !redemptionResolutionOutbox
                        .hasAcknowledgedRedemption(
                            broadcasterID: identity.broadcasterID,
                            rewardID: identity.rewardID,
                            redemptionID: redemptionID) else {
                        continue
                    }
                    _ = try redemptionResolutionOutbox.enqueueIntake(
                        broadcasterID: identity.broadcasterID,
                        rewardID: identity.rewardID,
                        redemptionID: redemptionID)
                }
            } catch {
                setRedemptionStatus(.storageUnavailable)
                Log.error(
                    "TwitchChatService: Could not capture the final paused-reward "
                        + "redemption snapshot before credential teardown - "
                        + error.localizedDescription,
                    category: "Twitch")
                return false
            }
        }
        guard await settleRedemptionWorkBeforeCredentialTeardown(
            broadcasterID: identity.broadcasterID) else {
            return false
        }

        if result.rewardMissing {
            guard TwitchManagedRewardStore.remove(matching: identity) else {
                return false
            }
            Log.info(
                "TwitchChatService: Managed reward was already absent during credential teardown",
                category: "Twitch")
        } else {
            Log.info(
                "TwitchChatService: Paused managed reward and drained redemptions before credential teardown",
                category: "Twitch")
        }
        teardownSucceeded = true
        return true
    }

    /// Pauses the WolfWave-managed channel-point reward so it can't be redeemed
    /// while channel-point requests are off. No-op when no reward was ever
    /// created or broadcaster credentials are unavailable.
    private func pauseManagedRewardIfPossible(
        receiveContext: EventSubReceiveContext? = nil
    ) async {
        guard receiveContextIsCurrent(receiveContext),
              let credentials = currentChannelPointCredentials() else {
            return
        }
        do {
            guard let identity = try await channelPointsService
                .managedRewardIdentity(credentials: credentials) else {
                return
            }
            guard receiveContextIsCurrent(receiveContext),
                  channelPointCredentialsAreCurrent(
                    credentials,
                    rewardID: identity.rewardID) else {
                return
            }
            try await channelPointsService.setRewardPaused(
                credentials: credentials,
                rewardID: identity.rewardID,
                paused: true)
            guard receiveContextIsCurrent(receiveContext) else { return }
            Log.info(
                "TwitchChatService: Paused channel-point reward (requests off)",
                category: "Twitch")
        } catch {
            guard receiveContextIsCurrent(receiveContext) else { return }
            Log.error(
                "TwitchChatService: Failed to pause channel-point reward - \(error.localizedDescription)",
                category: "Twitch")
        }
    }

    /// Re-checks the sticky outbox circuit breaker after each setup suspension.
    /// If an EventSub delivery failed intake while an unpause was in flight, a
    /// fresh pause here is ordered after that response and therefore wins.
    private func holdManagedRewardIfIntakeStorageUnavailable(
        receiveContext: EventSubReceiveContext? = nil
    ) async -> Bool {
        guard redemptionResolutionOutbox.intakeStorageIsUnavailable() else {
            return false
        }
        setRedemptionStatus(.storageUnavailable)
        await pauseManagedRewardIfPossible(receiveContext: receiveContext)
        guard receiveContextIsCurrent(receiveContext) else { return true }
        setRedemptionStatus(.storageUnavailable)
        return true
    }

    private func subscribeToChannelPointsRedemption(
        receiveContext: EventSubReceiveContext? = nil
    ) async -> Bool {
        guard receiveContextIsCurrent(receiveContext) else { return false }
        guard let broadcasterID, let token = oauthToken,
              let clientID, let sessionID else { return false }
        let body = Self.eventSubBody(
            type: AppConstants.Twitch.eventSubChannelPointsRedemption,
            broadcasterID: broadcasterID, sessionID: sessionID)
        return await postEventSubSubscription(
            body: body,
            token: token,
            clientID: clientID,
            label: "channel-point redemptions",
            receiveContext: receiveContext
        )
    }

    private func subscribeToBitsUse(
        receiveContext: EventSubReceiveContext? = nil
    ) async {
        guard receiveContextIsCurrent(receiveContext) else { return }
        guard let broadcasterID, let token = oauthToken, let clientID, let sessionID else { return }
        let body = Self.eventSubBody(
            type: AppConstants.Twitch.eventSubBitsUse,
            broadcasterID: broadcasterID, sessionID: sessionID)
        _ = await postEventSubSubscription(
            body: body,
            token: token,
            clientID: clientID,
            label: "bit usage",
            receiveContext: receiveContext
        )
    }

    // MARK: - Redemption Event Handlers

    /// Handles a channel-point reward redemption. Ignores redemptions for any
    /// reward other than the WolfWave-managed one, routes the viewer's input
    /// into the song-request pipeline, then fulfils the redemption on success
    /// or cancels it (refunding the points) on failure.
    func handleChannelPointsRedemption(_ payload: [String: Any]) {
        // Note: the enabled check happens inside the Task below (after we confirm
        // this is our reward), so a redemption that arrives while the feature is
        // off is refunded rather than silently swallowed.
        guard let event = payload["event"] as? [String: Any] else { return }

        let rewardID = ((event["reward"] as? [String: Any])?["id"] as? String) ?? ""
        let eventBroadcasterID = ((event["broadcaster_user_id"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rewardID.isEmpty,
              !eventBroadcasterID.isEmpty,
              TwitchManagedRewardStore.matches(
                TwitchManagedRewardStore.Identity(
                    rewardID: rewardID,
                    broadcasterID: eventBroadcasterID)
              ) else {
            return
        }

        let redemptionID = (event["id"] as? String) ?? ""
        let userName = ((event["user_name"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let userInput = ((event["user_input"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !redemptionID.isEmpty, !userName.isEmpty else { return }

        if redemptionResolutionOutbox.hasAcknowledgedRedemption(
            broadcasterID: eventBroadcasterID,
            rewardID: rewardID,
            redemptionID: redemptionID
        ) {
            return
        }
        let songRequestService = self.songRequestService
        let generation = connectionGeneration

        // Once a storage write fails, every later delivery is contained without
        // touching the song queue. The reward pause closes future intake at
        // Twitch; any redemption already in flight is refunded best-effort.
        if redemptionResolutionOutbox.intakeStorageIsUnavailable() {
            beginRedemptionStorageFailureContainment(
                broadcasterID: eventBroadcasterID,
                rewardID: rewardID,
                redemptionID: redemptionID,
                resolution: .canceled)
            return
        }

        let intake: TwitchRedemptionResolutionOutbox.Item
        let inserted: Bool
        do {
            let result = try redemptionResolutionOutbox.enqueueIntake(
                broadcasterID: eventBroadcasterID,
                rewardID: rewardID,
                redemptionID: redemptionID
            )
            intake = result.item
            inserted = result.inserted
        } catch {
            // Do not touch the volatile queue unless the recovery intent is on
            // disk first. A write failure is safer than consuming points and
            // losing the only record that they still need to be resolved.
            Log.error(
                "TwitchChatService: Could not persist redemption intake \(redemptionID): \(error.localizedDescription)",
                category: "Twitch")
            beginRedemptionStorageFailureContainment(
                broadcasterID: eventBroadcasterID,
                rewardID: rewardID,
                redemptionID: redemptionID,
                resolution: .canceled)
            return
        }

        if !inserted {
            // A live pipeline owns intake until it records the queue outcome.
            // Otherwise this is a duplicate delivery after a crash/cancel: an
            // unknown outcome must refund, while a known outcome can resume.
            guard redemptionTasks[intake.id] == nil else { return }
            if intake.isIntake {
                resolveUnknownRedemptionIntake(intake)
            } else {
                startPersistedRedemptionResolution(intake)
            }
            return
        }

        redemptionTasks[intake.id] = Task { [weak self] in
            await self?.runChannelPointsRedemption(
                intake: intake,
                rewardID: rewardID,
                redemptionID: redemptionID,
                userName: userName,
                userInput: userInput,
                service: songRequestService,
                generation: generation,
                broadcasterID: eventBroadcasterID)
            await self?.clearRedemptionTask(intake.id)
        }
    }

    /// Runs the channel-point redemption pipeline. Cancellation (disconnect or
    /// teardown) suppresses chat replies only; the redemption itself is always
    /// resolved (fulfil/refund is Helix HTTP, independent of the chat socket),
    /// so viewer points never strand in the pending state.
    private func runChannelPointsRedemption(
        intake: TwitchRedemptionResolutionOutbox.Item,
        rewardID: String,
        redemptionID: String,
        userName: String,
        userInput: String,
        service: SongRequestService?,
        generation: UInt64,
        broadcasterID: String
    ) async {
        guard let service,
              redemptionWorkIsCurrent(
                generation: generation,
                broadcasterID: broadcasterID
              ) else {
            // Service not wired up, or cancelled before starting: the points
            // were already spent, so refund rather than strand the redemption
            // in the pending state forever.
            finalizeRedemptionIntake(intake, as: .canceled)
            return
        }

        // Channel-point requests off (toggle flipped between subscribe and
        // redemption, or the reward wasn't paused in time): refund.
        guard UserDefaults.standard.bool(
            forKey: AppConstants.UserDefaults.songRequestChannelPointsEnabled) else {
            finalizeRedemptionIntake(intake, as: .canceled)
            await sendSessionBoundMessage(
                "@\(userName) channel-point song requests are off right now. Refunding your points.",
                replyTo: nil,
                generation: generation,
                broadcasterID: broadcasterID)
            return
        }

        if userInput.isEmpty {
            finalizeRedemptionIntake(intake, as: .canceled)
            await sendSessionBoundMessage(
                "@\(userName) add a song name when you redeem. Refunding your points.",
                replyTo: nil,
                generation: generation,
                broadcasterID: broadcasterID)
            return
        }

        let result = await service.processRequest(
            query: userInput,
            username: userName,
            source: .channelPoints(redemptionID: redemptionID, rewardID: rewardID))
        let (message, resolution) = redemptionOutcome(for: result, username: userName)
        // Record the queue outcome before another suspension. If the process
        // exits while sending chat, replay still knows whether to fulfil or
        // refund instead of guessing from volatile queue state.
        finalizeRedemptionIntake(intake, as: resolution)
        if !message.isEmpty {
            await sendSessionBoundMessage(
                message,
                replyTo: nil,
                generation: generation,
                broadcasterID: broadcasterID)
        }
    }

    /// Drops a finished redemption pipeline task from the tracking table.
    private func clearRedemptionTask(_ id: UUID) {
        redemptionTasks[id] = nil
    }

    /// Handles a `channel.bits.use` event. The complete action is durable
    /// before queue mutation, so a crash replays pending work instead of losing
    /// a paid request or relying on the bounded transport dedup cache.
    func handleBitsUse(
        _ payload: [String: Any],
        eventSubMessageID: String
    ) {
        let defaults = UserDefaults.standard
        guard
            defaults.bool(forKey: AppConstants.UserDefaults.songRequestBitsEnabled),
            let event = payload["event"] as? [String: Any],
            event["type"] as? String == "cheer"
        else { return }

        let bits = (event["bits"] as? Int) ?? 0
        guard bits > 0, bits >= bitsMinimumSetting() else { return }

        let userName = ((event["user_name"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let eventBroadcasterID = ((event["broadcaster_user_id"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userName.isEmpty,
              !eventBroadcasterID.isEmpty,
              eventBroadcasterID == broadcasterID else {
            return
        }

        guard !volatileBitsFallbackIsClaimed(
            messageID: eventSubMessageID,
            broadcasterID: eventBroadcasterID
        ) else {
            return
        }

        let boostEnabled = defaults.bool(
            forKey: AppConstants.UserDefaults.songRequestBitsBoostEnabled)
        let query = Self.cleanBitsMessage(event["message"] as? [String: Any])
        do {
            let result = try redemptionResolutionOutbox.enqueueBits(
                messageID: eventSubMessageID,
                broadcasterID: eventBroadcasterID,
                userName: userName,
                bits: bits,
                boostEnabled: boostEnabled,
                query: query)
            guard let item = result.item else { return }
            startBitsEvent(
                item,
                requiresDurableAcknowledgement: true,
                generation: connectionGeneration)
        } catch {
            setRedemptionStatus(.storageUnavailable)
            Log.error(
                "TwitchChatService: Could not persist Bits intake "
                    + "\(eventSubMessageID); using process-owned fallback - "
                    + error.localizedDescription,
                category: "Twitch")
            guard let fallback = claimVolatileBitsFallback(
                messageID: eventSubMessageID,
                broadcasterID: eventBroadcasterID,
                userName: userName,
                bits: bits,
                boostEnabled: boostEnabled,
                query: query
            ) else {
                return
            }
            startBitsEvent(
                fallback,
                requiresDurableAcknowledgement: false,
                generation: connectionGeneration)
        }
    }

    private func pruneVolatileBitsFallbacks(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(
            -TwitchRedemptionResolutionOutbox.paidEventTombstoneRetention)
        volatileBitsFallbacks = volatileBitsFallbacks.filter {
            !$0.value.completed
                || $0.value.claimedAt >= cutoff
                || paidRedemptionTasks[$0.value.item.id] != nil
        }
    }

    private func volatileBitsFallbackIsClaimed(
        messageID: String,
        broadcasterID: String
    ) -> Bool {
        pruneVolatileBitsFallbacks()
        return volatileBitsFallbacks[
            VolatileBitsFallbackKey(
                messageID: messageID,
                broadcasterID: broadcasterID)
        ] != nil
    }

    private func claimVolatileBitsFallback(
        messageID: String,
        broadcasterID: String,
        userName: String,
        bits: Int,
        boostEnabled: Bool,
        query: String
    ) -> TwitchRedemptionResolutionOutbox.BitsItem? {
        pruneVolatileBitsFallbacks()
        let key = VolatileBitsFallbackKey(
            messageID: messageID,
            broadcasterID: broadcasterID)
        guard volatileBitsFallbacks[key] == nil else { return nil }
        let now = Date()
        let item = TwitchRedemptionResolutionOutbox.BitsItem(
            id: UUID(),
            messageID: messageID,
            broadcasterID: broadcasterID,
            userName: userName,
            bits: bits,
            boostEnabled: boostEnabled,
            query: query,
            createdAt: now)
        volatileBitsFallbacks[key] = VolatileBitsFallback(
            item: item,
            claimedAt: now,
            completed: false)
        return item
    }

    private func completeVolatileBitsFallback(
        _ item: TwitchRedemptionResolutionOutbox.BitsItem
    ) {
        let key = VolatileBitsFallbackKey(
            messageID: item.messageID,
            broadcasterID: item.broadcasterID)
        guard var fallback = volatileBitsFallbacks[key],
              fallback.item.id == item.id else {
            return
        }
        fallback.completed = true
        volatileBitsFallbacks[key] = fallback
    }

    private func pendingVolatileBitsFallbackItems(
        broadcasterID: String? = nil
    ) -> [TwitchRedemptionResolutionOutbox.BitsItem] {
        pruneVolatileBitsFallbacks()
        return volatileBitsFallbacks.values
            .filter {
                !$0.completed
                    && (broadcasterID == nil
                        || $0.item.broadcasterID == broadcasterID)
            }
            .map(\.item)
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Replays pending Bits work only for the active broadcaster. The request
    /// queue is intentionally process-local, so a process crash after queue
    /// mutation loses that volatile mutation and replay applies it exactly once
    /// to the fresh queue. In-process workers are retained until acknowledgement.
    func replayPendingBitsEvents() {
        guard let broadcasterID, songRequestService != nil else { return }
        pruneVolatileBitsFallbacks()
        let generation = connectionGeneration
        for item in redemptionResolutionOutbox.pendingBitsItems(
            broadcasterID: broadcasterID
        ) {
            startBitsEvent(
                item,
                requiresDurableAcknowledgement: true,
                generation: generation)
        }
        for fallback in volatileBitsFallbacks.values
        where fallback.item.broadcasterID == broadcasterID
            && !fallback.completed {
            startBitsEvent(
                fallback.item,
                requiresDurableAcknowledgement: false,
                generation: generation)
        }
    }

    private func startBitsEvent(
        _ item: TwitchRedemptionResolutionOutbox.BitsItem,
        requiresDurableAcknowledgement: Bool,
        generation: UInt64
    ) {
        guard paidRedemptionTasks[item.id] == nil,
              let service = songRequestService,
              broadcasterID == item.broadcasterID else {
            return
        }
        paidRedemptionTasks[item.id] = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.applyPersistedBitsEvent(
                item,
                service: service)
            guard outcome.applied else {
                await self.clearPaidRedemptionTask(item.id)
                return
            }
            if requiresDurableAcknowledgement {
                guard await self.acknowledgeBitsEventWithRetry(item) else {
                    await self.clearPaidRedemptionTask(item.id)
                    return
                }
            } else {
                await self.completeVolatileBitsFallback(item)
            }
            if let message = outcome.message, !message.isEmpty {
                await self.sendSessionBoundMessage(
                    message,
                    replyTo: nil,
                    generation: generation,
                    broadcasterID: item.broadcasterID)
            }
            await self.clearPaidRedemptionTask(item.id)
        }
    }

    private func applyPersistedBitsEvent(
        _ item: TwitchRedemptionResolutionOutbox.BitsItem,
        service: SongRequestService
    ) async -> (applied: Bool, message: String?) {
        guard !Task.isCancelled else { return (false, nil) }

        if item.boostEnabled,
           let boosted = await service.boost(username: item.userName) {
            return (
                true,
                "@\(item.userName) boosted \"\(boosted.title)\" to the front of the queue! (\(item.bits) bits)")
        }

        guard !Task.isCancelled else { return (false, nil) }
        guard !item.query.isEmpty else {
            let message = item.boostEnabled
                ? "@\(item.userName) no song of yours to boost. Include a song name in your cheer to request one."
                : nil
            return (true, message)
        }

        let result = await service.processRequest(
            query: item.query,
            username: item.userName,
            source: .bits(amount: item.bits))
        if case .cancelled = result {
            return (false, nil)
        }
        return (
            true,
            bitsOutcomeMessage(for: result, username: item.userName))
    }

    /// Retries only the local atomic acknowledgement; the paid queue action is
    /// never repeated in-process after it has been applied.
    private func acknowledgeBitsEventWithRetry(
        _ item: TwitchRedemptionResolutionOutbox.BitsItem
    ) async -> Bool {
        var attempt = 0
        while !Task.isCancelled {
            do {
                try redemptionResolutionOutbox.acknowledgeBits(item.id)
                return true
            } catch {
                setRedemptionStatus(.storageUnavailable)
                Log.error(
                    "TwitchChatService: Bits action \(item.messageID) completed "
                        + "but its durable acknowledgement failed - "
                        + error.localizedDescription,
                    category: "Twitch")
                attempt += 1
                guard await sleepBeforeRedemptionRetry(
                    attempt: attempt,
                    retryAfter: nil
                ) else {
                    return false
                }
            }
        }
        return false
    }

    private func clearPaidRedemptionTask(_ id: UUID) {
        paidRedemptionTasks[id] = nil
    }

    private func clearContainmentTask(
        _ id: UUID,
        settled: Bool
    ) {
        paidRedemptionTasks[id] = nil
        if settled {
            TwitchRedemptionTeardownGate.endContainment(id: id)
        }
    }

    // MARK: - Redemption Helpers

    /// Durably trips the local circuit breaker before launching HTTP cleanup.
    /// The task is tracked with other paid work so socket reconnects cannot
    /// cancel the pause/refund sequence after a viewer has spent points.
    private func beginRedemptionStorageFailureContainment(
        broadcasterID: String,
        rewardID: String,
        redemptionID: String,
        resolution: TwitchChannelPointsService.Resolution?
    ) {
        setRedemptionStatus(.storageUnavailable)
        let taskID = UUID()
        TwitchRedemptionTeardownGate.beginContainment(
            id: taskID,
            serviceID: ObjectIdentifier(self),
            broadcasterID: broadcasterID)
        paidRedemptionTasks[taskID] = Task { [weak self] in
            var attempt = 0
            while !Task.isCancelled {
                guard let settled = await self?
                    .pauseRewardAndResolveUnpersistedIntake(
                        broadcasterID: broadcasterID,
                        rewardID: rewardID,
                        redemptionID: redemptionID,
                        resolution: resolution) else {
                    TwitchRedemptionTeardownGate.endContainment(id: taskID)
                    return
                }
                if settled {
                    await self?.clearContainmentTask(
                        taskID,
                        settled: true)
                    return
                }

                attempt += 1
                guard let shouldRetry = await self?.sleepBeforeRedemptionRetry(
                    attempt: attempt,
                    retryAfter: nil),
                      shouldRetry else {
                    await self?.clearContainmentTask(
                        taskID,
                        settled: false)
                    return
                }
            }
            await self?.clearContainmentTask(
                taskID,
                settled: false)
        }
    }

    /// Pauses at the source first, then applies the conservative refund
    /// requested by intake/outcome failures. The containment remains unresolved
    /// until both operations are confirmed (with 404 treated idempotently).
    private func pauseRewardAndResolveUnpersistedIntake(
        broadcasterID eventBroadcasterID: String,
        rewardID: String,
        redemptionID: String,
        resolution: TwitchChannelPointsService.Resolution?
    ) async -> Bool {
        let identity = TwitchManagedRewardStore.Identity(
            rewardID: rewardID,
            broadcasterID: eventBroadcasterID)
        guard TwitchManagedRewardStore.matches(identity),
              let activeBroadcasterID = broadcasterID,
              let activeBotID = botID,
              activeBroadcasterID == eventBroadcasterID,
              activeBotID == eventBroadcasterID,
              let credentials = currentChannelPointCredentials(),
              credentials.broadcasterID == eventBroadcasterID else {
            Log.warn(
                "TwitchChatService: Storage failed for redemption \(redemptionID), but active "
                    + "broadcaster credentials no longer match; retaining unresolved containment",
                category: "Twitch")
            return false
        }

        let sourceIsSafe: Bool
        do {
            try await channelPointsService.setRewardPaused(
                credentials: credentials,
                rewardID: rewardID,
                paused: true)
            sourceIsSafe = true
            Log.info(
                "TwitchChatService: Paused channel-point reward after redemption storage failure",
                category: "Twitch")
        } catch let TwitchChannelPointsService.RewardError.http(status, _)
            where status == 404 {
            sourceIsSafe = true
        } catch is CancellationError {
            return false
        } catch {
            sourceIsSafe = false
            Log.error(
                "TwitchChatService: Could not pause channel-point reward after storage failure - "
                    + error.localizedDescription,
                category: "Twitch")
        }

        guard let resolution else { return sourceIsSafe }

        let redemptionIsSettled: Bool
        do {
            try await channelPointsService.resolveRedemptionWithMetadata(
                credentials: credentials,
                rewardID: rewardID,
                redemptionID: redemptionID,
                as: resolution)
            redemptionIsSettled = true
        } catch let TwitchChannelPointsService.RedemptionResolutionError.http(
            status,
            _,
            _
        ) where status == 404 {
            redemptionIsSettled = TwitchManagedRewardStore.matches(identity)
        } catch is CancellationError {
            return false
        } catch {
            redemptionIsSettled = false
            Log.error(
                "TwitchChatService: Could not apply \(resolution.rawValue) to redemption "
                    + "\(redemptionID) after storage failure - \(error.localizedDescription)",
                category: "Twitch")
        }
        return sourceIsSafe && redemptionIsSettled
    }

    /// Atomically records a known outcome before starting any Helix request.
    private func finalizeRedemptionIntake(
        _ intake: TwitchRedemptionResolutionOutbox.Item,
        as resolution: TwitchChannelPointsService.Resolution
    ) {
        do {
            let item = try redemptionResolutionOutbox.updateResolution(
                intake.id,
                to: resolution)
            startPersistedRedemptionResolution(item)
        } catch {
            Log.error(
                "TwitchChatService: Could not persist \(resolution.rawValue) outcome "
                    + "for redemption \(intake.redemptionID); intake remains for a "
                    + "startup refund: \(error.localizedDescription)",
                category: "Twitch")
            beginRedemptionStorageFailureContainment(
                broadcasterID: intake.broadcasterID,
                rewardID: intake.rewardID,
                redemptionID: intake.redemptionID,
                resolution: .canceled)
        }
    }

    /// Intake has no reconstructible queue result after a process exit or a
    /// canceled live pipeline. Persist the conservative refund before Helix.
    private func resolveUnknownRedemptionIntake(
        _ intake: TwitchRedemptionResolutionOutbox.Item
    ) {
        finalizeRedemptionIntake(intake, as: .canceled)
    }

    /// Replays every durable item not already owned by a live worker. Safe to
    /// call at app startup, after OAuth, and after each channel join.
    func replayPendingRedemptionResolutions() {
        replayPendingBitsEvents()
        // A credential transition must wake items that were sleeping while no
        // matching account was available. Disk is authoritative, so replacing
        // the in-memory workers cannot lose work.
        redemptionResolutionTasks.values.forEach { $0.cancel() }
        redemptionResolutionTasks.removeAll()
        redemptionResolutionWorkerIDs.removeAll()
        for item in redemptionResolutionOutbox.pendingItems() {
            if item.isIntake {
                // Never race a live queue pipeline with a refund. Its owner will
                // persist the real outcome or leave intake for a later replay.
                guard redemptionTasks[item.id] == nil else { continue }
                resolveUnknownRedemptionIntake(item)
            } else {
                startPersistedRedemptionResolution(item)
            }
        }
    }

    private func startPersistedRedemptionResolution(
        _ item: TwitchRedemptionResolutionOutbox.Item
    ) {
        guard redemptionResolutionTasks[item.id] == nil else { return }
        let workerID = UUID()
        redemptionResolutionWorkerIDs[item.id] = workerID
        redemptionResolutionTasks[item.id] = Task { [weak self] in
            await self?.runPersistedRedemptionResolution(item)
            await self?.clearRedemptionResolutionTask(
                item.id,
                workerID: workerID
            )
        }
    }

    private func runPersistedRedemptionResolution(
        _ item: TwitchRedemptionResolutionOutbox.Item
    ) async {
        guard let resolution = item.resolution else {
            Log.error(
                "TwitchChatService: Invalid persisted redemption resolution \(item.resolutionRawValue)",
                category: "Twitch")
            return
        }

        var transientAttempt = 0
        while !Task.isCancelled {
            guard !Task.isCancelled else { return }
            guard let snapshot = TwitchCredentialStore.shared.accessSnapshot(),
                  snapshot.userID == item.broadcasterID,
                  let resolvedClientID = clientID ?? redemptionClientIDProvider(),
                  !resolvedClientID.isEmpty else {
                Log.warn(
                    "TwitchChatService: Keeping redemption \(item.redemptionID) "
                        + "pending until its broadcaster credentials are available",
                    category: "Twitch")
                transientAttempt += 1
                guard await sleepBeforeRedemptionRetry(
                    attempt: transientAttempt,
                    retryAfter: .seconds(60)
                ) else { return }
                continue
            }

            let credentials = TwitchChannelPointsService.Credentials(
                broadcasterID: item.broadcasterID,
                token: snapshot.accessToken,
                clientID: resolvedClientID
            )

            do {
                try await channelPointsService.resolveRedemptionWithMetadata(
                    credentials: credentials,
                    rewardID: item.rewardID,
                    redemptionID: item.redemptionID,
                    as: resolution
                )
                acknowledgeRedemptionResolution(item)
                return
            } catch is CancellationError {
                return
            } catch let error as TwitchChannelPointsService.RedemptionResolutionError {
                switch error {
                case let .http(status, _, retryAfter):
                    // A prior request may have reached Twitch just before the
                    // process exited. "Not found" is the idempotent replay
                    // terminal: there is no pending redemption left to resolve.
                    if status == 404 {
                        let identity = TwitchManagedRewardStore.Identity(
                            rewardID: item.rewardID,
                            broadcasterID: item.broadcasterID)
                        guard TwitchManagedRewardStore.matches(identity) else {
                            Log.error(
                                "TwitchChatService: Keeping redemption "
                                    + "\(item.redemptionID) because the managed reward "
                                    + "owner changed before the 404 terminal",
                                category: "Twitch")
                            return
                        }
                        acknowledgeRedemptionResolution(item)
                        return
                    }

                    if status == 401 {
                        do {
                            switch try await reactiveTokenRefresh(
                                resolvedClientID,
                                expected: snapshot.accessExpectation
                            ) {
                            case let .refreshed(accessToken):
                                let adopted = adoptRefreshedAccessCredential(
                                    snapshot.accessExpectation.replacingAccessToken(
                                        accessToken),
                                    replacing: snapshot.accessExpectation
                                )
                                guard adopted else { return }
                                transientAttempt = 0
                                continue
                            case .invalid:
                                // The invalid result belongs only to the exact
                                // account/token that authorized this PATCH. A
                                // replacement account must never inherit its
                                // re-auth side effect.
                                guard TwitchCredentialStore.shared.matches(
                                    snapshot.accessExpectation
                                ) else { return }
                                signalReauthNeededAndStop()
                                return
                            case .temporarilyUnavailable:
                                break
                            case .superseded:
                                return
                            }
                        } catch is CancellationError {
                            return
                        } catch {
                            // The persisted item remains available for a future
                            // replay after this bounded attempt finishes.
                        }
                        transientAttempt += 1
                        guard await sleepBeforeRedemptionRetry(
                            attempt: transientAttempt,
                            retryAfter: retryAfter
                        ) else { return }
                        continue
                    }

                    guard Self.shouldRetryRedemptionResolution(status: status) else {
                        Log.error(
                            "TwitchChatService: Keeping unresolved redemption "
                                + "\(item.redemptionID) after HTTP \(status)",
                            category: "Twitch")
                        return
                    }
                    transientAttempt += 1
                    guard await sleepBeforeRedemptionRetry(
                        attempt: transientAttempt,
                        retryAfter: retryAfter
                    ) else { return }
                case .transport:
                    transientAttempt += 1
                    guard await sleepBeforeRedemptionRetry(
                        attempt: transientAttempt,
                        retryAfter: nil
                    ) else { return }
                case .malformedResponse:
                    Log.error(
                        "TwitchChatService: Keeping unresolved redemption "
                            + "\(item.redemptionID) after a malformed response",
                        category: "Twitch")
                    return
                case .ownershipUnverified:
                    Log.error(
                        "TwitchChatService: Keeping unresolved redemption "
                            + "\(item.redemptionID) because managed reward ownership "
                            + "is no longer verified",
                        category: "Twitch")
                    return
                }
            } catch {
                Log.error(
                    "TwitchChatService: Keeping unresolved redemption "
                        + "\(item.redemptionID): \(error.localizedDescription)",
                    category: "Twitch")
                return
            }
        }
    }

    private func acknowledgeRedemptionResolution(
        _ item: TwitchRedemptionResolutionOutbox.Item
    ) {
        do {
            try redemptionResolutionOutbox.acknowledge(item.id)
        } catch {
            // A replay may repeat the already-applied PATCH, which is safe: the
            // 404 terminal above then retries this local acknowledgement.
            Log.error(
                "TwitchChatService: Resolved redemption \(item.redemptionID) but "
                    + "could not acknowledge its outbox item: "
                    + error.localizedDescription,
                category: "Twitch")
            beginRedemptionStorageFailureContainment(
                broadcasterID: item.broadcasterID,
                rewardID: item.rewardID,
                redemptionID: item.redemptionID,
                resolution: nil)
        }
    }

    /// Focused regression seam for an acknowledgement write that fails after
    /// Twitch has already accepted the resolution.
    #if DEBUG
    func acknowledgeRedemptionResolutionForTesting(
        _ item: TwitchRedemptionResolutionOutbox.Item
    ) {
        acknowledgeRedemptionResolution(item)
    }
    #endif

    private func sleepBeforeRedemptionRetry(
        attempt: Int,
        retryAfter: Duration?
    ) async -> Bool {
        let exponent = min(max(0, attempt - 1), 8)
        let fallback = Duration.seconds(min(300, 1 << exponent))
        let delay = if let retryAfter, retryAfter > fallback {
            retryAfter
        } else {
            fallback
        }
        do {
            try await redemptionResolutionSleep(delay)
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    nonisolated static func shouldRetryRedemptionResolution(status: Int) -> Bool {
        status == 408 || status == 425 || status == 429 || (500...599).contains(status)
    }

    private func clearRedemptionResolutionTask(_ id: UUID, workerID: UUID) {
        guard redemptionResolutionWorkerIDs[id] == workerID else { return }
        redemptionResolutionTasks[id] = nil
        redemptionResolutionWorkerIDs[id] = nil
    }

    private func redemptionWorkIsCurrent(
        generation: UInt64,
        broadcasterID: String
    ) -> Bool {
        !Task.isCancelled
            && !broadcasterID.isEmpty
            && commandReplyIsCurrent(
                generation: generation,
                broadcasterID: broadcasterID
            )
    }

    /// Maps a request result to a chat message and a redemption resolution.
    private func redemptionOutcome(
        for result: SongRequestService.RequestResult,
        username: String
    ) -> (message: String, resolution: TwitchChannelPointsService.Resolution) {
        switch result {
        case .cancelled:
            return ("", .canceled)
        case let .added(item, position):
            return (
                "@\(username) added \"\(item.title)\" by \(item.artist), #\(position) in queue",
                .fulfilled)
        case let .pendingApproval(item):
            // ponytail: fulfill on submit-to-review. A later reject can't refund
            // points once the redemption is resolved, so approval-mode redemptions
            // consume points on request, not on approval.
            return (
                "@\(username) sent \"\(item.title)\" by \(item.artist) to the streamer for approval.",
                .fulfilled)
        case let .queueFull(max):
            return ("@\(username) the queue is full (\(max)). Points refunded.", .canceled)
        case let .userLimitReached(max):
            return ("@\(username) you already have \(max) songs queued. Points refunded.", .canceled)
        case .alreadyInQueue:
            return ("@\(username) that song is already queued. Points refunded.", .canceled)
        case .blocked:
            return ("@\(username) that song is on the blocklist. Points refunded.", .canceled)
        case let .notFound(query):
            let truncated = StringFormatting.truncatedWithEllipsis(query)
            return ("@\(username) no results for \"\(truncated)\". Points refunded.", .canceled)
        case .linkNotFound:
            return ("@\(username) couldn't find that on Apple Music. Points refunded.", .canceled)
        case .notAuthorized:
            return ("@\(username) song requests aren't available right now. Points refunded.", .canceled)
        case .featureDisabled:
            return ("@\(username) song requests are off right now. Points refunded.", .canceled)
        case let .error(message):
            return ("@\(username) \(message) Points refunded.", .canceled)
        }
    }

    /// Builds a chat reply for a bit-cheer song request.
    private func bitsOutcomeMessage(
        for result: SongRequestService.RequestResult,
        username: String
    ) -> String {
        switch result {
        case .cancelled:
            return ""
        case let .added(item, position):
            return "@\(username) added \"\(item.title)\" by \(item.artist), #\(position) in queue. Thanks for the bits!"
        case let .pendingApproval(item):
            return "@\(username) sent \"\(item.title)\" by \(item.artist) to the streamer for approval. Thanks for the bits!"
        case let .queueFull(max):
            return "@\(username) the queue is full (\(max)/\(max)). Try again soon!"
        case let .userLimitReached(max):
            return "@\(username) you already have \(max) songs queued."
        case .alreadyInQueue:
            return "@\(username) that song is already in the queue."
        case .blocked:
            return "@\(username) sorry, that song/artist is on the blocklist."
        case let .notFound(query):
            let truncated = StringFormatting.truncatedWithEllipsis(query)
            return "@\(username) no results for \"\(truncated)\"."
        case .linkNotFound:
            return "@\(username) couldn't find that on Apple Music."
        case .notAuthorized:
            return "@\(username) song requests aren't available right now."
        case .featureDisabled:
            return "@\(username) song requests are off right now."
        case let .error(message):
            return "@\(username) \(message)"
        }
    }

    /// Current broadcaster credentials for Helix channel-point calls, or `nil`
    /// when any credential is missing.
    private func currentChannelPointCredentials() -> TwitchChannelPointsService.Credentials? {
        guard let broadcasterID, let token = oauthToken, let clientID,
              !broadcasterID.isEmpty, !token.isEmpty, !clientID.isEmpty else { return nil }
        return TwitchChannelPointsService.Credentials(
            broadcasterID: broadcasterID, token: token, clientID: clientID)
    }

    /// Configured channel-point cost for the managed reward (default 500).
    nonisolated private func channelPointsCostSetting() -> Int {
        Preferences.int(AppConstants.UserDefaults.songRequestChannelPointsCost, default: AppConstants.UserDefaults.Defaults.songRequestChannelPointsCost)
    }

    /// Configured minimum bits required to trigger a request (default 100).
    nonisolated private func bitsMinimumSetting() -> Int {
        Preferences.int(AppConstants.UserDefaults.songRequestBitsMinimum, default: AppConstants.UserDefaults.Defaults.songRequestBitsMinimum)
    }

    /// Persists the redemption integration health for the settings UI.
    nonisolated func setRedemptionStatus(_ status: RedemptionStatus) {
        UserDefaults.standard.set(
            status.rawValue, forKey: AppConstants.UserDefaults.songRequestRedemptionStatus)
    }

    /// Extracts the viewer's song query from a `channel.bits.use` message,
    /// dropping cheermote tokens.
    nonisolated static func cleanBitsMessage(_ message: [String: Any]?) -> String {
        guard let message else { return "" }

        if let fragments = message["fragments"] as? [[String: Any]] {
            let textParts = fragments.compactMap { fragment -> String? in
                guard (fragment["type"] as? String) == "text" else { return nil }
                return fragment["text"] as? String
            }
            let joined = textParts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { return joined }
        }

        let raw = (message["text"] as? String) ?? ""
        return stripLeadingCheermotes(raw)
    }

    /// Cached compiled pattern for the leading-cheermote strip. Compiling it per call on the
    /// hot chat path was wasteful. NSRegularExpression is thread-safe for matching.
    private nonisolated static let cheermotePrefixRegex = try? NSRegularExpression(
        pattern: "^(?:[Cc]heer[0-9]+\\s*)+")

    /// Removes leading `Cheer<amount>` tokens from a raw cheer message.
    nonisolated static func stripLeadingCheermotes(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let regex = cheermotePrefixRegex,
            let match = regex.firstMatch(
                in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
            let range = Range(match.range, in: trimmed)
        else {
            return trimmed
        }
        var stripped = trimmed
        stripped.removeSubrange(range)
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
