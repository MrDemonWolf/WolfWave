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
        crashReporterBuildMarkerPrefix()
        // Scratch for formatting the epoch stamp. Pre-allocated because the
        // handler may not malloc; writing digits into memory that already exists
        // is async-signal-safe.
        crashReporterScratch = UnsafeMutablePointer<CChar>.allocate(capacity: crashReporterScratchCapacity)

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

        Log.info("CrashReporter: installed (uncaught-exception + signal handlers)", category: .app)
    }

    // MARK: Breadcrumb lifecycle

    /// Whether the previous run left a crash breadcrumb. Existence check only;
    /// does not clear the marker (the caller clears after reading).
    nonisolated static func didCrashLastLaunch() -> Bool {
        FileManager.default.fileExists(atPath: markerURL().path)
    }

    /// Reads and parses the breadcrumb left by a previous run.
    ///
    /// Prefer this over ``didCrashLastLaunch()``: the marker carries the signal
    /// name, timestamp, build, and (for exceptions) the backtrace, and the
    /// caller is about to delete it, so an existence check throws all of that
    /// away.
    ///
    /// - Returns: The parsed marker, or `nil` when absent or empty.
    nonisolated static func readMarker() -> CrashMarker? {
        guard let text = try? String(contentsOf: markerURL(), encoding: .utf8) else { return nil }
        return CrashMarker.parse(text)
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

    #if DEBUG
    /// Composes exactly what the signal handler's three `write(2)` calls emit,
    /// for the given signal slot and epoch.
    ///
    /// The real path cannot be exercised in a test: raising a fatal signal kills
    /// the xctest host. This pins the concatenation against ``CrashMarker`` so
    /// the writer and the reader cannot drift, which is the failure that would
    /// otherwise only show up when someone actually crashed.
    nonisolated static func composeSignalMarkerForTesting(slot: Int, epoch: Int) -> String {
        let label = crashReporterSignalLabels[slot]
        return crashReporterMarkerPrefixString() + label + "\(epoch)\n"
    }
    #endif

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

/// malloc'd, NUL-terminated fixed header written before the signal label.
private nonisolated(unsafe) var crashReporterMarkerPrefix: UnsafePointer<CChar>?

/// Pre-allocated digit buffer for the epoch stamp. 32 bytes is far more than the
/// 19 digits a 64-bit `time_t` can need.
private nonisolated(unsafe) var crashReporterScratch: UnsafeMutablePointer<CChar>?

/// `nonisolated` like every other handler global: the module defaults to
/// MainActor isolation and the signal handler is a `@convention(c)` function
/// that cannot be actor-isolated.
private nonisolated let crashReporterScratchCapacity = 32

/// Saved prior `sigaction` for each trapped signal, in install order (indexed by
/// `crashReporterSignalSlot`). malloc'd at install. The handler restores the
/// entry for the firing signal so the previous handler (debugger, Swift runtime
/// backtracer, a dependency's reporter) is chained before re-raise.
private nonisolated(unsafe) var crashReporterPreviousActions: UnsafeMutablePointer<sigaction>?

// MARK: - Handlers

/// Uncaught ObjC exception handler. Runs in a normal runtime (allocation OK).
private nonisolated func crashReporterExceptionHandler(_ exception: NSException) {
    let name = Log.redact(exception.name.rawValue)
    // Newlines are collapsed so `reason` stays one `key=value` line; the frames
    // that follow each get their own line, which keeps the marker parseable.
    let reason = Log.redact(exception.reason ?? "")
        .replacingOccurrences(of: "\n", with: " ")
    let frames = exception.callStackSymbols.prefix(20)
        .map { "frame=\(Log.redact($0))" }
        .joined(separator: "\n")

    CrashReporter.writeMarker("""
        \(CrashMarker.header)
        kind=exception
        pid=\(ProcessInfo.processInfo.processIdentifier)
        version=\(AppConstants.AppInfo.shortVersion)
        build=\(AppConstants.AppInfo.buildNumber)
        epoch=\(Int(Date().timeIntervalSince1970))
        name=\(name)
        reason=\(reason)
        \(frames)
        """)
    Log.error("CrashReporter: uncaught NSException \(name): \(reason)", category: .app)
    Log.flush() // belt-and-suspenders; Log.error already flushes
    crashReporterPreviousExceptionHandler?(exception) // chain, do not swallow
}

/// Fatal-signal handler. **Async-signal-safe only.**
private nonisolated func crashReporterSignalHandler(_ signalNumber: Int32) {
    if let pathPtr = crashReporterMarkerPath {
        let fd = open(pathPtr, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        if fd >= 0 {
            // Three writes, all async-signal-safe over memory allocated at
            // install time: the pre-baked header (pid/version/build), the signal
            // label, then the epoch digits. The marker used to be just the label,
            // e.g. 8 bytes of "SIGSEGV\n", with no time, pid, or build at all.
            if let prefix = crashReporterMarkerPrefix {
                _ = write(fd, prefix, strlen(prefix))
            }
            let slot = crashReporterSignalSlot(signalNumber)
            if slot >= 0, let table = crashReporterLabelTable, let label = table[slot] {
                _ = write(fd, label, strlen(label))
            } else if let unknown = crashReporterUnknownLabel {
                _ = write(fd, unknown, strlen(unknown))
            }
            crashReporterWriteEpoch(fd)
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
/// Signal labels, indexed by ``crashReporterSignalSlot``.
///
/// Each closes the `signal=` line and opens the `epoch=` one, so the handler
/// emits the whole record in three writes with no formatting.
nonisolated let crashReporterSignalLabels = [
    "SIGABRT\nepoch=", "SIGILL\nepoch=", "SIGSEGV\nepoch=",
    "SIGFPE\nepoch=", "SIGBUS\nepoch=", "SIGTRAP\nepoch="
]

private nonisolated func crashReporterBuildLabelTable() {
    let labels = crashReporterSignalLabels
    let table = UnsafeMutablePointer<UnsafePointer<CChar>?>.allocate(capacity: labels.count)
    for (index, label) in labels.enumerated() {
        table[index] = label.withCString { UnsafePointer(strdup($0)) }
    }
    crashReporterLabelTable = table
    crashReporterUnknownLabel = "SIGNAL\nepoch=".withCString { UnsafePointer(strdup($0)) }
}

/// Bakes the fixed part of the marker (schema, kind, pid, version, build) into a
/// malloc'd C string at install time, when a normal runtime is available.
private nonisolated func crashReporterBuildMarkerPrefix() {
    crashReporterMarkerPrefix = crashReporterMarkerPrefixString()
        .withCString { UnsafePointer(strdup($0)) }
}

/// The fixed part of a signal marker, as a Swift string.
///
/// Note the deliberate lack of a trailing newline after `signal=`: the signal
/// label supplies the rest of that line.
nonisolated func crashReporterMarkerPrefixString() -> String {
    """
    \(CrashMarker.header)
    kind=signal
    pid=\(ProcessInfo.processInfo.processIdentifier)
    version=\(AppConstants.AppInfo.shortVersion)
    build=\(AppConstants.AppInfo.buildNumber)
    signal=
    """
}

/// Writes the current epoch seconds followed by a newline.
///
/// `clock_gettime` is on POSIX's async-signal-safe list, and the digits are
/// formatted by hand into a buffer allocated at install time, so this adds no
/// allocation, no Foundation, and no locking to the handler.
private nonisolated func crashReporterWriteEpoch(_ descriptor: Int32) {
    guard let scratch = crashReporterScratch else { return }
    var time = timespec()
    guard clock_gettime(CLOCK_REALTIME, &time) == 0 else { return }

    // Fill backwards from the end: newline first, then least-significant digit up.
    var index = crashReporterScratchCapacity - 1
    scratch[index] = 0x0A // "\n"
    index -= 1

    var value = time.tv_sec
    if value <= 0 {
        scratch[index] = 0x30 // "0"
        index -= 1
    } else {
        while value > 0 && index >= 0 {
            scratch[index] = CChar(0x30 + (value % 10))
            value /= 10
            index -= 1
        }
    }

    _ = write(descriptor, scratch.advanced(by: index + 1), crashReporterScratchCapacity - index - 1)
}
