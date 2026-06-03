//
//  ReplyCapture.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-29.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//
//  Shared reply-capture helper for bot-command tests. Several command suites
//  fire a fire-and-forget reply closure and need to await the first value (or
//  fall back to an empty string after a timeout). This used to be copy-pasted
//  into each command test file. It now lives here once.
//

import XCTest

@testable import WolfWave

extension WolfWaveTestCase {

    /// Runs `trigger`, handing it a reply callback, and returns the first value
    /// the callback receives. Returns `""` if no reply arrives within `timeout`.
    ///
    /// The continuation is resumed exactly once. `ReplyOnceBox` guards against
    /// both a real reply and the timeout racing to fulfill it.
    @MainActor
    func captureReply(
        timeout: TimeInterval = 2.0,
        _ trigger: @escaping (@escaping (String) -> Void) -> Void
    ) async -> String {
        await withCheckedContinuation { continuation in
            let box = ReplyOnceBox()
            trigger { value in
                guard box.fulfill() else { return }
                continuation.resume(returning: value)
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                guard box.fulfill() else { return }
                continuation.resume(returning: "")
            }
        }
    }
}

/// One-shot latch: `fulfill()` returns `true` for the first caller and `false`
/// thereafter, so a continuation is resumed exactly once.
final class ReplyOnceBox: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()

    func fulfill() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
