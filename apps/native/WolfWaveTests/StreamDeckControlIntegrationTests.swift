//
//  StreamDeckControlIntegrationTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-17.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import XCTest
@testable import WolfWave

/// Drives a Stream Deck command across a real WebSocket and back.
///
/// The two halves of this path were each covered and the seam between them was
/// not: `StreamDeckCommandTests` parses envelopes as strings with no transport,
/// and `WebSocketServerAuthTests` settles handshakes without sending a command
/// through one. So a change to how a frame is read off the wire, dispatched to
/// the handler, or acked back on the originating connection could break the
/// plugin with both suites green.
///
/// Every case owns an OS-assigned loopback port and waits on observed state, so
/// nothing here depends on a fixed port being free or on a sleep standing in for
/// an assertion.
final class StreamDeckControlIntegrationTests: XCTestCase, @unchecked Sendable {

    private static let overlayToken = String(repeating: "c", count: 64)
    private static let controlToken = String(repeating: "d", count: 64)

    /// Just the ack fields. Decoding the whole frame union would couple this
    /// suite to every broadcast shape it has to skip past.
    private struct Ack: Decodable, Sendable {
        let type: String
        let action: String?
        let ok: Bool?
        let error: String?
    }

    private enum FrameError: Error {
        case unsupportedMessage
    }

    // MARK: - Fixtures

    /// Starts a server on an OS-assigned port and returns it with that port.
    ///
    /// Binding `0` is what keeps the suite independent of the machine: a
    /// hardcoded high port sits inside the macOS ephemeral range, so an
    /// unrelated process holding it would fail the bind and the test with it.
    private func startServer() async throws -> (WebSocketServerService, UInt16) {
        let service = WebSocketServerService(
            port: 0,
            overlayToken: Self.overlayToken,
            controlToken: Self.controlToken
        )

        let listening = expectation(description: "server listening")
        let stream = service.stateChanges
        let observer = Task.detached {
            for await (state, _) in stream where state == .listening {
                listening.fulfill()
                return
            }
        }
        await service.setEnabled(true)
        await fulfillment(of: [listening], timeout: 5)
        observer.cancel()

        let bound = await service.boundPort
        let port = try XCTUnwrap(bound, "A listening server must report the port it bound")
        return (service, port)
    }

    /// Connects over loopback with the subprotocol for `role`.
    ///
    /// The address is the literal `127.0.0.1` on purpose: the server only
    /// authorizes commands from literal loopback, so anything else here would be
    /// testing the rejection path by accident.
    private func connect(
        port: UInt16,
        role: WebSocketAuthToken.Role,
        token: String
    ) throws -> (URLSession, URLSessionWebSocketTask) {
        let url = try XCTUnwrap(URL(string: "ws://127.0.0.1:\(port)/"))
        let session = URLSession(configuration: .ephemeral)
        let subprotocol = WebSocketAuthToken.expectedSubprotocol(for: token, role: role)
        return (session, session.webSocketTask(with: url, protocols: [subprotocol]))
    }

    private func commandFrame(action: String, protocolVersion: Int) -> String {
        #"{"type":"command","protocol":\#(protocolVersion),"action":"\#(action)"}"#
    }

    /// Receives until an `ack` arrives, skipping the state broadcasts a fresh
    /// connection is replayed. Transport and decode failures fail immediately so
    /// the real cause is not buried under the outer timeout.
    private nonisolated static func receiveAck(
        from task: URLSessionWebSocketTask,
        fulfilling expectation: XCTestExpectation,
        file: StaticString = #filePath,
        line: UInt = #line,
        asserting assertions: @escaping @Sendable (Ack) -> Void
    ) {
        task.receive { result in
            switch result {
            case .success(let message):
                do {
                    let data: Data
                    switch message {
                    case .string(let text): data = Data(text.utf8)
                    case .data(let payload): data = payload
                    @unknown default: throw FrameError.unsupportedMessage
                    }
                    let ack = try JSONDecoder().decode(Ack.self, from: data)
                    if ack.type == "ack" {
                        assertions(ack)
                        expectation.fulfill()
                    } else {
                        receiveAck(
                            from: task,
                            fulfilling: expectation,
                            file: file,
                            line: line,
                            asserting: assertions
                        )
                    }
                } catch {
                    XCTFail("Failed to decode frame: \(error)", file: file, line: line)
                    expectation.fulfill()
                }
            case .failure(let error):
                XCTFail("WebSocket receive failed: \(error)", file: file, line: line)
                expectation.fulfill()
            }
        }
    }

    private func close(_ session: URLSession, _ task: URLSessionWebSocketTask) {
        task.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
    }

    // MARK: - Tests

    /// The whole round trip: a control client's frame reaches the handler and
    /// its ack comes back on the same connection.
    func testControlClientCommandReachesHandlerAndIsAcked() async throws {
        let (service, port) = try await startServer()
        defer { Task { await service.setEnabled(false) } }

        let handled = Atomic<StreamDeckCommand?>(nil)
        await service.setCommandHandler { command in
            handled.set(command)
            return .success(command.action)
        }

        let (session, task) = try connect(
            port: port, role: .control, token: Self.controlToken)
        defer { close(session, task) }
        task.resume()

        let acked = expectation(description: "received ack")
        Self.receiveAck(from: task, fulfilling: acked) { ack in
            XCTAssertEqual(ack.action, StreamDeckAction.skip.rawValue)
            XCTAssertEqual(ack.ok, true)
            XCTAssertNil(ack.error)
        }

        try await task.send(
            .string(commandFrame(
                action: StreamDeckAction.skip.rawValue,
                protocolVersion: StreamDeckControl.protocolVersion
            )))
        await fulfillment(of: [acked], timeout: 10)

        XCTAssertEqual(
            handled.value?.action, .skip,
            "The command never reached the handler, so the ack came from somewhere else"
        )
    }

    /// The read-only credential must not be able to drive the app.
    ///
    /// The overlay token is handed to an OBS browser source, which is the least
    /// trusted thing that ever connects. A regression that let it run commands
    /// would not fail any pure-parse test, because the envelope is perfectly
    /// valid; only its origin is wrong.
    func testOverlayClientCommandIsRefusedAndNeverReachesHandler() async throws {
        let (service, port) = try await startServer()
        defer { Task { await service.setEnabled(false) } }

        let handled = Atomic<StreamDeckCommand?>(nil)
        await service.setCommandHandler { command in
            handled.set(command)
            return .success(command.action)
        }

        let (session, task) = try connect(
            port: port, role: .overlay, token: Self.overlayToken)
        defer { close(session, task) }
        task.resume()

        let refused = expectation(description: "received refusal ack")
        Self.receiveAck(from: task, fulfilling: refused) { ack in
            XCTAssertEqual(ack.ok, false, "An overlay client's command was accepted")
            XCTAssertEqual(ack.error, "unauthorized")
        }

        try await task.send(
            .string(commandFrame(
                action: StreamDeckAction.skip.rawValue,
                protocolVersion: StreamDeckControl.protocolVersion
            )))
        await fulfillment(of: [refused], timeout: 10)

        XCTAssertNil(
            handled.value,
            "The handler ran for an overlay client; the refusal is only cosmetic"
        )
    }

    /// An out-of-date plugin gets `error:"protocol"` rather than silent
    /// misbehaviour, and its command is not run.
    func testStaleProtocolVersionIsRejectedWithoutRunning() async throws {
        let (service, port) = try await startServer()
        defer { Task { await service.setEnabled(false) } }

        let handled = Atomic<StreamDeckCommand?>(nil)
        await service.setCommandHandler { command in
            handled.set(command)
            return .success(command.action)
        }

        let (session, task) = try connect(
            port: port, role: .control, token: Self.controlToken)
        defer { close(session, task) }
        task.resume()

        let rejected = expectation(description: "received protocol rejection")
        Self.receiveAck(from: task, fulfilling: rejected) { ack in
            XCTAssertEqual(ack.ok, false)
            XCTAssertEqual(ack.error, "protocol")
        }

        try await task.send(
            .string(commandFrame(
                action: StreamDeckAction.skip.rawValue,
                protocolVersion: StreamDeckControl.protocolVersion - 1
            )))
        await fulfillment(of: [rejected], timeout: 10)

        XCTAssertNil(handled.value, "A stale-protocol command was run anyway")
    }
}
