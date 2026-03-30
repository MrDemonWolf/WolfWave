//
//  WebSocketServerIntegrationTests.swift
//  WolfWaveTests
//
//  Created by MrDemonWolf, Inc. on 3/19/26.
//

import XCTest
@testable import WolfWave

// Integration tests using fixed ports (59001-59008) for WebSocket server lifecycle
final class WebSocketServerIntegrationTests: XCTestCase {

    // MARK: - Server Lifecycle Tests

    func testServerStartReachesListeningState() {
        let service = WebSocketServerService(port: 59001)
        let exp = expectation(description: "server listening")
        var fulfilled = false

        service.onStateChange = { state, _ in
            if state == .listening && !fulfilled {
                fulfilled = true
                exp.fulfill()
            }
        }

        service.setEnabled(true)
        waitForExpectations(timeout: 10)
        service.setEnabled(false)
    }

    func testServerStopReachesStoppedState() {
        let service = WebSocketServerService(port: 59002)
        let listeningExpectation = expectation(description: "server listening")
        let stoppedExpectation = expectation(description: "server stopped")
        var wasListening = false
        var wasStopped = false

        service.onStateChange = { state, _ in
            if state == .listening && !wasListening {
                wasListening = true
                listeningExpectation.fulfill()
            } else if state == .stopped && wasListening && !wasStopped {
                wasStopped = true
                stoppedExpectation.fulfill()
            }
        }

        service.setEnabled(true)
        wait(for: [listeningExpectation], timeout: 10)

        Thread.sleep(forTimeInterval: 0.5)

        service.setEnabled(false)
        wait(for: [stoppedExpectation], timeout: 10)
    }

    func testServerRestartCycle() {
        let service = WebSocketServerService(port: 59003)
        let firstListen = expectation(description: "first listen")
        let stopped = expectation(description: "stopped")
        let secondListen = expectation(description: "second listen")
        var phase = 0

        service.onStateChange = { state, _ in
            if state == .listening && phase == 0 {
                phase = 1
                firstListen.fulfill()
            } else if state == .stopped && phase == 1 {
                phase = 2
                stopped.fulfill()
            } else if state == .listening && phase == 2 {
                phase = 3
                secondListen.fulfill()
            }
        }

        service.setEnabled(true)
        wait(for: [firstListen], timeout: 5)

        service.setEnabled(false)
        wait(for: [stopped], timeout: 5)

        service.setEnabled(true)
        wait(for: [secondListen], timeout: 5)

        service.setEnabled(false)
    }

    // MARK: - Port Conflict Tests

    func testTwoServersOnSamePortHandledGracefully() {
        let service1 = WebSocketServerService(port: 59004)
        let service2 = WebSocketServerService(port: 59004)

        let listening1 = expectation(description: "service1 listening")

        var s1Listening = false
        service1.onStateChange = { state, _ in
            if state == .listening && !s1Listening {
                s1Listening = true
                listening1.fulfill()
            }
        }

        service1.setEnabled(true)
        wait(for: [listening1], timeout: 5)

        // Second server on same port should fail with an error
        let service2State = expectation(description: "service2 state change")
        service2.onStateChange = { state, _ in
            if state == .error {
                service2State.fulfill()
            }
        }

        service2.setEnabled(true)
        wait(for: [service2State], timeout: 5)

        service1.setEnabled(false)
        service2.setEnabled(false)
    }

    // MARK: - Connection Count Tests

    func testConnectionCountStartsAtZero() {
        let service = WebSocketServerService(port: 59005)
        XCTAssertEqual(service.connectionCount, 0)
    }

    func testConnectionCountIsZeroAfterStart() {
        let service = WebSocketServerService(port: 59006)
        let expectation = expectation(description: "server listening")

        var fulfilled = false
        service.onStateChange = { state, count in
            if state == .listening && !fulfilled {
                fulfilled = true
                XCTAssertEqual(count, 0)
                expectation.fulfill()
            }
        }

        service.setEnabled(true)
        waitForExpectations(timeout: 5)
        service.setEnabled(false)
    }

    // MARK: - Initial State Tests

    func testServiceInitialStateIsStopped() {
        let service = WebSocketServerService(port: 59007)
        XCTAssertEqual(service.state, .stopped)
    }

    func testOnStateChangeCallbackIsNilByDefault() {
        let service = WebSocketServerService(port: 59008)
        XCTAssertNil(service.onStateChange)
    }
}
