//
//  WebSocketServerServiceTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-02-20.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest
@testable import WolfWave

/// Smoke tests for `WebSocketServerService` construction.
///
/// The port bounds, notification names, UserDefaults keys, queue label, and
/// `ServerState` raw values are covered once in `AppConstantsTests`. Re-asserting
/// those literals here was change-detector duplication (it restates the source and
/// breaks on any intentional edit without catching a bug), so this file keeps only
/// the init behavior that exercises the type itself.
@MainActor
final class WebSocketServerServiceTests: XCTestCase {

    func testServiceInitializesWithDefaultPort() {
        let service = WebSocketServerService()
        XCTAssertEqual(service.state, .stopped)
        XCTAssertEqual(service.connectionCount, 0)
    }

    func testServiceInitializesWithCustomPort() {
        let service = WebSocketServerService(port: 9999)
        XCTAssertEqual(service.state, .stopped)
        XCTAssertEqual(service.connectionCount, 0)
    }
}
