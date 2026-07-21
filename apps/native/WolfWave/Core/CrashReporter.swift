//
//  CrashReporter.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-03.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Darwin
import Foundation

// MARK: - CrashReporter

/// Process-wide last-gasp crash handler. The app's "way to error out" safety net.
///
/// WolfWave is sandboxed and runs services that talk to AppleScript, Discord IPC,
/// a WebSocket server, and Apple Music ScriptingBridge. Most failure paths are
/// already handled with `guard`/`do-catch`/`try?`, but two classes of failure
/// still terminate the process with nothing written:
///
/// 1. An uncaught Objective-C `NSException` (e.g. a Foundation/AppKit invariant
///    violation). Swift `try?`/`do-catch` cannot catch these.
/// 2. A fatal POSIX signal (`SIGSEGV`, `SIGABRT`, …) from a memory fault or trap.
///
/// `install()` registers handlers for both so a hard crash leaves a breadcrumb on
/// disk first. Both paths **chain** to whatever was installed before, and the
/// signal path resets to the default disposition and re-raises, so the OS still
/// generates its normal crash report and MetricKit's `MXCrashDiagnostic` (consumed
/// by ``DiagnosticsService``) still fires next launch. Nothing here runs on the
/// happy path. The next launch reads the breadcrumb via ``didCrashLastLaunch()``.
///
/// - Important: The signal handler is restricted to **async-signal-safe** work
///   only (see `man 7 signal-safety`): `open`/`write`/`close`/`strlen`/`signal`/
///   `raise` over pre-baked C buffers. No Swift `String`/`Array` growth, no
///   Foundation, no `Log`. All rich work (backtrace, reason, `Log.flush()`) is
///   confined to the NSException handler, which runs in a normal runtime.
enum CrashReporter {

    // MARK: Installation

    /// Installs the exception + signal handlers. Idempotent; safe to call once
    /// early in launch. Must run on the main thread (it allocates the marker
    /// path and label table that the signal handler later reads).
    nonisolated static func install() {
        guard !crashReporterDidInstall else { return }
        crashReporterDidInstall = true

        // Pre-create the marker directory and bake the marker path into a malloc'd
        // C string NOW, on the main thread, so the signal handler never allocates.
        let url = markerURL()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        crashReporterMarkerPath = url.path.withCString { strdup($0) } // never freed: process lifetime
        crashReporterBuildLabelTable()

        // SIGPIPE is special: this app holds long-lived sockets (Discord IPC,
        // WebSocket). A peer that drops mid-write would raise SIGPIPE, and a
        // re-raising handler would turn a handled EPIPE into a crash. Ignore it
        // process-wide; the socket code already inspects `errno == EPIPE`.
        signal(SIGPIPE, SIG_IGN)

        // Uncaught ObjC exceptions: chain to any previously-installed handler.
        crashReporterPreviousExceptionHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler(crashReporterExceptionHandler)

        // Fatal signals: record a breadcrumb, then restore the PREVIOUS handler
        // and re-raise so the OS crash reporter / MetricKit / the debugger / the
        // Swift runtime backtracer all still see the crash. We capture each prior
        // disposition here and chain it from the handler instead of dropping to
        // SIG_DFL, so a handler a dependency or debugger registered isn't lost.
        // Order must line up with `crashReporterSignalSlot` and the label table.
        // SIGPIPE is deliberately excluded (ignored above).
        let trappedSignals: [Int32] = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP]
        let savedActions = UnsafeMutablePointer<sigaction>.allocate(capacity: trappedSignals.count)
        for (index, sig) in trappedSignals.enumerated() {
            var action = sigaction()
            action.__sigaction_u.__sa_handler = crashReporterSignalHandler
            sigemptyset(&action.sa_mask)
            action.sa_flags = 0
            sigaction(sig, &action, savedActions.advanced(by: index)) // capture prior disposition
        }
        crashReporterPreviousActions = savedActions

        Log.info("CrashReporter: installed (uncaught-exception + signal handlers)", category: "App")
    }

    // MARK: Breadcrumb lifecycle

    /// Whether the previous run left a crash breadcrumb. Existence check only;
    /// does not clear the marker (the caller clears after reading).
    nonisolated static func didCrashLastLaunch() -> Bool {
        FileManager.default.fileExists(atPath: markerURL().path)
    }

    /// Removes the breadcrumb. Call after a clean launch has read it, so the
    /// next launch is silent. No-op when absent.
    nonisolated static func clearMarker() {
        try? FileManager.default.removeItem(at: markerURL())
    }

    /// Location of the on-disk breadcrumb: `…/Application Support/WolfWave/State/
    /// last-crash.marker`. Mirrors ``DiagnosticsService``'s container layout.
    nonisolated static func markerURL() -> URL {
        if let override = markerDirectoryOverride {
            return override.appending(path: markerFileName, directoryHint: .notDirectory)
        }
        return AppContainer.directory("State")
            .appending(path: markerFileName, directoryHint: .notDirectory)
    }

    // MARK: Test seams

    /// When set, the marker lives in this directory instead of Application
    /// Support. Production never sets this; tests point it at a temp dir to stay
    /// hermetic. Only affects the Foundation-level helpers (`writeMarker`,
    /// `didCrashLastLaunch`, `clearMarker`); the signal handler always writes to
    /// the path baked at `install()` time.
    nonisolated(unsafe) static var markerDirectoryOverride: URL?

    /// Writes the breadcrumb body via Foundation. Used by the NSException handler
    /// (which runs in a normal runtime) and by tests. **Never** call this from a
    /// signal handler (it allocates).
    nonisolated static func writeMarker(_ body: String) {
        let url = markerURL()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Data(body.utf8).write(to: url, options: .atomic)
    }

    // MARK: Private

    nonisolated private static let markerFileName = "last-crash.marker"
}

// MARK: - C-callable handler state
//
// The handlers are assigned to C function pointers (`@convention(c)`), so they
// can't capture context; their shared state lives at file scope. `nonisolated`
// keeps them out of the module's default `MainActor` isolation (a MainActor
// function can't be converted to `@convention(c)`). `nonisolated(unsafe)` on the
// mutable globals is sound here: everything is written once on the main thread in
// `install()` and only read afterward (the signal handler reads raw pointers).

/// Guards against double-install.
private nonisolated(unsafe) var crashReporterDidInstall = false

/// The uncaught-exception handler that was installed before us, if any. Chained.
private nonisolated(unsafe) var crashReporterPreviousExceptionHandler:
    (@convention(c) (NSException) -> Void)?

/// malloc'd, NUL-terminated marker path. Read by the signal handler. Never freed
/// (lives for the process lifetime by design).
private nonisolated(unsafe) var crashReporterMarkerPath: UnsafeMutablePointer<CChar>?

/// malloc'd table of `"SIGNAME\n"` C strings, parallel to
/// `crashReporterTrappedSignals`. Indexed by a pure switch in the handler.
private nonisolated(unsafe) var crashReporterLabelTable: UnsafeMutablePointer<UnsafePointer<CChar>?>?

/// Fallback label when a signal isn't in the trapped set (defensive; shouldn't
/// happen). malloc'd at install.
private nonisolated(unsafe) var crashReporterUnknownLabel: UnsafePointer<CChar>?

/// Saved prior `sigaction` for each trapped signal, in install order (indexed by
/// `crashReporterSignalSlot`). malloc'd at install. The handler restores the
/// entry for the firing signal so the previous handler (debugger, Swift runtime
/// backtracer, a dependency's reporter) is chained before re-raise.
private nonisolated(unsafe) var crashReporterPreviousActions: UnsafeMutablePointer<sigaction>?

// MARK: - Handlers

/// Uncaught ObjC exception handler. Runs in a normal runtime (allocation OK).
private nonisolated func crashReporterExceptionHandler(_ exception: NSException) {
    let name = Log.redact(exception.name.rawValue)
    let reason = Log.redact(exception.reason ?? "")
    let frames = exception.callStackSymbols.prefix(20).joined(separator: "\n")
    CrashReporter.writeMarker("EXCEPTION \(name)\n\(reason)\n\(frames)\n")
    Log.error("CrashReporter: uncaught NSException \(name): \(reason)", category: "App")
    Log.flush() // belt-and-suspenders; Log.error already flushes
    crashReporterPreviousExceptionHandler?(exception) // chain, do not swallow
}

/// Fatal-signal handler. **Async-signal-safe only.**
private nonisolated func crashReporterSignalHandler(_ signalNumber: Int32) {
    if let pathPtr = crashReporterMarkerPath {
        let fd = open(pathPtr, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        if fd >= 0 {
            let slot = crashReporterSignalSlot(signalNumber)
            if slot >= 0, let table = crashReporterLabelTable, let label = table[slot] {
                _ = write(fd, label, strlen(label))
            } else if let unknown = crashReporterUnknownLabel {
                _ = write(fd, unknown, strlen(unknown))
            }
            close(fd)
        }
    }
    // Restore the PREVIOUS disposition for this signal (the debugger, the Swift
    // runtime backtracer, or a dependency's handler) and re-deliver, so the crash
    // still reaches whatever was watching. Falls back to the default only when no
    // prior action was captured. Async-signal-safe: a pure slot switch, a
    // raw-pointer read, a stack-local copy, then sigaction/raise.
    let slot = crashReporterSignalSlot(signalNumber)
    if slot >= 0, let saved = crashReporterPreviousActions {
        var previous = saved[slot]
        sigaction(signalNumber, &previous, nil)
    } else {
        signal(signalNumber, SIG_DFL)
    }
    raise(signalNumber)
}

/// Pure integer switch (no allocation) mapping a signal to its label-table slot.
private nonisolated func crashReporterSignalSlot(_ sig: Int32) -> Int {
    switch sig {
    case SIGABRT: return 0
    case SIGILL:  return 1
    case SIGSEGV: return 2
    case SIGFPE:  return 3
    case SIGBUS:  return 4
    case SIGTRAP: return 5
    default:      return -1
    }
}

/// Builds the malloc'd label table on the main thread at install time.
private nonisolated func crashReporterBuildLabelTable() {
    let labels = ["SIGABRT\n", "SIGILL\n", "SIGSEGV\n", "SIGFPE\n", "SIGBUS\n", "SIGTRAP\n"]
    let table = UnsafeMutablePointer<UnsafePointer<CChar>?>.allocate(capacity: labels.count)
    for (index, label) in labels.enumerated() {
        table[index] = label.withCString { UnsafePointer(strdup($0)) }
    }
    crashReporterLabelTable = table
    crashReporterUnknownLabel = "SIGNAL\n".withCString { UnsafePointer(strdup($0)) }
}
