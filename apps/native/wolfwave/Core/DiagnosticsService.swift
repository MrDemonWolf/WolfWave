//
//  DiagnosticsService.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import MetricKit

// MARK: - Diagnostics Service

/// Privacy-preserving, on-device diagnostics using Apple's MetricKit.
///
/// When the user opts in, this service subscribes to `MXMetricManager` and
/// persists crash, hang, and performance payloads as JSON under Application
/// Support. **No data ever leaves the device** — there is no network code
/// here. It also keeps a local, anonymous app-launch counter.
///
/// Use `DiagnosticsService.shared`. The initializer is internal so tests can
/// inject an isolated `UserDefaults`.
///
/// Marked `@unchecked Sendable` because all mutable state is lock-guarded;
/// MetricKit invokes the subscriber callbacks off the main thread.
final class DiagnosticsService: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {

    // MARK: - Singleton

    /// Shared instance used across the app.
    static let shared = DiagnosticsService()

    // MARK: - Properties

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var isSubscribed = false
    private var lastDiagnosticSummary: String?

    // MARK: - Init

    /// Internal so unit tests can inject an isolated `UserDefaults`; app code
    /// uses `shared`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
    }

    // MARK: - Opt-In

    /// Whether the user has opted in to on-device diagnostics collection.
    var isEnabled: Bool {
        defaults.bool(forKey: AppConstants.UserDefaults.shareDiagnosticsEnabled)
    }

    /// Registers or removes the MetricKit subscriber to match the stored opt-in
    /// preference. Call once at launch.
    func applyEnabledState() {
        setEnabled(isEnabled)
    }

    /// Subscribes to or unsubscribes from MetricKit payloads.
    ///
    /// - Parameter enabled: `true` to start collecting on-device diagnostics.
    func setEnabled(_ enabled: Bool) {
        let alreadySubscribed = lock.withLock { isSubscribed }

        if enabled, !alreadySubscribed {
            MXMetricManager.shared.add(self)
            lock.withLock { isSubscribed = true }
            Log.info("DiagnosticsService: MetricKit subscriber registered (opt-in on)", category: "Diagnostics")
        } else if !enabled, alreadySubscribed {
            MXMetricManager.shared.remove(self)
            lock.withLock { isSubscribed = false }
            Log.info("DiagnosticsService: MetricKit subscriber removed (opt-in off)", category: "Diagnostics")
        }
    }

    // MARK: - Anonymous Usage

    /// Increments the local app-launch counter. The count never leaves the device.
    func recordAppLaunch() {
        let next = defaults.integer(forKey: AppConstants.UserDefaults.diagnosticsLaunchCount) + 1
        defaults.set(next, forKey: AppConstants.UserDefaults.diagnosticsLaunchCount)
    }

    /// Total app launches recorded on this device.
    var launchCount: Int {
        defaults.integer(forKey: AppConstants.UserDefaults.diagnosticsLaunchCount)
    }

    /// Human-readable summary of the most recent MetricKit diagnostic payload,
    /// or `nil` if none has been received this session.
    var diagnosticSummary: String? {
        lock.withLock { lastDiagnosticSummary }
    }

    /// On-device directory where MetricKit payloads are persisted.
    var payloadDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "WolfWave/Diagnostics", directoryHint: .isDirectory)
    }

    // MARK: - MXMetricManagerSubscriber

    func didReceive(_ payloads: [MXMetricPayload]) {
        guard isEnabled else { return }
        persist(payloads.map { $0.jsonRepresentation() }, prefix: "metric")
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        guard isEnabled else { return }
        persist(payloads.map { $0.jsonRepresentation() }, prefix: "diagnostic")

        let summary = Self.summarize(payloads)
        lock.withLock { lastDiagnosticSummary = summary }
        Log.info("DiagnosticsService: \(summary)", category: "Diagnostics")
    }

    // MARK: - Private Helpers

    /// Writes raw payload JSON to the on-device payload directory.
    private func persist(_ payloads: [Data], prefix: String) {
        guard !payloads.isEmpty else { return }
        let dir = payloadDirectory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            for (index, data) in payloads.enumerated() {
                let url = dir.appending(path: "\(prefix)-\(stamp)-\(index).json")
                try data.write(to: url)
            }
        } catch {
            Log.error(
                "DiagnosticsService: Failed to persist \(prefix) payload: \(error.localizedDescription)",
                category: "Diagnostics"
            )
        }
    }

    /// Builds a one-line count summary across a batch of diagnostic payloads.
    private static func summarize(_ payloads: [MXDiagnosticPayload]) -> String {
        var crashes = 0, hangs = 0, cpu = 0, diskWrites = 0
        for payload in payloads {
            crashes += payload.crashDiagnostics?.count ?? 0
            hangs += payload.hangDiagnostics?.count ?? 0
            cpu += payload.cpuExceptionDiagnostics?.count ?? 0
            diskWrites += payload.diskWriteExceptionDiagnostics?.count ?? 0
        }
        return "\(crashes) crash · \(hangs) hang · \(cpu) CPU · \(diskWrites) disk-write"
    }
}
