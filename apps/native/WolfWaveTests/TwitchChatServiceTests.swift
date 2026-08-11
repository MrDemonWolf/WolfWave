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

    private let handlerStore = MockURLProtocol.HandlerStore()

    /// Reset UserDefaults keys that tests depend on to prevent cross-test contamination.
    init() {
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.currentSongCommandEnabled)
        UserDefaults.standard.removeObject(forKey: AppConstants.UserDefaults.lastSongCommandEnabled)
        clearManagedRewardIdentity()
    }

    private func installManagedRewardIdentity() {
        clearManagedRewardIdentity()
        #expect(
            TwitchManagedRewardStore.store(
                .init(
                    rewardID: "reward",
                    broadcasterID: "broadcaster"),
                replacing: .none))
    }

    private func clearManagedRewardIdentity() {
        UserDefaults.standard.removeObject(
            forKey: AppConstants.UserDefaults.songRequestChannelPointsRewardID)
        UserDefaults.standard.removeObject(
            forKey: AppConstants.UserDefaults.songRequestChannelPointsRewardIdentity)
    }

    #if DEBUG
    @Test("Debug viewer simulation matches canonical login and display-name fallback")
    func testDebugViewerSimulationUsernameMatching() {
        let suiteName = "TwitchChatServiceTests.viewer.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            " other, SOMEHANDLE ",
            forKey: AppConstants.UserDefaults.debugViewerUsernames
        )
        #expect(TwitchChatService.shouldTreatAsViewer(
            event: ["chatter_user_login": "somehandle", "chatter_user_name": "Localized Name"],
            defaults: defaults
        ))
        #expect(TwitchChatService.shouldTreatAsViewer(
            event: ["chatter_user_name": "Other"],
            defaults: defaults
        ))
        #expect(!TwitchChatService.shouldTreatAsViewer(
            event: ["chatter_user_login": "different"],
            defaults: defaults
        ))

        defaults.set(true, forKey: AppConstants.UserDefaults.debugTreatAllChattersAsViewers)
        #expect(TwitchChatService.shouldTreatAsViewer(
            event: ["chatter_user_login": "anyone"],
            defaults: defaults
        ))
    }
    #endif

    // MARK: - Initialization Tests

    @Test("EventSub 409 deletes the exact stale subscription and retries POST once")
    func testEventSubConflictRecovery() async {
        let requests = ThreadSafeBox<[URLRequest]>([])
        let requestNumber = ThreadSafeBox(0)
        handlerStore.handler = { request in
            requests.mutate { $0.append(request) }
            let number = requestNumber.value
            requestNumber.value = number + 1
            switch number {
            case 0:
                return (
                    MockURLProtocol.httpResponse(for: request, status: 409),
                    Data(#"{"id":"stale-subscription"}"#.utf8))
            case 1:
                return (MockURLProtocol.httpResponse(for: request, status: 204), Data())
            default:
                return (
                    MockURLProtocol.httpResponse(for: request, status: 202),
                    Data(#"{"data":[{"id":"replacement"}]}"#.utf8))
            }
        }
        defer { handlerStore.handler = nil }

        let service = TwitchChatService(
            eventSubHTTPClient: HTTPClient(session: MockURLProtocol.makeSession(handlerStore: handlerStore)))
        let success = ThreadSafeBox(false)
        let subscribed = await service.postEventSubSubscription(
            body: ["type": "channel.chat.message"],
            token: "token",
            clientID: "client",
            label: "chat messages",
            onSuccess: { success.value = true })

        #expect(subscribed)
        #expect(success.value)
        #expect(requests.value.map(\.httpMethod) == ["POST", "DELETE", "POST"])
        #expect(
            requests.value[1].url?.query?.contains("id=stale-subscription") == true)
    }

    @Test("EventSub 409 without a subscription ID fails instead of claiming success")
    func testEventSubConflictWithoutIDFailsClosed() async {
        let count = ThreadSafeBox(0)
        handlerStore.handler = { request in
            count.mutate { $0 += 1 }
            return (
                MockURLProtocol.httpResponse(for: request, status: 409),
                Data(#"{"error":"Conflict","status":409}"#.utf8))
        }
        defer { handlerStore.handler = nil }

        let service = TwitchChatService(
            eventSubHTTPClient: HTTPClient(session: MockURLProtocol.makeSession(handlerStore: handlerStore)))
        let subscribed = await service.postEventSubSubscription(
            body: ["type": "channel.chat.message"],
            token: "token",
            clientID: "client",
            label: "chat messages")

        #expect(!subscribed)
        #expect(count.value == 1)
    }

    @Test("Suspended connection greeting cannot queue into a replacement channel")
    func testConnectionGreetingIsGenerationScoped() async {
        let requestStarted = DispatchSemaphore(value: 0)
        let releaseRequest = DispatchSemaphore(value: 0)
        let handler: MockURLProtocol.Handler = { request in
            requestStarted.signal()
            _ = releaseRequest.wait(timeout: .now() + 2)
            return (MockURLProtocol.httpResponse(for: request, status: 503), Data())
        }
        defer { handlerStore.handler = nil }

        let service = TwitchChatService(
            helixHTTPClient: HTTPClient(
                session: MockURLProtocol.makeSession(handler: handler)))
        let generation = await service.configureChatSendForTesting(
            broadcasterID: "old-channel")
        let greeting = Task {
            await service.sendConnectionMessageIfNeeded(
                generation: generation,
                broadcasterID: "old-channel")
        }

        let started = await waitForSemaphore(
            requestStarted,
            timeout: .now() + 2
        )
        #expect(started)
        _ = await service.beginConnectionAttempt()
        await service.switchBroadcasterForTesting(to: "new-channel")
        releaseRequest.signal()
        await greeting.value

        #expect(await service.pendingMessageCount == 0)
    }

    @Test("Canceled generic chat send never enters the retry queue")
    func testCanceledGenericSendDoesNotQueue() async {
        let requestStarted = DispatchSemaphore(value: 0)
        let releaseRequest = DispatchSemaphore(value: 0)
        let handler: MockURLProtocol.Handler = { request in
            requestStarted.signal()
            _ = releaseRequest.wait(timeout: .now() + 2)
            return (MockURLProtocol.httpResponse(for: request, status: 503), Data())
        }
        defer { handlerStore.handler = nil }

        let service = TwitchChatService(
            helixHTTPClient: HTTPClient(
                session: MockURLProtocol.makeSession(handler: handler)))
        _ = await service.configureChatSendForTesting(broadcasterID: "channel")
        let send = Task { await service.sendMessage("hello") }
        let started = await waitForSemaphore(
            requestStarted,
            timeout: .now() + 2
        )
        #expect(started)
        send.cancel()
        releaseRequest.signal()
        await send.value

        #expect(await service.pendingMessageCount == 0)
    }

    @Test("Bits processing survives an EventSub reconnect and only suppresses stale chat")
    func testBitsProcessingSurvivesReconnect() async {
        let directory = makeIsolatedTempDirectory(prefix: "bits-reconnect")
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = TwitchRedemptionResolutionOutbox(
            fileURL: directory.appending(path: "outbox.json"))
        let gate = DeterministicAsyncGate()
        let searches = ThreadSafeBox(0)
        let music = MockAppleMusicController()
        music.searchProvider = { _ in
            searches.mutate { $0 += 1 }
            await gate.suspend()
            return .notFound
        }
        let requests = SongRequestService(musicController: music)
        let service = TwitchChatService(redemptionResolutionOutbox: outbox)

        let defaults = UserDefaults.standard
        defaults.set(true, forKey: AppConstants.UserDefaults.songRequestEnabled)
        defaults.set(true, forKey: AppConstants.UserDefaults.songRequestBitsEnabled)
        defaults.set(1, forKey: AppConstants.UserDefaults.songRequestBitsMinimum)
        defer {
            defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestEnabled)
            defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestBitsEnabled)
            defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestBitsMinimum)
        }

        _ = await service.configureChatSendForTesting(broadcasterID: "channel")
        await service.setSongRequestServiceReference(requests)
        await service.handleBitsUse(
            [
                "event": [
                    "type": "cheer",
                    "bits": 100,
                    "broadcaster_user_id": "channel",
                    "user_name": "Viewer",
                    "message": ["text": "Cheer100 a song"],
                ]
            ],
            eventSubMessageID: "bits-reconnect")

        #expect(await waitUntil { await gate.suspended })
        #expect(await service.activePaidRedemptionTaskCount == 1)
        _ = await service.beginConnectionAttempt()
        await gate.resume()
        #expect(await waitUntil { await service.activePaidRedemptionTaskCount == 0 })
        #expect(searches.value == 1)
        #expect(await service.pendingMessageCount == 0)
    }

    @Test("Durable Bits completion survives EventSub cache eviction and relaunch")
    func testBitsCompletionSurvivesDedupEvictionAndRelaunch() async throws {
        let directory = makeIsolatedTempDirectory(prefix: "bits-durable-dedup")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "outbox.json")
        let searches = ThreadSafeBox(0)
        let music = MockAppleMusicController()
        music.searchProvider = { _ in
            searches.mutate { $0 += 1 }
            return .notFound
        }
        let requests = SongRequestService(musicController: music)
        let chatHandler: MockURLProtocol.Handler = { request in
            (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Data(#"{"data":[{"is_sent":true}]}"#.utf8)
            )
        }
        let chatClient = HTTPClient(
            session: MockURLProtocol.makeSession(handler: chatHandler))
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: AppConstants.UserDefaults.songRequestEnabled)
        defaults.set(true, forKey: AppConstants.UserDefaults.songRequestBitsEnabled)
        defaults.set(1, forKey: AppConstants.UserDefaults.songRequestBitsMinimum)
        defer {
            defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestEnabled)
            defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestBitsEnabled)
            defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestBitsMinimum)
        }

        let paidEnvelope = try Self.eventSubEnvelope(
            messageType: "notification",
            messageID: "durable-paid-message",
            payload: [
                "subscription": [
                    "type": AppConstants.Twitch.eventSubBitsUse
                ],
                "event": [
                    "type": "cheer",
                    "bits": 100,
                    "broadcaster_user_id": "channel",
                    "user_name": "Viewer",
                    "message": ["text": "Cheer100 a song"],
                ],
            ])
        let firstOutbox = TwitchRedemptionResolutionOutbox(fileURL: file)
        let firstService = TwitchChatService(
            helixHTTPClient: chatClient,
            redemptionResolutionOutbox: firstOutbox)
        _ = await firstService.configureChatSendForTesting(
            broadcasterID: "channel")
        await firstService.setSongRequestServiceReference(requests)

        await firstService.handleWebSocketMessage(paidEnvelope)
        await firstService.awaitPaidRedemptionTasksForTesting()
        #expect(searches.value == 1)
        #expect(firstOutbox.pendingBitsItems().isEmpty)

        // The transport cache holds 500 IDs; overflow it so only the durable
        // terminal record can suppress the late at-least-once delivery.
        for index in 0..<500 {
            await firstService.handleWebSocketMessage(
                try Self.eventSubEnvelope(
                    messageType: "session_keepalive",
                    messageID: "cache-fill-\(index)",
                    payload: [:]))
        }
        await firstService.handleWebSocketMessage(paidEnvelope)
        await firstService.awaitPaidRedemptionTasksForTesting()
        #expect(searches.value == 1)

        let relaunchedOutbox = TwitchRedemptionResolutionOutbox(fileURL: file)
        let relaunchedService = TwitchChatService(
            helixHTTPClient: chatClient,
            redemptionResolutionOutbox: relaunchedOutbox)
        _ = await relaunchedService.configureChatSendForTesting(
            broadcasterID: "channel")
        await relaunchedService.setSongRequestServiceReference(requests)
        await relaunchedService.handleWebSocketMessage(paidEnvelope)
        await relaunchedService.awaitPaidRedemptionTasksForTesting()

        #expect(searches.value == 1)
        #expect(relaunchedOutbox.pendingBitsItems().isEmpty)
    }

    #if DEBUG
    @Test("Leave drains a paid frame already returned at the receive boundary")
    func testLeaveDrainsPaidFrameAtReceiveBoundary() async throws {
        let directory = makeIsolatedTempDirectory(prefix: "bits-leave-boundary")
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = TwitchRedemptionResolutionOutbox(
            fileURL: directory.appending(path: "outbox.json"))
        let searches = ThreadSafeBox(0)
        let receiveCalls = ThreadSafeBox(0)
        let receiveGate = DeterministicAsyncGate()
        let music = MockAppleMusicController()
        music.searchProvider = { _ in
            searches.mutate { $0 += 1 }
            return .notFound
        }
        let requests = SongRequestService(musicController: music)
        let paidEnvelope = try Self.eventSubEnvelope(
            messageType: "notification",
            messageID: "leave-boundary-paid-message",
            payload: [
                "subscription": [
                    "type": AppConstants.Twitch.eventSubBitsUse
                ],
                "event": [
                    "type": "cheer",
                    "bits": 100,
                    "broadcaster_user_id": "channel",
                    "user_name": "Viewer",
                    "message": ["text": "Cheer100 a song"],
                ],
            ])
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let socket = session.webSocketTask(
            with: try #require(URL(string: "wss://eventsub.wss.twitch.tv/leave")))
        let chatHandler: MockURLProtocol.Handler = { request in
            (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Data(#"{"data":[{"is_sent":true}]}"#.utf8)
            )
        }
        let service = TwitchChatService(
            helixHTTPClient: HTTPClient(
                session: MockURLProtocol.makeSession(handler: chatHandler)),
            redemptionResolutionOutbox: outbox,
            eventSubWebSocketFactory: { _ in socket },
            eventSubWebSocketResume: { _ in },
            eventSubWebSocketReceive: { _ in
                var call = 0
                receiveCalls.mutate {
                    $0 += 1
                    call = $0
                }
                if call == 1 {
                    await receiveGate.suspend()
                    return .string(paidEnvelope)
                }
                throw URLError(.networkConnectionLost)
            })
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: AppConstants.UserDefaults.songRequestEnabled)
        defaults.set(true, forKey: AppConstants.UserDefaults.songRequestBitsEnabled)
        defaults.set(1, forKey: AppConstants.UserDefaults.songRequestBitsMinimum)
        defer {
            defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestEnabled)
            defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestBitsEnabled)
            defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestBitsMinimum)
        }

        _ = await service.configureChatSendForTesting(broadcasterID: "channel")
        await service.setSongRequestServiceReference(requests)
        await service.connectToEventSub()
        #expect(await waitUntil { await receiveGate.suspended })

        let generationBeforeLeave = await service.connectionGeneration
        let leaving = Task { await service.leaveChannel() }
        #expect(await waitUntil {
            service.eventSubTeardownQuiescing.value
                && socket.state != .suspended
        })

        // Models the catch pre-check racing with leave: the actor-side guard
        // must still reject the queued lifecycle error without invalidating the
        // receive context that owns the paid frame.
        await service.handleQueuedReceiveErrorForTesting(webSocketTask: socket)
        #expect(await service.connectionGeneration == generationBeforeLeave)
        await receiveGate.resume()

        #expect(await leaving.value)
        #expect(searches.value == 1)
        #expect(outbox.pendingBitsItems().isEmpty)
        #expect(await service.broadcasterID == nil)
    }

    @Test("Explicit join during quiesce supersedes stale leave")
    func testExplicitJoinDuringQuiesceSupersedesLeave() async throws {
        let directory = makeIsolatedTempDirectory(prefix: "leave-supersession")
        defer { try? FileManager.default.removeItem(at: directory) }
        let oldReceiveGate = DeterministicAsyncGate()
        let socketFactoryCalls = ThreadSafeBox(0)
        let receiveCalls = ThreadSafeBox(0)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let oldSocket = session.webSocketTask(
            with: try #require(URL(string: "wss://eventsub.wss.twitch.tv/old")))
        let replacementSocket = session.webSocketTask(
            with: try #require(URL(string: "wss://eventsub.wss.twitch.tv/new")))
        let service = TwitchChatService(
            redemptionResolutionOutbox: TwitchRedemptionResolutionOutbox(
                fileURL: directory.appending(path: "outbox.json")),
            eventSubWebSocketFactory: { _ in
                var call = 0
                socketFactoryCalls.mutate {
                    $0 += 1
                    call = $0
                }
                return call == 1 ? oldSocket : replacementSocket
            },
            eventSubWebSocketResume: { _ in },
            eventSubWebSocketReceive: { _ in
                var call = 0
                receiveCalls.mutate {
                    $0 += 1
                    call = $0
                }
                if call == 1 {
                    await oldReceiveGate.suspend()
                    try Task.checkCancellation()
                    throw URLError(.cancelled)
                }
                try await Task.sleep(for: .seconds(3_600))
                throw CancellationError()
            })

        try await service.joinChannel(
            broadcasterID: "old-channel",
            botID: "old-channel",
            token: "old-token",
            clientID: "old-client")
        await service.connectToEventSub()
        #expect(await waitUntil { await oldReceiveGate.suspended })

        let leaving = Task { await service.leaveChannel() }
        #expect(await waitUntil {
            service.eventSubTeardownQuiescing.value
                && oldSocket.state != .suspended
        })

        try await service.joinChannel(
            broadcasterID: "new-channel",
            botID: "new-channel",
            token: "new-token",
            clientID: "new-client")
        await service.connectToEventSub()
        await oldReceiveGate.resume()

        #expect(!(await leaving.value))
        #expect(await service.broadcasterID == "new-channel")
        #expect(await service.clientID == "new-client")
        #expect(await service.hasEventSubTransportForTesting)
        await service.disconnectFromEventSub()
    }
    #endif

    @Test("Bits storage failure uses one non-evicting process fallback")
    func testBitsStorageFailureUsesSingleProcessFallback() async {
        enum InjectedFailure: Error {
            case write
        }

        let directory = makeIsolatedTempDirectory(prefix: "bits-fallback")
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = TwitchRedemptionResolutionOutbox(
            fileURL: directory.appending(path: "outbox.json"),
            atomicWriter: { _, _ in throw InjectedFailure.write })
        let searches = ThreadSafeBox(0)
        let music = MockAppleMusicController()
        music.searchProvider = { _ in
            searches.mutate { $0 += 1 }
            return .notFound
        }
        let chatHandler: MockURLProtocol.Handler = { request in
            (
                MockURLProtocol.httpResponse(for: request, status: 200),
                Data(#"{"data":[{"is_sent":true}]}"#.utf8)
            )
        }
        let service = TwitchChatService(
            helixHTTPClient: HTTPClient(
                session: MockURLProtocol.makeSession(handler: chatHandler)),
            redemptionResolutionOutbox: outbox)
        let defaults = UserDefaults.standard
        let statusKey = AppConstants.UserDefaults.songRequestRedemptionStatus
        defaults.set(true, forKey: AppConstants.UserDefaults.songRequestEnabled)
        defaults.set(true, forKey: AppConstants.UserDefaults.songRequestBitsEnabled)
        defaults.set(1, forKey: AppConstants.UserDefaults.songRequestBitsMinimum)
        defaults.removeObject(forKey: statusKey)
        defer {
            defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestEnabled)
            defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestBitsEnabled)
            defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestBitsMinimum)
            defaults.removeObject(forKey: statusKey)
        }

        _ = await service.configureChatSendForTesting(broadcasterID: "channel")
        await service.setSongRequestServiceReference(
            SongRequestService(musicController: music))
        let payload: [String: Any] = [
            "event": [
                "type": "cheer",
                "bits": 100,
                "broadcaster_user_id": "channel",
                "user_name": "Viewer",
                "message": ["text": "Cheer100 a song"],
            ]
        ]

        await service.handleBitsUse(
            payload, eventSubMessageID: "bits-fallback")
        await service.handleBitsUse(
            payload, eventSubMessageID: "bits-fallback")
        await service.awaitPaidRedemptionTasksForTesting()
        await service.handleBitsUse(
            payload, eventSubMessageID: "bits-fallback")
        await service.awaitPaidRedemptionTasksForTesting()

        #expect(searches.value == 1)
        #expect(outbox.pendingBitsItems().isEmpty)
        #expect(
            RedemptionStatus(rawValue: defaults.string(forKey: statusKey) ?? "")
                == .storageUnavailable)
    }

    @Test("Bits handler ignores power-up event variants")
    func testBitsHandlerIgnoresPowerUpVariants() async {
        let directory = makeIsolatedTempDirectory(prefix: "bits-subtypes")
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = TwitchRedemptionResolutionOutbox(
            fileURL: directory.appending(path: "outbox.json"))
        let searches = ThreadSafeBox(0)
        let music = MockAppleMusicController()
        music.searchProvider = { _ in
            searches.mutate { $0 += 1 }
            return .notFound
        }
        let service = TwitchChatService(redemptionResolutionOutbox: outbox)
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: AppConstants.UserDefaults.songRequestEnabled)
        defaults.set(true, forKey: AppConstants.UserDefaults.songRequestBitsEnabled)
        defaults.set(1, forKey: AppConstants.UserDefaults.songRequestBitsMinimum)
        defer {
            defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestEnabled)
            defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestBitsEnabled)
            defaults.removeObject(forKey: AppConstants.UserDefaults.songRequestBitsMinimum)
        }

        _ = await service.configureChatSendForTesting(broadcasterID: "channel")
        await service.setSongRequestServiceReference(
            SongRequestService(musicController: music))
        for type in ["power_up", "custom_power_up"] {
            await service.handleBitsUse(
                [
                    "event": [
                        "type": type,
                        "bits": 100,
                        "broadcaster_user_id": "channel",
                        "user_name": "Viewer",
                        "message": ["text": "a song"],
                    ]
                ],
                eventSubMessageID: "bits-\(type)")
        }

        #expect(searches.value == 0)
        #expect(outbox.pendingBitsItems().isEmpty)
        #expect(await service.activePaidRedemptionTaskCount == 0)
    }

    @Test("Channel-point intake keeps its processor across reconnect replay and duplicate delivery")
    func testChannelPointIntakeKeepsOwnerAcrossReconnectAndReplay() async throws {
        let directory = makeIsolatedTempDirectory(prefix: "redemption-owner")
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = TwitchRedemptionResolutionOutbox(
            fileURL: directory.appending(path: "outbox.json"))
        let service = TwitchChatService(redemptionResolutionOutbox: outbox)
        let gate = DeterministicAsyncGate()
        let mutations = ThreadSafeBox(0)
        let processorWasCancelled = ThreadSafeBox(false)
        installManagedRewardIdentity()
        defer { clearManagedRewardIdentity() }

        _ = await service.configureChatSendForTesting(broadcasterID: "broadcaster")
        let intake = try outbox.enqueueIntake(
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "redemption"
        ).item
        await service.installRedemptionPipelineForTesting(item: intake) {
            await gate.suspend()
            processorWasCancelled.value = Task.isCancelled
            mutations.mutate { $0 += 1 }
            _ = try? outbox.updateResolution(intake.id, to: .fulfilled)
        }
        #expect(await waitUntil { await gate.suspended })

        // Socket invalidation used to cancel and erase the durable-intake
        // owner. Replay could then persist CANCELED while that suspended task
        // later mutated the queue and tried to fulfil the same redemption.
        _ = await service.beginConnectionAttempt()
        await service.replayPendingRedemptionResolutions()
        await service.handleChannelPointsRedemption([
            "event": [
                "id": "redemption",
                "broadcaster_user_id": "broadcaster",
                "user_name": "Viewer",
                "user_input": "A song",
                "reward": ["id": "reward"],
            ]
        ])

        #expect(outbox.pendingItems() == [intake])
        #expect(await service.activeRedemptionPipelineCountForTesting == 1)
        #expect(mutations.value == 0)

        await gate.resume()
        #expect(await waitUntil {
            await service.activeRedemptionPipelineCountForTesting == 0
        })
        #expect(!processorWasCancelled.value)
        #expect(mutations.value == 1)
        #expect(outbox.pendingItems().first?.resolution == .fulfilled)
    }

    @Test("Atomic intake write failure pauses reward, exposes failure, and blocks later intake")
    func testAtomicIntakeWriteFailureFailsClosed() async {
        enum InjectedFailure: Error {
            case write
        }

        let directory = makeIsolatedTempDirectory(prefix: "redemption-write-failure")
        defer { try? FileManager.default.removeItem(at: directory) }
        let writes = ThreadSafeBox(0)
        let outbox = TwitchRedemptionResolutionOutbox(
            fileURL: directory.appending(path: "outbox.json"),
            atomicWriter: { _, _ in
                writes.mutate { $0 += 1 }
                throw InjectedFailure.write
            }
        )

        await assertRedemptionStorageFailureFailsClosed(
            outbox: outbox,
            intakeWrites: writes,
            expectedWriteAttempts: 1)
    }

    @Test("Unquarantinable redemption store pauses reward, exposes failure, and blocks intake")
    func testQuarantineFailureFailsClosed() async throws {
        enum InjectedFailure: Error {
            case quarantine
        }

        let directory = makeIsolatedTempDirectory(prefix: "redemption-quarantine-failure")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "outbox.json")
        try Data("not-json".utf8).write(to: file, options: .atomic)
        let writes = ThreadSafeBox(0)
        let outbox = TwitchRedemptionResolutionOutbox(
            fileURL: file,
            atomicWriter: { data, url in
                writes.mutate { $0 += 1 }
                try data.write(to: url, options: .atomic)
            },
            quarantineMover: { _, _ in throw InjectedFailure.quarantine }
        )

        await assertRedemptionStorageFailureFailsClosed(
            outbox: outbox,
            intakeWrites: writes,
            expectedWriteAttempts: 0)
    }

    @Test("Outcome write failure immediately exposes failure, pauses, and refunds")
    func testOutcomeWriteFailureImmediatelyFailsClosed() async {
        enum InjectedFailure: Error {
            case write
        }

        let directory = makeIsolatedTempDirectory(prefix: "redemption-outcome-failure")
        defer { try? FileManager.default.removeItem(at: directory) }
        let writes = ThreadSafeBox(0)
        let outbox = TwitchRedemptionResolutionOutbox(
            fileURL: directory.appending(path: "outbox.json"),
            atomicWriter: { data, url in
                var attempt = 0
                writes.mutate {
                    $0 += 1
                    attempt = $0
                }
                if attempt == 2 { throw InjectedFailure.write }
                try data.write(to: url, options: .atomic)
            }
        )
        let defaults = UserDefaults.standard
        let statusKey = AppConstants.UserDefaults.songRequestRedemptionStatus
        installManagedRewardIdentity()
        defaults.removeObject(forKey: statusKey)
        defer {
            clearManagedRewardIdentity()
            defaults.removeObject(forKey: statusKey)
        }

        let operations = ThreadSafeBox<[(url: String, body: String)]>([])
        let handler: MockURLProtocol.Handler = { request in
            operations.mutate {
                $0.append((
                    url: request.url?.absoluteString ?? "",
                    body: Self.requestBodyString(request)
                ))
            }
            return (MockURLProtocol.httpResponse(for: request, status: 204), Data())
        }
        let service = TwitchChatService(
            channelPointsService: TwitchChannelPointsService(
                session: MockURLProtocol.makeSession(handler: handler)),
            redemptionResolutionOutbox: outbox)
        await service.configureBroadcasterRedemptionCredentialsForTesting(
            broadcasterID: "broadcaster")

        // No song service is wired, so intake is persisted first and then the
        // conservative CANCELED outcome hits the injected second-write failure.
        await service.handleChannelPointsRedemption(
            Self.redemptionPayload(id: "outcome-failure"))
        await service.awaitRedemptionPipelinesForTesting()
        await service.awaitPaidRedemptionTasksForTesting()

        #expect(writes.value == 2)
        #expect(outbox.intakeStorageIsUnavailable())
        #expect(outbox.pendingItems().count == 1)
        #expect(
            RedemptionStatus(rawValue: defaults.string(forKey: statusKey) ?? "")
                == .storageUnavailable)
        #expect(operations.value.contains {
            $0.url.contains("/channel_points/custom_rewards?")
                && !$0.url.contains("/redemptions")
                && $0.body.contains(#""is_paused":true"#)
        })
        #expect(operations.value.contains {
            $0.url.contains("/redemptions?")
                && $0.url.contains("id=outcome-failure")
                && $0.body.contains(#""status":"CANCELED""#)
        })
    }

    #if DEBUG
    @Test("Acknowledgement write failure immediately exposes failure and pauses only")
    func testAcknowledgementWriteFailureImmediatelyFailsClosed() async throws {
        enum InjectedFailure: Error {
            case write
        }

        let directory = makeIsolatedTempDirectory(prefix: "redemption-ack-failure")
        defer { try? FileManager.default.removeItem(at: directory) }
        let writes = ThreadSafeBox(0)
        let outbox = TwitchRedemptionResolutionOutbox(
            fileURL: directory.appending(path: "outbox.json"),
            atomicWriter: { data, url in
                var attempt = 0
                writes.mutate {
                    $0 += 1
                    attempt = $0
                }
                if attempt == 2 { throw InjectedFailure.write }
                try data.write(to: url, options: .atomic)
            }
        )
        let item = try outbox.enqueue(
            broadcasterID: "broadcaster",
            rewardID: "reward",
            redemptionID: "ack-failure",
            resolution: .canceled)
        let defaults = UserDefaults.standard
        let statusKey = AppConstants.UserDefaults.songRequestRedemptionStatus
        installManagedRewardIdentity()
        defaults.removeObject(forKey: statusKey)
        defer {
            clearManagedRewardIdentity()
            defaults.removeObject(forKey: statusKey)
        }

        let operations = ThreadSafeBox<[(url: String, body: String)]>([])
        let handler: MockURLProtocol.Handler = { request in
            operations.mutate {
                $0.append((
                    url: request.url?.absoluteString ?? "",
                    body: Self.requestBodyString(request)
                ))
            }
            return (MockURLProtocol.httpResponse(for: request, status: 204), Data())
        }
        let service = TwitchChatService(
            channelPointsService: TwitchChannelPointsService(
                session: MockURLProtocol.makeSession(handler: handler)),
            redemptionResolutionOutbox: outbox)
        await service.configureBroadcasterRedemptionCredentialsForTesting(
            broadcasterID: "broadcaster")

        await service.acknowledgeRedemptionResolutionForTesting(item)
        await service.awaitPaidRedemptionTasksForTesting()

        #expect(writes.value == 2)
        #expect(outbox.intakeStorageIsUnavailable())
        #expect(outbox.pendingItems() == [item])
        #expect(
            RedemptionStatus(rawValue: defaults.string(forKey: statusKey) ?? "")
                == .storageUnavailable)
        #expect(operations.value.contains {
            $0.url.contains("/channel_points/custom_rewards?")
                && !$0.url.contains("/redemptions")
                && $0.body.contains(#""is_paused":true"#)
        })
        #expect(!operations.value.contains { $0.url.contains("/redemptions?") })
    }
    #endif

    private func assertRedemptionStorageFailureFailsClosed(
        outbox: TwitchRedemptionResolutionOutbox,
        intakeWrites: ThreadSafeBox<Int>,
        expectedWriteAttempts: Int
    ) async {
        let defaults = UserDefaults.standard
        let statusKey = AppConstants.UserDefaults.songRequestRedemptionStatus
        installManagedRewardIdentity()
        defaults.removeObject(forKey: statusKey)
        defer {
            clearManagedRewardIdentity()
            defaults.removeObject(forKey: statusKey)
        }

        let operations = ThreadSafeBox<[(url: String, body: String)]>([])
        let handler: MockURLProtocol.Handler = { request in
            operations.mutate {
                $0.append((
                    url: request.url?.absoluteString ?? "",
                    body: Self.requestBodyString(request)
                ))
            }
            return (
                MockURLProtocol.httpResponse(for: request, status: 204),
                Data()
            )
        }
        let service = TwitchChatService(
            channelPointsService: TwitchChannelPointsService(
                session: MockURLProtocol.makeSession(handler: handler)),
            redemptionResolutionOutbox: outbox)
        await service.configureBroadcasterRedemptionCredentialsForTesting(
            broadcasterID: "broadcaster")

        await service.handleChannelPointsRedemption(
            Self.redemptionPayload(id: "redemption-1"))
        await service.awaitPaidRedemptionTasksForTesting()

        #expect(intakeWrites.value == expectedWriteAttempts)
        #expect(outbox.pendingItems().isEmpty)
        #expect(
            RedemptionStatus(
                rawValue: defaults.string(forKey: statusKey) ?? "")
                == .storageUnavailable)
        #expect(RedemptionStatus.storageUnavailable.bannerMessage != nil)
        #expect(operations.value.contains {
            $0.url.contains("/channel_points/custom_rewards?")
                && !$0.url.contains("/redemptions")
                && $0.body.contains(#""is_paused":true"#)
        })
        #expect(operations.value.contains {
            $0.url.contains("/redemptions?")
                && $0.url.contains("id=redemption-1")
                && $0.body.contains(#""status":"CANCELED""#)
        })

        // A later delivery must not attempt another outbox write or enter the
        // song-request pipeline. It is contained and refunded while the durable
        // status keeps the integration visibly failed.
        await service.handleChannelPointsRedemption(
            Self.redemptionPayload(id: "redemption-2"))
        await service.awaitPaidRedemptionTasksForTesting()

        #expect(intakeWrites.value == expectedWriteAttempts)
        #expect(outbox.pendingItems().isEmpty)
        #expect(operations.value.contains {
            $0.url.contains("/redemptions?")
                && $0.url.contains("id=redemption-2")
                && $0.body.contains(#""status":"CANCELED""#)
        })
    }

    private static func redemptionPayload(id: String) -> [String: Any] {
        [
            "event": [
                "id": id,
                "broadcaster_user_id": "broadcaster",
                "user_name": "Viewer",
                "user_input": "A song",
                "reward": ["id": "reward"],
            ]
        ]
    }

    private static func eventSubEnvelope(
        messageType: String,
        messageID: String,
        payload: [String: Any]
    ) throws -> String {
        let object: [String: Any] = [
            "metadata": [
                "message_type": messageType,
                "message_id": messageID,
                "message_timestamp": ISO8601DateFormatter().string(from: Date()),
            ],
            "payload": payload,
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self)
    }

    nonisolated private static func requestBodyString(_ request: URLRequest) -> String {
        if let body = request.httpBody, !body.isEmpty {
            return String(data: body, encoding: .utf8) ?? ""
        }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var body = Data()
        let bufferSize = 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            guard count > 0 else { break }
            body.append(buffer, count: count)
        }
        return String(data: body, encoding: .utf8) ?? ""
    }

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
    
    // MARK: - Token Validation Tests

    @Test("Token validation accepts a decoded 200 response with required scopes")
    func testTokenValidationValid() async throws {
        let scopes = [
            "user:read:chat",
            "user:write:chat",
            AppConstants.Twitch.pollsScope,
            AppConstants.Twitch.channelPointsScope,
            AppConstants.Twitch.bitsScope,
        ]
        let body = try JSONSerialization.data(withJSONObject: ["scopes": scopes])

        let result = await validateToken(status: 200, body: body)

        #expect(result == .valid)
    }

    @Test("Only Twitch 401 definitively invalidates a token")
    func testTokenValidationInvalidOn401() async {
        let result = await validateToken(status: 401, body: Data())
        #expect(result == .invalid)
    }

    @Test("Rate limits and server failures keep token validity unknown")
    func testTokenValidationTransientHTTPFailures() async {
        for status in [429, 500, 503] {
            let result = await validateToken(status: status, body: Data())
            #expect(result == .temporarilyUnavailable)
        }
    }

    @Test("Malformed validate payload keeps token validity unknown")
    func testTokenValidationMalformedPayload() async {
        let result = await validateToken(status: 200, body: Data("not-json".utf8))
        #expect(result == .temporarilyUnavailable)
    }

    @Test("Transport failure keeps token validity unknown")
    func testTokenValidationTransportFailure() async {
        handlerStore.handler = { _ in throw URLError(.notConnectedToInternet) }
        defer { handlerStore.handler = nil }
        let client = HTTPClient(session: MockURLProtocol.makeSession(handlerStore: handlerStore))
        let service = TwitchChatService()

        let result = await service.validateToken(
            "stored-token", expectedClientID: nil, http: client)

        #expect(result == .temporarilyUnavailable)
    }

    @Test("Confirmed missing required scopes invalidates the local grant")
    func testTokenValidationMissingScopeIsInvalid() async throws {
        let body = try JSONSerialization.data(withJSONObject: ["scopes": []])
        let result = await validateToken(
            status: 200,
            body: body,
            requiredScopes: ["user:read:chat"])
        #expect(result == .invalid)
    }

    @Test("Token validation enforces the configured Twitch client ID")
    func testTokenValidationClientIDBinding() async throws {
        let scopes = ["user:read:chat", "user:write:chat"]
        let matching = try JSONSerialization.data(withJSONObject: [
            "client_id": "expected", "scopes": scopes,
        ])
        let mismatch = try JSONSerialization.data(withJSONObject: [
            "client_id": "different", "scopes": scopes,
        ])
        let missing = try JSONSerialization.data(withJSONObject: ["scopes": scopes])

        let matchingResult = await validateToken(
            status: 200, body: matching, expectedClientID: "expected")
        let mismatchResult = await validateToken(
            status: 200, body: mismatch, expectedClientID: "expected")
        let missingResult = await validateToken(
            status: 200, body: missing, expectedClientID: "expected")
        #expect(matchingResult == .valid)
        #expect(mismatchResult == .invalid)
        #expect(missingResult == .temporarilyUnavailable)
    }

    private func validateToken(
        status: Int,
        body: Data,
        requiredScopes: [String] = ["user:read:chat", "user:write:chat"],
        expectedClientID: String? = nil
    ) async -> TwitchChatService.TokenValidationResult {
        handlerStore.handler = { request in
            (MockURLProtocol.httpResponse(for: request, status: status), body)
        }
        defer { handlerStore.handler = nil }
        let client = HTTPClient(session: MockURLProtocol.makeSession(handlerStore: handlerStore))
        let service = TwitchChatService()
        return await service.validateToken(
            "stored-token",
            requiredScopes: requiredScopes,
            expectedClientID: expectedClientID,
            http: client)
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

    /// Builds a `ChatMessage` carrying only the named badge sets.
    private func message(withBadgeSets sets: [String]) -> TwitchChatService.ChatMessage {
        TwitchChatService.ChatMessage(
            messageID: "m", username: "u", userID: "1", message: "!sr x",
            channel: "c",
            badges: sets.map { .init(setID: $0, id: "1", info: "") },
            reply: nil
        )
    }

    @Test("Founder badge counts as subscriber for the request gate")
    func testFounderBadgeIsSubscriber() async throws {
        let roles = message(withBadgeSets: ["founder"]).roles
        #expect(roles.isSubscriber)
        #expect(!roles.isModerator)
        #expect(!roles.isBroadcaster)
        #expect(!roles.isVIP)
    }

    @Test("Subscriber badge counts as subscriber")
    func testSubscriberBadgeIsSubscriber() async throws {
        #expect(message(withBadgeSets: ["subscriber"]).roles.isSubscriber)
    }

    @Test("Each badge set maps to its own role")
    func testRolesMapEachBadge() async throws {
        #expect(message(withBadgeSets: ["moderator"]).roles.isModerator)
        #expect(message(withBadgeSets: ["broadcaster"]).roles.isBroadcaster)
        #expect(message(withBadgeSets: ["vip"]).roles.isVIP)
    }

    @Test("No badges means no roles")
    func testNoBadgesNoRoles() async throws {
        let roles = message(withBadgeSets: []).roles
        #expect(!roles.isModerator && !roles.isBroadcaster && !roles.isSubscriber && !roles.isVIP)
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

        // Attempts strictly increase by 1; never reset.
        #expect(observed == Array(1...maxRetries))
        // The loop terminated at exactly the retry limit.
        #expect(attempts == maxRetries)
    }

    // MARK: - Runtime Lifecycle / Retry Classification

    @Test("Only transient chat-send failures enter the retry queue")
    func testChatSendRetryDisposition() {
        #expect(!TwitchChatService.shouldRetryChatSend(.sent))
        #expect(TwitchChatService.shouldRetryChatSend(.retryableFailure))
        #expect(!TwitchChatService.shouldRetryChatSend(.permanentFailure))
    }

    @Test("Helix status classification separates auth, transient, and permanent failures")
    func testHelixResponseDisposition() {
        #expect(TwitchChatService.helixResponseDisposition(for: 200) == .success)
        #expect(TwitchChatService.helixResponseDisposition(for: 204) == .success)
        #expect(TwitchChatService.helixResponseDisposition(for: 401) == .authenticationFailure)
        #expect(TwitchChatService.helixResponseDisposition(for: 403) == .permanentFailure)

        for status in [408, 425, 429, 500, 503, 599] {
            #expect(TwitchChatService.helixResponseDisposition(for: status) == .retryableFailure)
        }
        for status in [300, 400, 404, 409, 422] {
            #expect(TwitchChatService.helixResponseDisposition(for: status) == .permanentFailure)
        }
    }

    @Test("Only a second 401 after token refresh requires re-authentication")
    func testRefreshedReconnectFailureDisposition() {
        #expect(TwitchChatService.refreshedReconnectFailureDisposition(
            for: TwitchChatService.ConnectionError.authenticationFailed
        ) == .authenticationFailure)
        #expect(TwitchChatService.refreshedReconnectFailureDisposition(
            for: CancellationError()
        ) == .cancelled)
        #expect(TwitchChatService.refreshedReconnectFailureDisposition(
            for: TwitchChatService.ConnectionError.networkError("offline")
        ) == .retryableFailure)
        #expect(TwitchChatService.refreshedReconnectFailureDisposition(
            for: TwitchChatService.ConnectionError.invalidCredentials
        ) == .retryableFailure)
    }

    @Test("Reconnect attempts advance to the cap and never wrap")
    func testReconnectAttemptCap() {
        let maximum = AppConstants.Twitch.maxReconnectionAttempts
        var attempts = 0
        for expected in 1...maximum {
            let next = TwitchChatService.nextReconnectAttempt(
                after: attempts,
                maximum: maximum)
            #expect(next == expected)
            attempts = next ?? attempts
        }
        #expect(TwitchChatService.nextReconnectAttempt(after: attempts, maximum: maximum) == nil)
        #expect(TwitchChatService.nextReconnectAttempt(after: -1, maximum: maximum) == nil)
    }

    @Test("First non-whitespace character must be an exclamation for command dispatch")
    func testPotentialCommandPrefilter() {
        #expect(TwitchChatService.isPotentialCommand("!song"))
        #expect(TwitchChatService.isPotentialCommand("!custom argument"))
        #expect(TwitchChatService.isPotentialCommand("  !song"))
        #expect(TwitchChatService.isPotentialCommand("\t!song"))
        #expect(!TwitchChatService.isPotentialCommand("hello chat"))
        #expect(!TwitchChatService.isPotentialCommand("   "))
        #expect(!TwitchChatService.isPotentialCommand(""))
    }

    @Test("Inbound frames reuse one keepalive watchdog task")
    func testKeepaliveResetDoesNotRecreateTask() async {
        let service = TwitchChatService()
        await service.armKeepaliveWatchdog(deadlineSeconds: 60)
        for _ in 0..<100 {
            await service.resetKeepaliveWatchdog()
        }

        #expect(await service.keepaliveWatchdogTaskStarts == 1)
        await service.disconnectFromEventSub()
        #expect(await service.lastKeepaliveActivity == nil)
    }

    @Test("A stale keepalive expiry cannot tear down a rearmed session")
    func testStaleKeepaliveExpiryAfterRearmIsIgnored() async {
        let service = TwitchChatService()
        await service.armKeepaliveWatchdog(deadlineSeconds: 60)
        let staleGeneration = await service.keepaliveGeneration

        await service.disconnectFromEventSub()
        await service.armKeepaliveWatchdog(deadlineSeconds: 60)
        let activeGeneration = await service.keepaliveGeneration

        let staleTaskShouldStop = await service.handleKeepaliveExpiry(
            generation: staleGeneration,
            at: ContinuousClock().now.advanced(by: .seconds(3_600)))

        #expect(staleTaskShouldStop)
        #expect(await service.keepaliveGeneration == activeGeneration)
        #expect(await service.lastKeepaliveActivity != nil)
        await service.disconnectFromEventSub()
    }

    @Test("Leaving invalidates an in-flight connection intent")
    func testLeaveInvalidatesConnectionAttempt() async {
        let service = TwitchChatService()
        let generation = await service.beginConnectionAttempt()
        #expect(await service.connectionAttemptIsCurrent(generation))

        await service.leaveChannel()

        #expect(!(await service.connectionAttemptIsCurrent(generation)))
    }

    @Test("A new logical connection attempt retires the previous transport")
    func testNewConnectionAttemptRetiresPreviousTransport() async {
        let service = TwitchChatService(
            eventSubWebSocketFactory: { url in
                URLSession(configuration: .ephemeral).webSocketTask(with: url)
            },
            eventSubWebSocketResume: { _ in }
        )

        await service.connectToEventSub()
        #expect(await service.hasEventSubTransportForTesting)

        _ = await service.beginConnectionAttempt()

        #expect(!(await service.hasEventSubTransportForTesting))
    }

    @Test("session_welcome is the event that resets reconnect attempts")
    func testSessionWelcomeResetsReconnectAttempts() async throws {
        let service = TwitchChatService()
        await service.configureReconnectStateForTesting(attempts: 3, migrating: true)

        let message: [String: Any] = [
            "metadata": [
                "message_type": "session_welcome",
                "message_id": "welcome-reset-test",
                "message_timestamp": ISO8601DateFormatter().string(from: Date()),
            ],
            "payload": [
                "session": [
                    "id": "test-session",
                    "keepalive_timeout_seconds": 60,
                ]
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: message)
        let text = String(decoding: data, as: UTF8.self)
        await service.handleWebSocketMessage(text)

        #expect(await service.reconnectionAttempts == 0)
        await service.disconnectFromEventSub()
    }

    @Test("Network loss broadcasts disconnected to stream consumers")
    func testNetworkLossBroadcastsDisconnected() async {
        let service = TwitchChatService()
        let stream = service.connectionStateChanges()
        let received = Task {
            await collectFirst(1, from: stream)?.first
        }

        await service.setConnected(true)
        await service.handleNetworkReachabilityChange(false)

        let disconnected = await received.value
        #expect(disconnected == false)
    }

    @Test("Network loss cancels a delayed reconnect")
    func testNetworkLossCancelsScheduledReconnect() async {
        let service = TwitchChatService()
        await service.configureReconnectCredentialsForTesting()
        await service.scheduleReconnect()
        #expect(await service.hasScheduledReconnectForTesting)

        await service.handleNetworkReachabilityChange(false)

        #expect(!(await service.hasScheduledReconnectForTesting))
    }

    @Test("Accepted network recovery starts a fresh bounded attempt cycle")
    func testNetworkRecoveryResetsExhaustedAttempts() async {
        let service = TwitchChatService()
        await service.configureNetworkRecoveryForTesting(
            attempts: AppConstants.Twitch.maxReconnectionAttempts)

        await service.handleNetworkReachabilityChange(true)

        #expect(await service.reconnectionAttempts == 0)
        #expect(await service.networkReconnectCycles == 1)
    }

    @Test("Leaving cancels and clears the pending message retry lifecycle")
    func testLeaveClearsPendingMessageRetry() async {
        let service = TwitchChatService()
        handlerStore.handler = { request in
            (MockURLProtocol.httpResponse(for: request, status: 503), Data())
        }
        defer { handlerStore.handler = nil }
        let networkedService = TwitchChatService(
            helixHTTPClient: HTTPClient(session: MockURLProtocol.makeSession(handlerStore: handlerStore)))
        _ = await networkedService.configureChatSendForTesting(broadcasterID: "channel")

        await networkedService.sendMessage("queued reply")
        #expect(await networkedService.hasPendingMessageRetry)

        await networkedService.leaveChannel()
        #expect(!(await networkedService.hasPendingMessageRetry))
        #expect(await networkedService.pendingMessageCount == 0)
    }

    @Test("A suspended command does not block EventSub and reconnect cancels it")
    func testTrackedCommandDoesNotBlockReceiveAndCancelsOnReconnect() async {
        let service = TwitchChatService()
        let gate = SuspendedCommandGate()
        service.commandDispatcher.register(SuspendedTestCommand(gate: gate))
        let generation = await service.configureCommandSessionForTesting(
            broadcasterID: "channel-1")

        await service.handleEventSubMessage(Self.chatEvent(
            id: "command-message", text: "!suspend", broadcasterID: "channel-1"))

        #expect(await waitUntil { await gate.started })
        #expect(await service.activeCommandTaskCount == 1)

        // A later event must be parsed and yielded while the command remains
        // suspended; the WebSocket receive task must not await command work.
        await service.handleEventSubMessage(Self.chatEvent(
            id: "later-message", text: "still responsive", broadcasterID: "channel-1"))
        let messages = await collectFirst(2, from: service.chatMessages)
        #expect(messages?.map(\.messageID) == ["command-message", "later-message"])

        _ = await service.beginConnectionAttempt()
        #expect(await waitUntil { await gate.wasCancelled })
        #expect(await waitUntil { await service.activeCommandTaskCount == 0 })
        #expect(!(await service.commandReplyIsCurrent(
            generation: generation, broadcasterID: "channel-1")))
        #expect(await service.pendingMessageCount == 0)
    }

    @Test("Duplicate command IDs start only one asynchronous command")
    func testDuplicateCommandIDStartsOneTask() async {
        let service = TwitchChatService()
        let gate = SuspendedCommandGate()
        service.commandDispatcher.register(SuspendedTestCommand(gate: gate))
        _ = await service.configureCommandSessionForTesting(
            broadcasterID: "channel-1")

        let event = Self.chatEvent(
            id: "duplicate-command",
            text: "!suspend",
            broadcasterID: "channel-1")
        await service.handleEventSubMessage(event)
        #expect(await waitUntil { await gate.started })

        await service.handleEventSubMessage(event)
        await Task.yield()
        #expect(await service.activeCommandTaskCount == 1)

        _ = await service.beginConnectionAttempt()
        #expect(await waitUntil { await gate.wasCancelled })
    }

    @Test("A command seen while disabled cannot execute from delayed redelivery")
    func testDisabledCommandIDIsStillReserved() async {
        let service = TwitchChatService()
        let gate = SuspendedCommandGate()
        service.commandDispatcher.register(SuspendedTestCommand(gate: gate))
        _ = await service.configureCommandSessionForTesting(
            broadcasterID: "channel-1")
        let event = Self.chatEvent(
            id: "disabled-command",
            text: "!suspend",
            broadcasterID: "channel-1")

        await service.setCommandsEnabled(false)
        await service.handleEventSubMessage(event)
        await service.setCommandsEnabled(true)
        await service.handleEventSubMessage(event)
        await Task.yield()

        #expect(!(await gate.started))
        #expect(await service.activeCommandTaskCount == 0)
    }

    private static func chatEvent(
        id: String,
        text: String,
        broadcasterID: String
    ) -> [String: Any] {
        [
            "event": [
                "message_id": id,
                "chatter_user_name": "Viewer",
                "chatter_user_login": "viewer",
                "chatter_user_id": "viewer-1",
                "broadcaster_user_id": broadcasterID,
                "message": ["text": text],
                "badges": [],
            ]
        ]
    }

}

private extension TwitchChatService {
    var hasEventSubTransportForTesting: Bool {
        webSocketTask != nil || migrationSourceWebSocketTask != nil
    }

    var activeRedemptionPipelineCountForTesting: Int {
        redemptionTasks.count
    }

    func installRedemptionPipelineForTesting(
        item: TwitchRedemptionResolutionOutbox.Item,
        operation: @escaping @Sendable () async -> Void
    ) {
        redemptionTasks[item.id] = Task { [weak self] in
            await operation()
            await self?.finishRedemptionPipelineForTesting(item.id)
        }
    }

    func finishRedemptionPipelineForTesting(_ id: UUID) {
        redemptionTasks[id] = nil
    }

    func configureChatSendForTesting(broadcasterID: String) -> UInt64 {
        let generation = beginConnectionAttempt()
        self.broadcasterID = broadcasterID
        botID = "bot"
        oauthToken = "token"
        clientID = "client"
        reconnectChannelName = broadcasterID
        reconnectToken = "token"
        reconnectClientID = "client"
        return generation
    }

    func configureBroadcasterRedemptionCredentialsForTesting(
        broadcasterID: String
    ) {
        _ = beginConnectionAttempt()
        self.broadcasterID = broadcasterID
        botID = broadcasterID
        oauthToken = "token"
        clientID = "client"
    }

    func awaitPaidRedemptionTasksForTesting() async {
        let tasks = Array(paidRedemptionTasks.values)
        for task in tasks {
            await task.value
        }
    }

    func awaitRedemptionPipelinesForTesting() async {
        let tasks = Array(redemptionTasks.values)
        for task in tasks {
            await task.value
        }
    }

    func switchBroadcasterForTesting(to broadcasterID: String) {
        self.broadcasterID = broadcasterID
        reconnectChannelName = broadcasterID
    }

    func configureReconnectStateForTesting(attempts: Int, migrating: Bool) {
        reconnectionAttempts = attempts
        isMigratingSession = migrating
    }

    func configureRetryChannelForTesting() {
        reconnectChannelName = "test-channel"
    }

    func configureCommandSessionForTesting(broadcasterID: String) -> UInt64 {
        let generation = beginConnectionAttempt()
        self.broadcasterID = broadcasterID
        reconnectChannelName = broadcasterID
        return generation
    }

    func configureReconnectCredentialsForTesting() {
        reconnectChannelName = "test-channel"
        reconnectToken = "test-token"
        reconnectClientID = "test-client"
    }

    var hasScheduledReconnectForTesting: Bool {
        reconnectTask != nil
    }

    func configureNetworkRecoveryForTesting(attempts: Int) {
        reconnectionAttempts = attempts
        networkReconnectCycles = 0
        isNetworkReachable = false
        lastNetworkReconnectTime = Date().timeIntervalSince1970
    }
}

private actor SuspendedCommandGate {
    private(set) var started = false
    private(set) var wasCancelled = false

    func waitForCancellation() async {
        started = true
        do {
            try await Task.sleep(for: .seconds(3_600))
        } catch {
            wasCancelled = true
        }
    }
}

private actor DeterministicAsyncGate {
    private(set) var suspended = false
    private var released = false
    private var resumeWaiters: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        suspended = true
        guard !released else { return }
        await withCheckedContinuation { continuation in
            resumeWaiters.append(continuation)
        }
    }

    func resume() {
        released = true
        resumeWaiters.forEach { $0.resume() }
        resumeWaiters.removeAll()
    }
}

@MainActor
private final class SuspendedTestCommand: AsyncBotCommand {
    let triggers = ["!suspend"]
    let description = "Suspends until its owning session is canceled"
    let globalCooldown: TimeInterval = 0
    let userCooldown: TimeInterval = 0

    private let gate: SuspendedCommandGate

    init(gate: SuspendedCommandGate) {
        self.gate = gate
    }

    func execute(message: String, context: BotCommandContext) async -> String? {
        await gate.waitForCancellation()
        return "stale reply"
    }
}
