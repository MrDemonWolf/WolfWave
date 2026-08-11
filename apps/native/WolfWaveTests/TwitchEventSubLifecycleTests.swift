//
//  TwitchEventSubLifecycleTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-06.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Testing
import Foundation
@testable import WolfWave

/// Covers the EventSub lifecycle's pure decision helpers plus deterministic
/// injected-socket orchestration for reconnect migration, overlap deduplication,
/// and watchdog ownership. No test opens a live Twitch connection.
@Suite("Twitch EventSub Lifecycle Helpers")
struct TwitchEventSubLifecycleTests {

    // MARK: - reconnectURL

    private func reconnectMessage(url: Any?) -> [String: Any] {
        var session: [String: Any] = ["id": "abc"]
        if let url { session["reconnect_url"] = url }
        return ["payload": ["session": session]]
    }

    @Test("reconnectURL extracts a valid wss reconnect_url")
    func testReconnectURLValid() {
        let json = reconnectMessage(
            url: "wss://eventsub.wss.twitch.tv/ws?challenge=xyz")
        #expect(
            TwitchChatService.reconnectURL(from: json)
                == "wss://eventsub.wss.twitch.tv/ws?challenge=xyz")
    }

    @Test("reconnectURL rejects insecure ws scheme")
    func testReconnectURLWsScheme() {
        let json = reconnectMessage(url: "ws://localhost:8080/ws")
        #expect(TwitchChatService.reconnectURL(from: json) == nil)
    }

    @Test("reconnectURL trims surrounding whitespace")
    func testReconnectURLTrims() {
        let json = reconnectMessage(url: "  wss://eventsub.wss.twitch.tv/ws  ")
        #expect(
            TwitchChatService.reconnectURL(from: json)
                == "wss://eventsub.wss.twitch.tv/ws")
    }

    @Test("reconnectURL returns nil when field is missing")
    func testReconnectURLMissing() {
        #expect(TwitchChatService.reconnectURL(from: reconnectMessage(url: nil)) == nil)
    }

    @Test("reconnectURL returns nil for empty string")
    func testReconnectURLEmpty() {
        #expect(TwitchChatService.reconnectURL(from: reconnectMessage(url: "   ")) == nil)
    }

    @Test("reconnectURL rejects non-websocket schemes")
    func testReconnectURLRejectsHTTP() {
        #expect(
            TwitchChatService.reconnectURL(from: reconnectMessage(url: "https://twitch.tv")) == nil)
    }

    @Test("reconnectURL rejects a host-less URL")
    func testReconnectURLRejectsHostless() {
        #expect(TwitchChatService.reconnectURL(from: reconnectMessage(url: "wss://")) == nil)
    }

    @Test("reconnectURL returns nil when payload is absent")
    func testReconnectURLNoPayload() {
        #expect(TwitchChatService.reconnectURL(from: ["metadata": ["x": 1]]) == nil)
    }

    // MARK: - keepaliveTimeoutSeconds

    private func welcome(keepalive: Any?) -> [String: Any] {
        var session: [String: Any] = ["id": "abc"]
        if let keepalive { session["keepalive_timeout_seconds"] = keepalive }
        return ["payload": ["session": session]]
    }

    @Test("keepaliveTimeoutSeconds reads an integer value")
    func testKeepaliveInt() {
        #expect(TwitchChatService.keepaliveTimeoutSeconds(from: welcome(keepalive: 30)) == 30)
    }

    @Test("keepaliveTimeoutSeconds tolerates a numeric string")
    func testKeepaliveString() {
        #expect(TwitchChatService.keepaliveTimeoutSeconds(from: welcome(keepalive: "45")) == 45)
    }

    @Test("keepaliveTimeoutSeconds returns nil when missing")
    func testKeepaliveMissing() {
        #expect(TwitchChatService.keepaliveTimeoutSeconds(from: welcome(keepalive: nil)) == nil)
    }

    @Test("keepaliveTimeoutSeconds returns nil for non-positive values")
    func testKeepaliveNonPositive() {
        #expect(TwitchChatService.keepaliveTimeoutSeconds(from: welcome(keepalive: 0)) == nil)
        #expect(TwitchChatService.keepaliveTimeoutSeconds(from: welcome(keepalive: -5)) == nil)
    }

    @Test("keepaliveTimeoutSeconds accepts Twitch protocol bounds")
    func testKeepaliveProtocolBounds() {
        #expect(TwitchChatService.keepaliveTimeoutSeconds(from: welcome(keepalive: 10)) == 10)
        #expect(TwitchChatService.keepaliveTimeoutSeconds(from: welcome(keepalive: 600)) == 600)
    }

    @Test("keepaliveTimeoutSeconds rejects non-finite and out-of-range values")
    func testKeepaliveRejectsUnsafeValues() {
        let unsafeValues: [Any] = [
            Int.max, Double.infinity, Double.nan, 1e308,
            "1e309", "nan", 10.5, "10.5", 9, 601,
        ]
        for value in unsafeValues {
            #expect(TwitchChatService.keepaliveTimeoutSeconds(
                from: welcome(keepalive: value)) == nil)
        }
    }

    // MARK: - keepaliveDeadline

    @Test("keepaliveDeadline sums timeout and grace")
    func testKeepaliveDeadlineSum() {
        #expect(
            TwitchChatService.keepaliveDeadline(timeoutSeconds: 10, grace: 10) == 20)
    }

    @Test("keepaliveDeadline replaces invalid timeout with the protocol default")
    func testKeepaliveDeadlineClamp() {
        #expect(
            TwitchChatService.keepaliveDeadline(timeoutSeconds: -100, grace: -100) == 10)
    }

    @Test("keepaliveDeadline ignores negative grace but keeps positive timeout")
    func testKeepaliveDeadlineNegativeGrace() {
        #expect(
            TwitchChatService.keepaliveDeadline(timeoutSeconds: 30, grace: -5) == 30)
    }

    @Test("keepaliveDeadline rejects non-finite inputs and caps excessive grace")
    func testKeepaliveDeadlineBounds() {
        #expect(TwitchChatService.keepaliveDeadline(
            timeoutSeconds: .infinity, grace: 10) == 20)
        #expect(TwitchChatService.keepaliveDeadline(
            timeoutSeconds: .nan, grace: 10) == 20)
        #expect(TwitchChatService.keepaliveDeadline(
            timeoutSeconds: 30, grace: .infinity) == 30)
        #expect(TwitchChatService.keepaliveDeadline(
            timeoutSeconds: 600, grace: 1e308) == 610)
    }

    @MainActor
    @Test("watchdog arming normalizes unsafe deadlines before constructing Duration")
    func testWatchdogArmingNormalizesUnsafeDeadline() async {
        let service = TwitchChatService()
        await service.armKeepaliveWatchdog(deadlineSeconds: .infinity)
        #expect(await service.keepaliveDeadlineSeconds == 20)
        await service.cancelKeepaliveWatchdog()
    }

    // MARK: - revocationDisposition

    @Test("409 subscription ID parser accepts Twitch and regular data envelopes")
    func testConflictingSubscriptionIDParser() {
        #expect(
            TwitchChatService.conflictingSubscriptionID(
                from: Data(#"{"id":"top-level"}"#.utf8)) == "top-level")
        #expect(
            TwitchChatService.conflictingSubscriptionID(
                from: Data(#"{"data":[{"id":"enveloped"}]}"#.utf8)) == "enveloped")
        #expect(
            TwitchChatService.conflictingSubscriptionID(
                from: Data(#"{"error":"Conflict"}"#.utf8)) == nil)
    }

    @Test("revocationDisposition exhaustively maps documented terminal and transient statuses")
    func testRevocationStatusTable() {
        let cases: [(status: String, expected: TwitchChatService.RevocationDisposition)] = [
            ("authorization_revoked", .reauth),
            ("user_removed", .accountUnavailable),
            ("version_removed", .clientUpdateRequired),
            ("moderator_removed", .permissionLost),
            ("chat_user_banned", .permissionLost),
            ("beta_maintenance", .reconnect),
            ("websocket_disconnected", .reconnect),
            ("websocket_failed_ping_pong", .reconnect),
            ("websocket_received_inbound_traffic", .reconnect),
            ("websocket_connection_unused", .reconnect),
            ("websocket_internal_error", .reconnect),
            ("websocket_network_timeout", .reconnect),
            ("websocket_network_error", .reconnect),
            ("websocket_failed_to_reconnect", .reconnect),
        ]

        for testCase in cases {
            #expect(
                TwitchChatService.revocationDisposition(
                    type: "channel.chat.message",
                    status: testCase.status
                ) == testCase.expected,
                "Unexpected disposition for \(testCase.status)"
            )
        }
    }

    @Test("revocationDisposition ignores unknown statuses")
    func testRevocationIgnore() {
        #expect(
            TwitchChatService.revocationDisposition(
                type: "channel.chat.message", status: "something_else") == .ignore)
        #expect(
            TwitchChatService.revocationDisposition(type: "", status: "") == .ignore)
    }

    @MainActor
    @Test("Malformed EventSub timestamps are rejected before dedup or routing")
    func testMalformedTimestampIsRejected() async throws {
        let service = TwitchChatService()

        try await service.handleWebSocketMessage(
            eventSubEnvelope(
                type: "session_keepalive",
                id: "malformed-timestamp",
                timestamp: "not-rfc3339",
                payload: [:]))

        #expect(await service.eventSubDedupCountForTesting() == 0)
    }

    @MainActor
    @Test("Nanosecond RFC3339 EventSub timestamps are accepted")
    func testNanosecondTimestampIsAccepted() async throws {
        let service = TwitchChatService()
        let wholeSeconds = ISO8601DateFormatter().string(from: Date())
        let timestamp = String(wholeSeconds.dropLast()) + ".123456789Z"

        try await service.handleWebSocketMessage(
            eventSubEnvelope(
                type: "session_keepalive",
                id: "nanosecond-timestamp",
                timestamp: timestamp,
                payload: [:]))

        #expect(await service.eventSubDedupCountForTesting() == 1)
    }

    @MainActor
    @Test("session_reconnect retains both receive loops until target welcome")
    func testDualSocketMigrationHandoffAndOverlapDedup() async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let source = session.webSocketTask(
            with: try #require(URL(string: "wss://eventsub.wss.twitch.tv/source")))
        let target = session.webSocketTask(
            with: try #require(URL(string: "wss://eventsub.wss.twitch.tv/target")))
        let openedURLs = ThreadSafeBox<[URL]>([])

        let service = TwitchChatService(
            eventSubWebSocketFactory: { url in
                openedURLs.mutate { $0.append(url) }
                return target
            },
            eventSubWebSocketResume: { _ in },
            eventSubWebSocketReceive: { _ in
                try await Task.sleep(for: .seconds(3_600))
                throw CancellationError()
            }
        )
        let sourceContext = await service.installEventSubSourceForTesting(source)

        try await service.handleWebSocketMessage(
            eventSubEnvelope(
                type: "session_reconnect",
                id: "reconnect-message",
                payload: [
                    "session": [
                        "id": "source-session",
                        "reconnect_url": "wss://eventsub.wss.twitch.tv/target",
                    ]
                ]
            ),
            receiveContext: sourceContext
        )

        let migrating = await service.eventSubMigrationSnapshotForTesting(
            source: source,
            target: target
        )
        #expect(migrating.isMigrating)
        #expect(migrating.sourceRetained)
        #expect(migrating.sourceReceiveRetained)
        #expect(migrating.targetIsCurrent)
        #expect(source.state == .suspended)
        #expect(openedURLs.value.map(\.absoluteString) == [
            "wss://eventsub.wss.twitch.tv/target"
        ])

        let targetContext = await service.eventSubContextForTesting(target)
        let overlappingNotification = try eventSubEnvelope(
            type: "notification",
            id: "overlapping-delivery",
            payload: [
                "subscription": ["type": AppConstants.Twitch.eventSubChatMessage],
                "event": [
                    "message_id": "chat-message",
                    "chatter_user_name": "Viewer",
                    "chatter_user_id": "viewer-id",
                    "broadcaster_user_id": "broadcaster-id",
                    "message": ["text": "hello"],
                    "badges": [],
                ],
            ]
        )
        await service.handleWebSocketMessage(
            overlappingNotification,
            receiveContext: sourceContext
        )
        await service.handleWebSocketMessage(
            overlappingNotification,
            receiveContext: targetContext
        )
        let delivered = try await nextChatMessage(from: service.chatMessages)
        #expect(delivered?.messageID == "chat-message")
        #expect(await service.eventSubDedupCountForTesting() == 2)

        try await service.handleWebSocketMessage(
            eventSubEnvelope(
                type: "session_welcome",
                id: "target-welcome",
                payload: [
                    "session": [
                        "id": "target-session",
                        "keepalive_timeout_seconds": 10,
                    ]
                ]
            ),
            receiveContext: targetContext
        )

        let completed = await service.eventSubMigrationSnapshotForTesting(
            source: source,
            target: target
        )
        #expect(!completed.isMigrating)
        #expect(!completed.sourceRetained)
        #expect(!completed.sourceReceiveRetained)
        #expect(completed.targetIsCurrent)
        #expect(completed.targetIsWelcomed)
        #expect(completed.isConnected)
        #expect(completed.sessionID == "target-session")

        await service.disconnectFromEventSub()
    }

    @MainActor
    @Test("migration target welcome re-arms a shorter keepalive watchdog")
    func testMigrationTargetWelcomeRearmsShorterKeepaliveWatchdog() async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let source = session.webSocketTask(
            with: try #require(URL(string: "wss://eventsub.wss.twitch.tv/source-long")))
        let target = session.webSocketTask(
            with: try #require(URL(string: "wss://eventsub.wss.twitch.tv/target-short")))

        let service = TwitchChatService(
            eventSubWebSocketFactory: { _ in target },
            eventSubWebSocketResume: { _ in },
            eventSubWebSocketReceive: { _ in
                try await Task.sleep(for: .seconds(3_600))
                throw CancellationError()
            }
        )
        let sourceContext = await service.installEventSubSourceForTesting(source)
        let targetTimeout: TimeInterval = 10
        let targetDeadline = TwitchChatService.keepaliveDeadline(
            timeoutSeconds: targetTimeout,
            grace: AppConstants.Twitch.keepaliveGraceSeconds
        )
        let sourceDeadline = TwitchChatService.keepaliveDeadline(
            timeoutSeconds: 600,
            grace: AppConstants.Twitch.keepaliveGraceSeconds)
        await service.armKeepaliveWatchdog(deadlineSeconds: sourceDeadline)
        let sourceGeneration = await service.keepaliveGeneration
        let sourceTaskStarts = await service.keepaliveWatchdogTaskStarts

        let reconnect = try eventSubEnvelope(
            type: "session_reconnect",
            id: "long-to-short-reconnect",
            payload: [
                "session": [
                    "id": "source-long-session",
                    "reconnect_url": "wss://eventsub.wss.twitch.tv/target-short",
                ]
            ]
        )
        await service.handleWebSocketMessage(
            reconnect,
            receiveContext: sourceContext
        )

        let targetContext = await service.eventSubContextForTesting(target)
        let targetWelcome = try eventSubEnvelope(
            type: "session_welcome",
            id: "short-target-welcome",
            payload: [
                "session": [
                    "id": "target-short-session",
                    "keepalive_timeout_seconds": targetTimeout,
                ]
            ]
        )
        await service.handleWebSocketMessage(
            targetWelcome,
            receiveContext: targetContext
        )

        #expect(targetDeadline < sourceDeadline)
        #expect(await service.keepaliveDeadlineSeconds == targetDeadline)
        #expect(await service.keepaliveGeneration != sourceGeneration)
        #expect(await service.keepaliveWatchdogTaskStarts == sourceTaskStarts + 1)
        #expect(await service.lastKeepaliveActivity != nil)
        let completed = await service.eventSubMigrationSnapshotForTesting(
            source: source,
            target: target
        )
        #expect(!completed.isMigrating)
        #expect(!completed.sourceRetained)
        #expect(completed.targetIsCurrent)
        #expect(completed.targetIsWelcomed)

        await service.disconnectFromEventSub()
    }

    private func eventSubEnvelope(
        type: String,
        id: String,
        timestamp: String? = nil,
        payload: [String: Any]
    ) throws -> String {
        let object: [String: Any] = [
            "metadata": [
                "message_type": type,
                "message_id": id,
                "message_timestamp": timestamp
                    ?? ISO8601DateFormatter().string(from: Date()),
            ],
            "payload": payload,
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        return try #require(String(data: data, encoding: .utf8))
    }
}

private nonisolated enum EventSubLifecycleTestError: Error, Sendable {
    case timedOutWaitingForChatMessage
}

/// Returns the next chat message or throws after a short cancellation-aware
/// deadline so a receive-stream regression fails instead of hanging the suite.
private nonisolated func nextChatMessage(
    from stream: AsyncStream<TwitchChatService.ChatMessage>,
    timeout: Duration = .seconds(1)
) async throws -> TwitchChatService.ChatMessage? {
    try await withThrowingTaskGroup(
        of: TwitchChatService.ChatMessage?.self
    ) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw EventSubLifecycleTestError.timedOutWaitingForChatMessage
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else { return nil }
        return result
    }
}

private nonisolated struct EventSubMigrationSnapshot: Sendable {
    let isMigrating: Bool
    let sourceRetained: Bool
    let sourceReceiveRetained: Bool
    let targetIsCurrent: Bool
    let targetIsWelcomed: Bool
    let isConnected: Bool
    let sessionID: String?
}

private extension TwitchChatService {
    func installEventSubSourceForTesting(
        _ source: URLSessionWebSocketTask
    ) -> EventSubReceiveContext {
        webSocketTask = source
        welcomedWebSocketTask = source
        sessionID = "source-session"
        setConnected(true)
        receiveTask = Task {
            try? await Task.sleep(for: .seconds(3_600))
        }
        return EventSubReceiveContext(
            generation: connectionGeneration,
            webSocketTask: source
        )
    }

    func eventSubContextForTesting(
        _ task: URLSessionWebSocketTask
    ) -> EventSubReceiveContext {
        EventSubReceiveContext(
            generation: connectionGeneration,
            webSocketTask: task
        )
    }

    func eventSubMigrationSnapshotForTesting(
        source: URLSessionWebSocketTask,
        target: URLSessionWebSocketTask
    ) -> EventSubMigrationSnapshot {
        EventSubMigrationSnapshot(
            isMigrating: isMigratingSession,
            sourceRetained: migrationSourceWebSocketTask === source,
            sourceReceiveRetained: migrationSourceReceiveTask != nil,
            targetIsCurrent: webSocketTask === target,
            targetIsWelcomed: welcomedWebSocketTask === target,
            isConnected: isConnected,
            sessionID: sessionID
        )
    }

    func eventSubDedupCountForTesting() -> Int {
        messageDeduplicator.entryCount
    }
}
