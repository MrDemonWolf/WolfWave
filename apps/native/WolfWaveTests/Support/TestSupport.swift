//
//  TestSupport.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-28.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//
//  Free helpers used by both XCTest and Swift Testing suites.
//

import Foundation
import Testing

@testable import WolfWave

/// Serializes tests that touch the process-wide Twitch credential state:
/// `KeychainService.backend` **and** `Preferences.twitchReauthNeeded`.
///
/// Holding this is required to *read* that state, not only to swap it. Swift
/// Testing runs separate suites in parallel (`.serialized` only orders tests
/// within one suite), so an unguarded suite that reaches the Keychain through a
/// service still lands on whichever backend another suite currently has
/// installed. That is exactly how `TwitchViewModel.clearCredentials()` came to
/// delete the accounts `KeychainServiceTests` had just seeded into its own
/// backend, and how its `reauthNeeded` writes flipped the shared default
/// mid-assertion.
///
/// ponytail: one test semaphore; use task-local backends if parallelism matters.
nonisolated enum KeychainBackendTestIsolation {
    private static let semaphore = DispatchSemaphore(value: 1)

    static func acquire() { semaphore.wait() }
    static func release() { semaphore.signal() }

    /// Acquisition for `@MainActor` suites. A blocking `acquire()` on the main
    /// thread deadlocks whenever the current holder is a `@MainActor` test
    /// suspended mid-`await`: the holder needs the main actor to resume and the
    /// waiter is sitting on it. Awaiting instead keeps the main actor free.
    static func acquireAsync() async { await acquireOffCooperativePool() }

    /// Runs `body` with exclusive ownership of the shared credential state, on a
    /// private in-memory backend, restoring the previous backend and reauth flag
    /// on exit. Balanced by construction, unlike a hand-written acquire/release
    /// pair.
    ///
    /// Inherits the caller's isolation so `@MainActor` suites can pass a plain
    /// closure, and waits off the cooperative pool so a blocked acquisition
    /// never starves the executor running the lock holder.
    static func withIsolatedCredentialState<T>(
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> T
    ) async rethrows -> T {
        await acquireOffCooperativePool()
        let previousBackend = KeychainService.backend
        let previousReauthNeeded = Preferences.twitchReauthNeeded
        KeychainService.backend = InMemoryKeychainBackend()
        Preferences.setTwitchReauthNeeded(false)
        defer {
            Preferences.setTwitchReauthNeeded(previousReauthNeeded)
            KeychainService.backend = previousBackend
            release()
        }
        return try await body()
    }

    private static func acquireOffCooperativePool() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                semaphore.wait()
                continuation.resume()
            }
        }
    }
}

/// Binds a task-scoped `KeychainService` backend around every test in the suite
/// it is applied to, so no concurrently running suite can observe or mutate it.
///
/// The semaphore above only excludes suites that cooperate with it. An ordinary
/// suite that reads Twitch credentials through a service does not, and a grant
/// read that is already inside `twitchCredentialLock` when the backend is
/// swapped finishes its legacy-field probes against the new backend. That is
/// unfixable by locking alone without locking every reader, so the backend stops
/// being shared instead.
struct IsolatedKeychainBackendTrait: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @concurrent @Sendable () async throws -> Void
    ) async throws {
        try await KeychainService.$backendBox.withValue(
            .init(InMemoryKeychainBackend())
        ) {
            try await function()
        }
    }
}

extension Trait where Self == IsolatedKeychainBackendTrait {
    /// Applies ``IsolatedKeychainBackendTrait`` to a suite or test.
    static var isolatedKeychainBackend: Self { Self() }
}

/// Creates a fresh, unique temp directory and ensures it exists. Returns the URL.
///
/// Swift Testing suites don't have tearDown. Callers are responsible for cleanup
/// (or rely on the OS reclaiming `tmp`). Prefer `WolfWaveTestCase.makeTempDir()`
/// for XCTest-based suites, which auto-cleans on tearDown.
func makeIsolatedTempDirectory(prefix: String = "wolfwave-test") -> URL {
    let dir = FileManager.default
        .temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Reads the request body from either representation Foundation exposes to
/// `URLProtocol` test doubles.
func requestBodyString(_ request: URLRequest) -> String {
    if let body = request.httpBody, !body.isEmpty {
        return String(bytes: body, encoding: .utf8) ?? ""
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
    return String(bytes: body, encoding: .utf8) ?? ""
}

/// Thread-safe value box for capturing state from inside `@Sendable` closures
/// (mock request handlers, actor callbacks) without violating strict
/// concurrency. NSLock is fine here; tests aren't measuring lock perf.
///
/// Shared by the suites that previously each declared a private copy
/// (`RequestCounter`, `TestValueBox`, `Box`). Deliberately not named `Atomic`
/// so it never shadows the production type in `Core/ThreadSafeStorage.swift`
/// (exercised directly by `AtomicTests`).
nonisolated final class ThreadSafeBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    /// Atomically replaces the stored value.
    func set(_ newValue: Value) { lock.withLock { stored = newValue } }

    /// Atomically transforms the stored value in place.
    func mutate(_ transform: (inout Value) -> Void) { lock.withLock { transform(&stored) } }
}

/// Bridges a synchronous GCD semaphore wait into async tests without running a
/// blocking operation inside a Swift concurrency task. The continuation is
/// resumed exactly once by the dedicated GCD work item, including on timeout.
func waitForSemaphore(
    _ semaphore: DispatchSemaphore,
    timeout: DispatchTime
) async -> Bool {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(
                returning: semaphore.wait(timeout: timeout) == .success
            )
        }
    }
}

/// Inspectable process-local Keychain backend with deterministic one-shot
/// failures. Shared by migration and transaction tests so failure semantics
/// stay deterministic without reaching the user's real Keychain.
nonisolated final class InspectableKeychainBackend: KeychainBackend, @unchecked Sendable {
    enum InjectedError: Error {
        case save
    }

    private let lock = NSLock()
    private var store: [String: String] = [:]
    private var nextFailingSaveAccount: String?
    private var nextFailingLoad: (account: String, status: Int32)?
    private var nextFailingDelete: (account: String, status: Int32)?
    private var nextDeleteAllStatus: Int32?
    private var loadedAccounts: [String] = []

    func failNextSave(for account: String) {
        lock.withLock { nextFailingSaveAccount = account }
    }

    func failNextLoad(for account: String, status: Int32 = -25308) {
        lock.withLock { nextFailingLoad = (account, status) }
    }

    func failNextDelete(for account: String, status: Int32 = -25308) {
        lock.withLock { nextFailingDelete = (account, status) }
    }

    func failNextDeleteAll(status: Int32 = -25308) {
        lock.withLock { nextDeleteAllStatus = status }
    }

    func seed(account: String, value: String) {
        lock.withLock { store[account] = value }
    }

    func rawValue(account: String) -> String? {
        lock.withLock { store[account] }
    }

    func loadCount(account: String) -> Int {
        lock.withLock { loadedAccounts.filter { $0 == account }.count }
    }

    func save(account: String, value: String) throws {
        try lock.withLock {
            if nextFailingSaveAccount == account {
                nextFailingSaveAccount = nil
                throw InjectedError.save
            }
            store[account] = value
        }
    }

    func load(account: String) throws -> String? {
        try lock.withLock {
            loadedAccounts.append(account)
            if nextFailingLoad?.account == account {
                let status = nextFailingLoad?.status ?? -25308
                nextFailingLoad = nil
                throw KeychainService.KeychainError.loadFailed(status)
            }
            return store[account]
        }
    }

    func delete(account: String) throws {
        try lock.withLock {
            if nextFailingDelete?.account == account {
                let status = nextFailingDelete?.status ?? -25308
                nextFailingDelete = nil
                throw KeychainService.KeychainError.deleteFailed(status)
            }
            store[account] = nil
        }
    }

    func deleteAll() throws {
        try lock.withLock {
            if let status = nextDeleteAllStatus {
                nextDeleteAllStatus = nil
                throw KeychainService.KeychainError.deleteFailed(status)
            }
            store.removeAll()
        }
    }
}

/// Polls `condition` until it returns true or the timeout elapses, returning
/// the final result. Avoids fixed sleeps when waiting on async work (disk I/O,
/// actor state), which are flaky under CI load.
///
/// The condition may be synchronous or `async`; non-async closures convert
/// implicitly. Shared by the suites that previously each declared a private
/// copy (ArtworkServiceNetworkTests, SkipVoteManagerTests,
/// SongRequestServiceTests).
@discardableResult
func waitUntil(
    timeout: Duration = .seconds(2),
    interval: Duration = .milliseconds(20),
    _ condition: () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: interval)
    }
    return await condition()
}

/// Collects exactly `count` values from an `AsyncStream`, or returns nil when
/// the deadline wins. Task-group cancellation makes a missing event fail the
/// test instead of leaving an unbounded `iterator.next()` suspended forever.
func collectFirst<Element: Sendable>(
    _ count: Int,
    from stream: AsyncStream<Element>,
    timeout: Duration = .seconds(2)
) async -> [Element]? {
    guard count > 0 else { return [] }
    return await withTaskGroup(of: [Element]?.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            var values: [Element] = []
            values.reserveCapacity(count)
            for _ in 0..<count {
                guard let value = await iterator.next() else { return nil }
                values.append(value)
            }
            return values
        }
        group.addTask {
            do {
                try await Task.sleep(for: timeout)
                return nil
            } catch {
                return nil
            }
        }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}

/// Round-trips a credential through a save/load/delete cycle and asserts the
/// loaded value matches what was saved.
///
/// Collapses the save → assert → delete → assert-nil pattern repeated for
/// every credential variant in `KeychainServiceTests`. Pass save/load/delete
/// closures bound to the specific KeychainService API under test.
///
/// - Parameters:
///   - value: Value to round-trip. Must not be empty.
///   - save: Save closure (throwing).
///   - load: Load closure returning the persisted value or nil.
///   - delete: Delete closure.
///   - sourceLocation: Forwarded so Swift Testing reports the caller's line.
func assertKeychainRoundTrip(
    _ value: String,
    save: (String) throws -> Void,
    load: () -> String?,
    delete: () throws -> Void,
    sourceLocation: Testing.SourceLocation = #_sourceLocation
) throws {
    try save(value)
    #expect(load() == value, sourceLocation: sourceLocation)
    try delete()
    #expect(load() == nil, sourceLocation: sourceLocation)
}
