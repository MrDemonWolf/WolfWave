//
//  DiagnosticSnapshot.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-14.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// The app's environment, as one value, for every place that has to describe
/// this install to someone else.
///
/// Three surfaces used to build this block independently: `BugReportURL` as a
/// bullet list, `DebugDiagnostics` as a markdown table, and the log export as
/// nothing at all. The only one carrying service state was compiled out of
/// release, which is why a release user reporting a bug could hand over a raw
/// log and nothing else.
///
/// Not `#if DEBUG`. That was the bug.
nonisolated struct DiagnosticSnapshot: Equatable {

    enum InstallMethod: String, Equatable {
        case homebrew = "Homebrew"
        case dmg = "DMG"
    }

    let appVersion: String
    let build: String
    let osVersion: String
    let arch: String
    let installMethod: InstallMethod

    /// Whether the previous launch left a crash breadcrumb.
    let crashedLastLaunch: Bool

    /// One-line summary of that crash, when there was one.
    let crashSummary: String?

    /// Whether the user opted into on-device MetricKit diagnostics.
    let diagnosticsEnabled: Bool

    let logSizeBytes: Int64

    /// Human-readable log size, formatted at capture time.
    ///
    /// Stored rather than formatted on demand because `ByteFormatting` is
    /// main-actor isolated, and the rendering below runs off the main actor when
    /// composing an export. Keeping the struct's rendering pure is what lets it
    /// cross that boundary.
    let logSizeDescription: String

    // MARK: - Capture

    /// Reads everything that does not require touching a service.
    ///
    /// Cheap: preferences plus `Bundle`/`ProcessInfo`. The log size is passed in
    /// because resolving it goes through `Log`'s serial file queue, and callers
    /// that already have it should not pay twice.
    @MainActor
    static func capture(logSizeBytes: Int64) -> DiagnosticSnapshot {
        DiagnosticSnapshot(
            appVersion: AppConstants.AppInfo.shortVersion,
            build: AppConstants.AppInfo.buildNumber,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            arch: currentArch,
            installMethod: Bundle.main.isHomebrewInstall ? .homebrew : .dmg,
            crashedLastLaunch: DefaultsStore.store.bool(
                forKey: AppConstants.UserDefaults.lastLaunchCrashed),
            crashSummary: DefaultsStore.store.string(
                forKey: AppConstants.UserDefaults.lastCrashSummary),
            diagnosticsEnabled: DefaultsStore.store.bool(
                forKey: AppConstants.UserDefaults.shareDiagnosticsEnabled),
            logSizeBytes: logSizeBytes,
            logSizeDescription: ByteFormatting.string(logSizeBytes)
        )
    }

    /// CPU architecture this build is running as.
    static var currentArch: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    // MARK: - Rendering

    /// Markdown bullet list, for a GitHub issue body.
    var markdownBullets: String {
        var lines = [
            "- **App version:** \(appVersion) (build \(build))",
            "- **macOS:** \(osVersion)",
            "- **Architecture:** \(arch)",
            "- **Install method:** \(installMethod.rawValue)",
            "- **Log size:** \(logSizeDescription)",
            "- **Diagnostics opt-in:** \(diagnosticsEnabled ? "yes" : "no")"
        ]
        // Only mentioned when true. A "Crashed last launch: no" line on every
        // report is noise that trains people to skip the block.
        if crashedLastLaunch {
            lines.append("- **Recovered from a crash:** \(crashSummary ?? "yes")")
        }
        return lines.joined(separator: "\n")
    }

    /// Plain-text header for the top of an exported diagnostics file.
    ///
    /// Deliberately not markdown: the export is a `.log` people open in a text
    /// editor or `less`, not a document.
    var exportHeader: String {
        var lines = [
            "WolfWave diagnostics",
            "app        \(appVersion) (build \(build))",
            "macOS      \(osVersion)",
            "arch       \(arch)",
            "install    \(installMethod.rawValue)",
            "log size   \(logSizeDescription)",
            "diagnostics opt-in: \(diagnosticsEnabled ? "yes" : "no")"
        ]
        if crashedLastLaunch {
            lines.append("crash      \(crashSummary ?? "previous launch ended in a crash")")
        }
        return lines.joined(separator: "\n")
    }
}
