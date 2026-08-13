//
//  MusicProcess.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-04.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit

/// Locates the running Music.app process.
///
/// ## Never address Music by bundle identifier
///
/// An Apple event addressed by bundle id is auto-launched by LaunchServices, so
/// `SBApplication(bundleIdentifier:)` and a bare `tell application "Music"` both
/// **start Music if it isn't running**. `SBApplication`'s own header says it
/// "launches the application only when it's necessary to send it an event", and
/// `LSLaunchFlags` has no don't-launch option, so `launchFlags` cannot suppress it.
///
/// Guarding with an is-it-running check *before* the send does not fix this: the
/// user can quit Music in the window between the check and the event, and the
/// event drags it straight back. That race shipped twice (PR #203, PR #273) and
/// was reported both times as "WolfWave keeps reopening Music".
///
/// The durable fix is to address Music by **pid**. A pid-addressed event cannot
/// launch anything; if the process is gone the send simply fails. Callers should
/// resolve `pid` and hand it to `SBApplication(processIdentifier:)`, treating nil
/// as "Music isn't running".
///
/// ## Only ScriptingBridge can do this
///
/// Pid addressing is a ScriptingBridge capability, not a general one. It does
/// **not** transfer to `NSAppleScript`: an `NSAppleEventDescriptor(processIdentifier:)`
/// is an event *address*, and AppleScript has no coercion from one to an
/// application specifier. Passed into a script it arrives as opaque
/// `«data kpid…»` with no terminology bound, so `tell` evaluates the body against
/// a meaningless object and every property read fails `-1728` while every verb
/// fails `-1708`. That shipped in 2.1.0 and silently killed all Music control.
/// See `AppleMusicController.musicTargetedScript` for the AppleScript-side
/// answer.
///
/// ## Trap: an unresolvable pid does not yield nil
///
/// `SBApplication(processIdentifier:)` is documented to return nil when no such
/// application exists, but it does not: for an unknown pid it returns a plain
/// `SBApplication` that is **not KVC-compliant**, and `value(forKey:)` on it raises
/// `NSUnknownKeyException`, which Swift cannot catch — an outright crash. Callers
/// must therefore gate on `isRunning` (and ideally `responds(to:)` for the accessor
/// they are about to use) before any KVC read. Both report false for an unresolved
/// target and true for a live one; verified on macOS 26.
///
/// AppleScript callers that cannot address by pid should wrap their script body in
/// `if application "Music" is running then …`, which is evaluated without launching
/// the target.
enum MusicProcess {

    // MARK: - Public API

    /// Process identifier of the running Music.app, or nil when it isn't running.
    ///
    /// Terminated instances are filtered out: `NSRunningApplication` can briefly
    /// vend a still-registered object for a process that has already exited.
    nonisolated static var pid: pid_t? {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: AppConstants.Music.bundleIdentifier)
            .first { !$0.isTerminated }?
            .processIdentifier
    }

    /// Whether Music.app currently has a live process.
    ///
    /// Prefer `pid` when the answer is about to be used to send an Apple event, so
    /// the send targets the exact process that was observed rather than re-resolving
    /// the bundle id.
    nonisolated static var isRunning: Bool { pid != nil }
}
