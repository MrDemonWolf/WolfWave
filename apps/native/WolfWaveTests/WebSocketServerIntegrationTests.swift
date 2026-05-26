//
//  WebSocketServerIntegrationTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 3/19/26.
//

import XCTest
@testable import WolfWave

// Integration tests using fixed ports (59001-59008) for WebSocket server lifecycle
final class WebSocketServerIntegrationTests: XCTestCase, @unchecked Sendable {

    // MARK: - Helpers

    /// Waits for `predicate` to return true for an emitted `(state, count)` event
    /// on the service's `stateChanges` stream, then fulfills `expectation`.
    /// Returns the consumer Task so the caller can cancel it after the wait.
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

    // MARK: - Server Lifecycle Tests

    func testServerStartReachesListeningState() {
        let service = WebSocketServerService(port: 59001)
        let exp = expectation(description: "server listening")

        let observer = observe(service, fulfilling: exp) { state, _ in state == .listening }

        Task { await service.setEnabled(true) }
        waitForExpectations(timeout: 10)
        observer.cancel()
        Task { await service.setEnabled(false) }
    }

    func testServerStopReachesStoppedState() {
        let service = WebSocketServerService(port: 59002)
        let listeningExpectation = expectation(description: "server listening")
        let stoppedExpectation = expectation(description: "server stopped")

        let listenObs = observe(service, fulfilling: listeningExpectation) { state, _ in state == .listening }

        Task { await service.setEnabled(true) }
        wait(for: [listeningExpectation], timeout: 10)
        listenObs.cancel()

        Thread.sleep(forTimeInterval: 0.5)

        let stopObs = observe(service, fulfilling: stoppedExpectation) { state, _ in state == .stopped }
        Task { await service.setEnabled(false) }
        wait(for: [stoppedExpectation], timeout: 10)
        stopObs.cancel()
    }

    func testServerRestartCycle() {
        let service = WebSocketServerService(port: 59003)
        let firstListen = expectation(description: "first listen")
        let stopped = expectation(description: "stopped")
        let secondListen = expectation(description: "second listen")

        let obs1 = observe(service, fulfilling: firstListen) { state, _ in state == .listening }
        Task { await service.setEnabled(true) }
        wait(for: [firstListen], timeout: 5)
        obs1.cancel()

        let obs2 = observe(service, fulfilling: stopped) { state, _ in state == .stopped }
        Task { await service.setEnabled(false) }
        wait(for: [stopped], timeout: 5)
        obs2.cancel()

        let obs3 = observe(service, fulfilling: secondListen) { state, _ in state == .listening }
        Task { await service.setEnabled(true) }
        wait(for: [secondListen], timeout: 5)
        obs3.cancel()

        Task { await service.setEnabled(false) }
    }

    // MARK: - Port Conflict Tests

    func testTwoServersOnSamePortHandledGracefully() {
        let service1 = WebSocketServerService(port: 59004)
        let service2 = WebSocketServerService(port: 59004)

        let listening1 = expectation(description: "service1 listening")
        let obs1 = observe(service1, fulfilling: listening1) { state, _ in state == .listening }

        Task { await service1.setEnabled(true) }
        wait(for: [listening1], timeout: 5)
        obs1.cancel()

        // Second server on same port should fail with an error
        let service2State = expectation(description: "service2 state change")
        let obs2 = observe(service2, fulfilling: service2State) { state, _ in state == .error }

        Task { await service2.setEnabled(true) }
        wait(for: [service2State], timeout: 5)
        obs2.cancel()

        Task { await service1.setEnabled(false) }
        Task { await service2.setEnabled(false) }
    }

    // MARK: - Connection Count Tests

    func testConnectionCountStartsAtZero() {
        let service = WebSocketServerService(port: 59005)
        XCTAssertEqual(service.connectionCount, 0)
    }

    func testConnectionCountIsZeroAfterStart() {
        let service = WebSocketServerService(port: 59006)
        let exp = expectation(description: "server listening")
        let obs = observe(service, fulfilling: exp) { state, count in
            if state == .listening {
                XCTAssertEqual(count, 0)
                return true
            }
            return false
        }

        Task { await service.setEnabled(true) }
        waitForExpectations(timeout: 5)
        obs.cancel()
        Task { await service.setEnabled(false) }
    }

    // MARK: - Initial State Tests

    func testServiceInitialStateIsStopped() {
        let service = WebSocketServerService(port: 59007)
        XCTAssertEqual(service.state, .stopped)
    }

    func testStateChangesStreamIsAvailable() {
        let service = WebSocketServerService(port: 59008)
        // Stream is a non-optional `let`; just confirm we can subscribe without
        // crashing and that no events are emitted before `setEnabled(true)`.
        let stream = service.stateChanges
        _ = stream
    }

    // MARK: - Replay-on-Connect Tests

    /// A freshly-connected client should immediately receive the last-known
    /// `now_playing` frame so the widget doesn't sit on a blank placeholder
    /// when OBS restarts the browser source mid-stream.
    func testFreshConnectionReceivesLastKnownState() {
        let port: UInt16 = 59009
        let service = WebSocketServerService(port: port)

        let listening = expectation(description: "server listening")
        let listenObs = observe(service, fulfilling: listening) { state, _ in state == .listening }
        Task { await service.setEnabled(true) }
        wait(for: [listening], timeout: 5)
        listenObs.cancel()

        // Seed state before any client connects.
        let stateSeeded = expectation(description: "state seeded")
        Task {
            await service.updateNowPlaying(
                track: "Replay Test Track",
                artist: "Test Artist",
                album: "Test Album",
                duration: 200,
                elapsed: 12,
                artworkURL: nil
            )
            stateSeeded.fulfill()
        }
        wait(for: [stateSeeded], timeout: 5)

        // Open a client. Service was constructed with the test-only `init(port:)`,
        // so `authToken` is nil and any handshake is accepted.
        guard let url = URL(string: "ws://127.0.0.1:\(port)/") else {
            XCTFail("bad ws url"); return
        }
        let session = URLSession(configuration: .ephemeral)
        let task = session.webSocketTask(with: url)
        task.resume()

        // Drain frames until we see a `now_playing` carrying our seeded track.
        let gotState = expectation(description: "received now_playing replay")
        func recv() {
            task.receive { result in
                switch result {
                case .success(let message):
                    let text: String
                    switch message {
                    case .string(let s): text = s
                    case .data(let d): text = String(data: d, encoding: .utf8) ?? ""
                    @unknown default: text = ""
                    }
                    if text.contains("\"type\":\"now_playing\"") && text.contains("Replay Test Track") {
                        gotState.fulfill()
                        return
                    }
                    recv()
                case .failure:
                    return
                }
            }
        }
        recv()

        wait(for: [gotState], timeout: 5)

        task.cancel(with: .normalClosure, reason: nil)
        Task { await service.setEnabled(false) }
    }
}
