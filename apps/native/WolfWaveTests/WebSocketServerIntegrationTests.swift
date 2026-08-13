//
//  WebSocketServerIntegrationTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-03-19.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import XCTest
@testable import WolfWave

// Integration tests for the WebSocket server lifecycle and replay protocol. Each
// case owns an OS-assigned loopback port and gates on observed state changes;
// no timing sleep stands in for a transport assertion.
final class WebSocketServerIntegrationTests: XCTestCase, @unchecked Sendable {

    private static let overlayToken = String(repeating: "a", count: 64)
    private static let controlToken = String(repeating: "b", count: 64)

    private struct Frame: Decodable, Sendable {
        struct DataPayload: Decodable, Sendable {
            let track: String?
            let isPlaying: Bool?
            let items: [QueueItem]?
        }

        struct QueueItem: Decodable, Equatable, Sendable {
            let title: String
            let requesterUsername: String
        }

        let type: String
        let data: DataPayload?
    }

    private enum FrameDecodingError: Error {
        case unsupportedMessage
    }

    // MARK: - Helpers

    /// Waits for predicate to return true for an emitted state/count event.
    /// Returns the consumer task so the caller can cancel it after the wait.
    @discardableResult
    private func observe(
        _ service: WebSocketServerService,
        fulfilling expectation: XCTestExpectation,
        on predicate: @escaping @Sendable (WebSocketServerService.ServerState, Int) -> Bool
    ) -> Task<Void, Never> {
        let stream = service.stateChanges
        return Task.detached {
            for await (state, count) in stream {
                if predicate(state, count) {
                    expectation.fulfill()
                    return
                }
            }
        }
    }

    /// Uses the same authenticated initializer as the app. Keeping the legacy
    /// no-auth initializer out of transport tests makes the handshake part of
    /// every client-facing assertion.
    private func makeService(port: UInt16) -> WebSocketServerService {
        WebSocketServerService(
            port: port,
            overlayToken: Self.overlayToken,
            controlToken: Self.controlToken
        )
    }

    /// Starts a service on an OS-assigned port, awaits `.listening`, and returns
    /// it with the port the kernel handed back.
    ///
    /// Binding `0` is what keeps this suite independent of the machine: a
    /// hardcoded high port sits inside the macOS ephemeral range, so any
    /// unrelated process holding it (a browser's outbound connections, reliably)
    /// would fail the bind and the test with it.
    private func startListeningService() async throws -> (WebSocketServerService, UInt16) {
        let service = makeService(port: 0)
        let listening = expectation(description: "server listening")
        let observer = observe(service, fulfilling: listening) { state, _ in
            state == .listening
        }
        await service.setEnabled(true)
        await fulfillment(of: [listening], timeout: 5)
        observer.cancel()

        // Hoisted out of XCTUnwrap: its argument is a nonisolated autoclosure,
        // which cannot await an actor-isolated property.
        let bound = await service.boundPort
        let port = try XCTUnwrap(bound, "A listening server must report the port it bound")
        return (service, port)
    }

    private func makeClient(port: UInt16) throws -> (URLSession, URLSessionWebSocketTask) {
        let url = try XCTUnwrap(URL(string: "ws://127.0.0.1:\(port)/"))
        let session = URLSession(configuration: .ephemeral)
        let subprotocol = WebSocketAuthToken.expectedSubprotocol(
            for: Self.overlayToken,
            role: .overlay
        )
        let task = session.webSocketTask(with: url, protocols: [subprotocol])
        return (session, task)
    }

    private nonisolated static func decode(_ message: URLSessionWebSocketTask.Message) throws -> Frame {
        let data: Data
        switch message {
        case .string(let text):
            data = Data(text.utf8)
        case .data(let messageData):
            data = messageData
        @unknown default:
            throw FrameDecodingError.unsupportedMessage
        }
        return try JSONDecoder().decode(Frame.self, from: data)
    }

    /// Receives until the requested frame type arrives, then runs field-level
    /// assertions. Transport and decoding errors fail and fulfill immediately so
    /// the real cause is not hidden behind the outer bounded timeout.
    private nonisolated static func receiveFrame(
        type: String,
        from task: URLSessionWebSocketTask,
        fulfilling expectation: XCTestExpectation,
        file: StaticString = #filePath,
        line: UInt = #line,
        asserting assertions: @escaping @Sendable (Frame) -> Void
    ) {
        task.receive { result in
            switch result {
            case .success(let message):
                do {
                    let frame = try decode(message)
                    if frame.type == type {
                        assertions(frame)
                        expectation.fulfill()
                    } else {
                        receiveFrame(
                            type: type,
                            from: task,
                            fulfilling: expectation,
                            file: file,
                            line: line,
                            asserting: assertions
                        )
                    }
                } catch {
                    XCTFail("Failed to decode WebSocket frame: \(error)", file: file, line: line)
                    expectation.fulfill()
                }
            case .failure(let error):
                XCTFail("WebSocket receive failed: \(error)", file: file, line: line)
                expectation.fulfill()
            }
        }
    }

    private func close(
        session: URLSession,
        task: URLSessionWebSocketTask
    ) {
        task.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
    }

    // MARK: - Server Lifecycle Tests

    func testServerRestartCycle() async {
        let service = makeService(port: 0)
        let firstListen = expectation(description: "first listen")
        let stopped = expectation(description: "stopped")
        let secondListen = expectation(description: "second listen")

        let firstObserver = observe(service, fulfilling: firstListen) { state, _ in
            state == .listening
        }
        await service.setEnabled(true)
        await fulfillment(of: [firstListen], timeout: 5)
        firstObserver.cancel()

        let stopObserver = observe(service, fulfilling: stopped) { state, _ in
            state == .stopped
        }
        await service.setEnabled(false)
        await fulfillment(of: [stopped], timeout: 5)
        stopObserver.cancel()

        let secondObserver = observe(service, fulfilling: secondListen) { state, _ in
            state == .listening
        }
        await service.setEnabled(true)
        await fulfillment(of: [secondListen], timeout: 15)
        secondObserver.cancel()

        await service.setEnabled(false)
    }

    // MARK: - Port Conflict Tests

    func testTwoServersOnSamePortHandledGracefully() async throws {
        // Let the kernel pick the contested port, then aim the second server at
        // it. The conflict is guaranteed because service1 already holds it, and
        // no unrelated process can be squatting on a port we were just given.
        let (service1, port) = try await startListeningService()
        let service2 = makeService(port: port)

        let conflict = expectation(description: "service2 reports port conflict")
        let secondObserver = observe(service2, fulfilling: conflict) { state, _ in
            state == .error
        }
        await service2.setEnabled(true)
        await fulfillment(of: [conflict], timeout: 5)
        secondObserver.cancel()

        await service1.setEnabled(false)
        await service2.setEnabled(false)
    }

    // MARK: - Replay-on-Connect Tests

    /// A freshly connected client should immediately receive the last known
    /// now-playing frame so an OBS browser source does not stay blank after reload.
    func testFreshConnectionReceivesLastKnownState() async throws {
        let (service, port) = try await startListeningService()
        let (session, task) = try makeClient(port: port)

        await service.updateNowPlaying(
            track: "Replay Test Track",
            artist: "Test Artist",
            album: "Test Album",
            duration: 200,
            elapsed: 12,
            artworkURL: nil
        )

        let received = expectation(description: "received now_playing replay")
        task.resume()
        Self.receiveFrame(type: "now_playing", from: task, fulfilling: received) { frame in
            XCTAssertEqual(frame.data?.track, "Replay Test Track")
            XCTAssertEqual(frame.data?.isPlaying, true)
        }
        await fulfillment(of: [received], timeout: 5)

        close(session: session, task: task)
        await service.setEnabled(false)
    }

    /// A paused update must broadcast isPlaying=false so the overlay renders the
    /// paused affordance rather than treating the track as live.
    func testUpdateNowPlaying_isPaused_broadcastsNotPlaying() async throws {
        let (service, port) = try await startListeningService()
        let (session, task) = try makeClient(port: port)

        let connected = expectation(description: "overlay connected")
        let connectionObserver = observe(service, fulfilling: connected) { _, count in
            count == 1
        }
        task.resume()
        await fulfillment(of: [connected], timeout: 5)
        connectionObserver.cancel()

        let received = expectation(description: "received paused now_playing")
        Self.receiveFrame(type: "now_playing", from: task, fulfilling: received) { frame in
            XCTAssertEqual(frame.data?.track, "Paused Track")
            XCTAssertEqual(frame.data?.isPlaying, false)
        }
        await service.updateNowPlaying(
            track: "Paused Track",
            artist: "Test Artist",
            album: "Test Album",
            duration: 200,
            elapsed: 12,
            artworkURL: nil,
            isPaused: true
        )
        await fulfillment(of: [received], timeout: 5)

        close(session: session, task: task)
        await service.setEnabled(false)
    }

    // MARK: - Queue Upcoming Tests (overlay queue ticker, WW-42)

    /// A freshly connected client receives the cached upcoming queue snapshot so
    /// an OBS browser-source reload never shows a stale ticker.
    func testFreshConnectionReceivesQueueUpcomingSnapshot() async throws {
        let (service, port) = try await startListeningService()
        let (session, task) = try makeClient(port: port)

        await service.broadcastQueueUpcoming(items: [
            WebSocketServerService.QueueUpcomingItem(
                title: "Seeded Track",
                requesterUsername: "someviewer"
            )
        ])

        let received = expectation(description: "received queue_upcoming replay")
        task.resume()
        Self.receiveFrame(type: "queue_upcoming", from: task, fulfilling: received) { frame in
            XCTAssertEqual(
                frame.data?.items,
                [Frame.QueueItem(title: "Seeded Track", requesterUsername: "someviewer")]
            )
        }
        await fulfillment(of: [received], timeout: 5)

        close(session: session, task: task)
        await service.setEnabled(false)
    }

    /// With no prior queue update, the cached snapshot is an empty items array,
    /// meaning the queue is open, rather than a missing message.
    func testFreshConnectionWithNoQueueGetsEmptyItemsArray() async throws {
        let (service, port) = try await startListeningService()
        let (session, task) = try makeClient(port: port)

        let received = expectation(description: "received empty queue_upcoming")
        task.resume()
        Self.receiveFrame(type: "queue_upcoming", from: task, fulfilling: received) { frame in
            XCTAssertEqual(frame.data?.items, [])
        }
        await fulfillment(of: [received], timeout: 5)

        close(session: session, task: task)
        await service.setEnabled(false)
    }
}
