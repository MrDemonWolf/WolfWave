//
//  TwitchTokenValidationLifecycleTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-12.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

@testable import WolfWave

// MARK: - Twitch Token Validation Lifecycle Tests

/// Deterministic coverage for the app-lifetime startup + hourly Twitch token
/// validation policy. Every suspension point is controlled by a continuation;
/// the suite performs no wall-clock sleeps and no live network requests.
@MainActor
final class TwitchTokenValidationLifecycleTests: XCTestCase {
    private typealias Runner = TwitchBootTokenValidationRunner

    func testTransientValidationRetriesAreBoundedWithExponentialDelays() async {
        let validationCount = ThreadSafeBox(0)
        let refreshCount = ThreadSafeBox(0)
        let delays = ThreadSafeBox<[Duration]>([])

        let outcome = await Runner.run(
            initialCredential: Runner.Credential(token: "token-a", revision: 1),
            validate: { _ in
                validationCount.mutate { $0 += 1 }
                return .temporarilyUnavailable
            },
            refresh: { _ in
                refreshCount.mutate { $0 += 1 }
                return .invalid
            },
            sleep: { delay in delays.mutate { $0.append(delay) } }
        )

        XCTAssertEqual(outcome, .temporarilyUnavailable)
        XCTAssertEqual(validationCount.value, 3)
        XCTAssertEqual(refreshCount.value, 0)
        XCTAssertEqual(delays.value, [.milliseconds(250), .milliseconds(500)])
    }

    func testInvalidTokenRefreshesOnceThenRevalidatesReplacement() async {
        let currentToken = ThreadSafeBox("token-a")
        let validatedTokens = ThreadSafeBox<[String]>([])
        let refreshCount = ThreadSafeBox(0)
        let acceptedTokens = ThreadSafeBox<[String]>([])

        let outcome = await Runner.run(
            initialCredential: Runner.Credential(token: "token-a", revision: 1),
            validate: { token in
                validatedTokens.mutate { $0.append(token) }
                return token == "token-a" ? .invalid : .valid
            },
            refresh: { _ in
                refreshCount.mutate { $0 += 1 }
                currentToken.set("token-b")
                return .refreshed("token-b")
            },
            isCurrent: { $0.token == currentToken.value },
            onValid: { credential in
                acceptedTokens.mutate { $0.append(credential.token) }
            }
        )

        XCTAssertEqual(outcome, .valid("token-b"))
        XCTAssertEqual(validatedTokens.value, ["token-a", "token-b"])
        XCTAssertEqual(refreshCount.value, 1)
        XCTAssertEqual(acceptedTokens.value, ["token-b"])
    }

    func testSecondInvalidResultStopsAfterSingleRefresh() async {
        let currentToken = ThreadSafeBox("token-a")
        let validatedTokens = ThreadSafeBox<[String]>([])
        let refreshCount = ThreadSafeBox(0)

        let outcome = await Runner.run(
            initialCredential: Runner.Credential(token: "token-a", revision: 1),
            validate: { token in
                validatedTokens.mutate { $0.append(token) }
                return .invalid
            },
            refresh: { _ in
                refreshCount.mutate { $0 += 1 }
                currentToken.set("token-b")
                return .refreshed("token-b")
            },
            isCurrent: { $0.token == currentToken.value }
        )

        XCTAssertEqual(outcome, .invalid("token-b"))
        XCTAssertEqual(validatedTokens.value, ["token-a", "token-b"])
        XCTAssertEqual(refreshCount.value, 1)
    }

    func testRefreshOutageKeepsCurrentCredentialTemporarilyUnavailable() async {
        let refreshCount = ThreadSafeBox(0)
        let acceptedTokens = ThreadSafeBox<[String]>([])

        let outcome = await Runner.run(
            initialCredential: Runner.Credential(token: "token-a", revision: 1),
            validate: { _ in .invalid },
            refresh: { _ in
                refreshCount.mutate { $0 += 1 }
                return .temporarilyUnavailable
            },
            onValid: { credential in
                acceptedTokens.mutate { $0.append(credential.token) }
            }
        )

        XCTAssertEqual(outcome, .temporarilyUnavailable)
        XCTAssertEqual(refreshCount.value, 1)
        XCTAssertTrue(acceptedTokens.value.isEmpty)
    }

    func testSupersededRefreshResultCannotValidateOrExpireCredential() async {
        let acceptedTokens = ThreadSafeBox<[String]>([])

        let outcome = await Runner.run(
            initialCredential: Runner.Credential(token: "token-a", revision: 1),
            validate: { _ in .invalid },
            refresh: { _ in .superseded },
            onValid: { credential in
                acceptedTokens.mutate { $0.append(credential.token) }
            }
        )

        XCTAssertEqual(outcome, .superseded)
        XCTAssertTrue(acceptedTokens.value.isEmpty)
    }

    func testCancellationDuringValidateSuppressesValidCallback() async {
        let gate = TokenValidationSuspensionGate()
        let acceptedTokens = ThreadSafeBox<[String]>([])
        let task = Task {
            await Runner.run(
                initialCredential: Runner.Credential(token: "token-a", revision: 1),
                validate: { _ in
                    await gate.suspend()
                    return .valid
                },
                refresh: { _ in .invalid },
                onValid: { credential in
                    acceptedTokens.mutate { $0.append(credential.token) }
                }
            )
        }

        let didSuspend = await waitUntil { await gate.hasSuspended }
        XCTAssertTrue(didSuspend)
        guard didSuspend else {
            task.cancel()
            await gate.release()
            _ = await task.value
            return
        }
        task.cancel()
        await gate.release()
        let outcome = await task.value

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertTrue(acceptedTokens.value.isEmpty)
    }

    func testCancellationDuringRetrySleepStopsBeforeNextValidation() async {
        let gate = TokenValidationSuspensionGate()
        let validationCount = ThreadSafeBox(0)
        let task = Task {
            await Runner.run(
                initialCredential: Runner.Credential(token: "token-a", revision: 1),
                validate: { _ in
                    validationCount.mutate { $0 += 1 }
                    return .temporarilyUnavailable
                },
                refresh: { _ in .invalid },
                sleep: { _ in await gate.suspend() }
            )
        }

        let didSuspend = await waitUntil { await gate.hasSuspended }
        XCTAssertTrue(didSuspend)
        guard didSuspend else {
            task.cancel()
            await gate.release()
            _ = await task.value
            return
        }
        task.cancel()
        await gate.release()
        let outcome = await task.value

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(validationCount.value, 1)
    }

    func testCancellationDuringOnValidCannotReportSuccess() async {
        let gate = TokenValidationSuspensionGate()
        let acceptedTokens = ThreadSafeBox<[String]>([])
        let task = Task {
            await Runner.run(
                initialCredential: Runner.Credential(token: "token-a", revision: 1),
                validate: { _ in .valid },
                refresh: { _ in .invalid },
                onValid: { credential in
                    await gate.suspend()
                    guard !Task.isCancelled else { return }
                    acceptedTokens.mutate { $0.append(credential.token) }
                }
            )
        }

        let didSuspend = await waitUntil { await gate.hasSuspended }
        XCTAssertTrue(didSuspend)
        guard didSuspend else {
            task.cancel()
            await gate.release()
            _ = await task.value
            return
        }
        task.cancel()
        await gate.release()
        let outcome = await task.value

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertTrue(acceptedTokens.value.isEmpty)
    }

    func testOnValidRunsOnlyForStillCurrentToken() async {
        let gate = TokenValidationSuspensionGate()
        let currentToken = ThreadSafeBox("token-a")
        let acceptedTokens = ThreadSafeBox<[String]>([])
        let task = Task {
            await Runner.run(
                initialCredential: Runner.Credential(token: "token-a", revision: 1),
                validate: { _ in
                    await gate.suspend()
                    return .valid
                },
                refresh: { _ in .invalid },
                isCurrent: { $0.token == currentToken.value },
                onValid: { credential in
                    acceptedTokens.mutate { $0.append(credential.token) }
                }
            )
        }

        let didSuspend = await waitUntil { await gate.hasSuspended }
        XCTAssertTrue(didSuspend)
        guard didSuspend else {
            task.cancel()
            await gate.release()
            _ = await task.value
            return
        }
        currentToken.set("token-b")
        await gate.release()
        let outcome = await task.value

        XCTAssertEqual(outcome, .superseded)
        XCTAssertTrue(acceptedTokens.value.isEmpty)
    }

    func testScheduleValidatesImmediatelyHourlyAndResetsForAccountRevision() async {
        let credential = ThreadSafeBox<Runner.Credential?>(
            Runner.Credential(token: "token-a", revision: 1)
        )
        let validatedTokens = ThreadSafeBox<[String]>([])
        let accepted = ThreadSafeBox<[String]>([])
        let sleeper = TokenValidationControlledSleeper()
        let task = Task {
            await Runner.runSchedule(
                credentials: { credential.value },
                validate: { token in
                    validatedTokens.mutate { $0.append(token) }
                    return .valid
                },
                refresh: { _ in .invalid },
                cadenceSleep: { delay in await sleeper.sleep(for: delay) },
                onValid: { current, isFirstValidForAccount, _ in
                    accepted.mutate {
                        $0.append("\(current.token):\(isFirstValidForAccount)")
                    }
                }
            )
        }

        let reachedFirstCadence = await waitUntil { await sleeper.sleepCount >= 1 }
        XCTAssertTrue(reachedFirstCadence)
        guard reachedFirstCadence else {
            task.cancel()
            await sleeper.releaseAll()
            _ = await task.value
            return
        }
        credential.set(Runner.Credential(token: "token-b", revision: 2))
        await sleeper.resumeNext()
        let reachedSecondCadence = await waitUntil { await sleeper.sleepCount >= 2 }
        XCTAssertTrue(reachedSecondCadence)
        guard reachedSecondCadence else {
            task.cancel()
            await sleeper.releaseAll()
            _ = await task.value
            return
        }
        task.cancel()
        await sleeper.resumeNext()
        _ = await task.value
        let delays = await sleeper.recordedDelays()

        XCTAssertEqual(validatedTokens.value, ["token-a", "token-b"])
        XCTAssertEqual(accepted.value, ["token-a:true", "token-b:true"])
        XCTAssertEqual(delays, [.seconds(3_600), .seconds(3_600)])
    }

    func testHourlyValidationPropagatesSameAccountTokenRotation() async {
        let credential = ThreadSafeBox<Runner.Credential?>(
            Runner.Credential(token: "token-a", revision: 7)
        )
        let shouldRejectOldToken = ThreadSafeBox(false)
        let validatedTokens = ThreadSafeBox<[String]>([])
        let refreshInputs = ThreadSafeBox<[String]>([])
        let accepted = ThreadSafeBox<[String]>([])
        let rotations = ThreadSafeBox<[String]>([])
        let sleeper = TokenValidationControlledSleeper()
        let task = Task {
            await Runner.runSchedule(
                credentials: { credential.value },
                validate: { token in
                    validatedTokens.mutate { $0.append(token) }
                    return token == "token-a" && shouldRejectOldToken.value
                        ? .invalid
                        : .valid
                },
                refresh: { rejected in
                    refreshInputs.mutate {
                        $0.append("\(rejected.token)@\(rejected.revision)")
                    }
                    credential.set(
                        Runner.Credential(token: "token-b", revision: rejected.revision)
                    )
                    return .refreshed("token-b")
                },
                cadenceSleep: { delay in await sleeper.sleep(for: delay) },
                onValid: { current, isFirstValidForAccount, rotatedFrom in
                    accepted.mutate {
                        $0.append("\(current.token):\(isFirstValidForAccount)")
                    }
                    if let rotatedFrom {
                        rotations.mutate {
                            $0.append("\(rotatedFrom.token)->\(current.token)")
                        }
                    }
                }
            )
        }

        let reachedFirstCadence = await waitUntil { await sleeper.sleepCount >= 1 }
        XCTAssertTrue(reachedFirstCadence)
        guard reachedFirstCadence else {
            task.cancel()
            await sleeper.releaseAll()
            _ = await task.value
            return
        }
        shouldRejectOldToken.set(true)
        await sleeper.resumeNext()
        let reachedSecondCadence = await waitUntil { await sleeper.sleepCount >= 2 }
        XCTAssertTrue(reachedSecondCadence)
        guard reachedSecondCadence else {
            task.cancel()
            await sleeper.releaseAll()
            _ = await task.value
            return
        }
        task.cancel()
        await sleeper.resumeNext()
        _ = await task.value

        XCTAssertEqual(validatedTokens.value, ["token-a", "token-a", "token-b"])
        XCTAssertEqual(refreshInputs.value, ["token-a@7"])
        XCTAssertEqual(accepted.value, ["token-a:true", "token-b:false"])
        XCTAssertEqual(rotations.value, ["token-a->token-b"])
    }
}

// MARK: - Deterministic Suspension Helpers

/// One-shot continuation gate used to pause validation at a specific await.
private actor TokenValidationSuspensionGate {
    private(set) var hasSuspended = false
    private var isReleased = false
    private var resumeWaiters: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        hasSuspended = true
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            resumeWaiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        resumeWaiters.forEach { $0.resume() }
        resumeWaiters.removeAll()
    }
}

/// Multi-cycle virtual sleeper for the hourly scheduler. Tests explicitly
/// resume each cadence, so account switches and cancellation are race-free.
private actor TokenValidationControlledSleeper {
    private(set) var sleepCount = 0
    private var delays: [Duration] = []
    private var passThrough = false
    private var sleepWaiters: [CheckedContinuation<Void, Never>] = []

    func sleep(for delay: Duration) async {
        delays.append(delay)
        sleepCount += 1
        guard !passThrough else { return }
        await withCheckedContinuation { continuation in
            sleepWaiters.append(continuation)
        }
    }

    func resumeNext() {
        guard !sleepWaiters.isEmpty else { return }
        let continuation = sleepWaiters.removeFirst()
        continuation.resume()
    }

    func releaseAll() {
        passThrough = true
        sleepWaiters.forEach { $0.resume() }
        sleepWaiters.removeAll()
    }

    func recordedDelays() -> [Duration] { delays }
}
