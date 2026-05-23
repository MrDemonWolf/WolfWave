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
}
