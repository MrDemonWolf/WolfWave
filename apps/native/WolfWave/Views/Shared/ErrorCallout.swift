//
//  ErrorCallout.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-14.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Renders a ``UserFacingError`` as a tinted banner with the buttons that fix it.
///
/// The banner itself is a plain ``CalloutBanner``; the actions sit **beside** it
/// rather than inside, which is the rule the component catalog already sets and
/// that `MusicPermissionBanner` and the Song Requests health banner follow. This
/// generalizes those two so a new error surface never has to hand-roll the pair
/// again.
///
/// Actions arrive as intent, not closures, so the view model decides what
/// "Reconnect with Twitch" means and a test can assert which fix was offered
/// without rendering anything.
///
/// ```swift
/// ErrorCallout(error: viewModel.channelError) { action in
///     viewModel.perform(action)
/// }
/// ```
struct ErrorCallout: View {

    // MARK: - Properties

    let error: UserFacingError

    /// Invoked with the intent the user chose. The caller owns the behavior.
    let onAction: (ErrorAction) -> Void

    // MARK: - State

    /// Seconds left on a `retryAfter` primary action, or `nil` when the primary
    /// action has no waiting period. Drives the live countdown so the button
    /// re-enables on its own instead of staying disabled forever.
    @State private var remainingWait: Int?

    // MARK: - Init

    init(error: UserFacingError, onAction: @escaping (ErrorAction) -> Void = { _ in }) {
        self.error = error
        self.onAction = onAction
    }

    // MARK: - Private Helpers

    /// Semantic severity to the banner's visual style. The model stays free of
    /// SwiftUI; this is the single place the two vocabularies meet.
    private var style: CalloutBanner.Style {
        switch error.severity {
        case .error: return .error
        case .warning: return .warning
        case .info: return .info
        }
    }

    private var tint: Color { style.tint }

    /// Resolves the primary action against the live countdown.
    ///
    /// Pure and static so the expiry behavior is testable without waiting on a
    /// real clock. A wait that has reached zero collapses to a plain `.retry`,
    /// which is enabled and reads "Try Again" rather than "Try Again in 0s".
    static func resolvedPrimary(_ action: ErrorAction?, remainingWait: Int?) -> ErrorAction? {
        guard let action, let declared = action.waitSeconds else { return action }
        let left = remainingWait ?? declared
        return left > 0 ? .retryAfter(seconds: left) : .retry
    }

    private var primaryAction: ErrorAction? {
        Self.resolvedPrimary(error.primaryAction, remainingWait: remainingWait)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            CalloutBanner(
                error.message,
                title: error.title,
                style: style
            )

            if !error.actions.isEmpty {
                actionRow
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(error.accessibilityLabel)
        .accessibilityIdentifier(error.accessibilityIdentifier)
        // Restarts whenever the error changes, so a new rate limit gets a fresh
        // countdown and a non-waiting error clears the old one.
        .task(id: error.id) { await runCountdown() }
    }

    /// Whole seconds left until `deadline`, rounded up so a partially elapsed
    /// second still reads as one.
    ///
    /// Derived from an instant rather than counted down tick by tick: a
    /// decrementing counter drifts under a busy main actor, and would restart
    /// at the full delay every time the view reappeared. Uses `ContinuousClock`
    /// so a system clock change cannot move the expiry.
    static func remainingSeconds(
        now: ContinuousClock.Instant,
        deadline: ContinuousClock.Instant
    ) -> Int {
        let left = now.duration(to: deadline)
        guard left > .zero else { return 0 }
        let parts = left.components
        return Int(parts.seconds) + (parts.attoseconds > 0 ? 1 : 0)
    }

    /// Holds the countdown against a fixed expiry instant, re-rendering about
    /// four times a second so the label stays honest without a per-second
    /// rounding stutter. Cancellation from `.task(id:)` ends it; nothing here
    /// outlives the view.
    private func runCountdown() async {
        guard let declared = error.primaryAction?.waitSeconds, declared > 0 else {
            remainingWait = nil
            return
        }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(declared))
        remainingWait = declared

        while true {
            let left = Self.remainingSeconds(now: clock.now, deadline: deadline)
            remainingWait = left
            guard left > 0 else { return }
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
        }
    }

    /// Primary action reads as the filled button; the rest stay bordered, which
    /// is the macOS convention for "one obvious next step, other ways out".
    private var actionRow: some View {
        HStack(spacing: DSSpace.s2) {
            if let primary = primaryAction {
                Button(primary.label) { onAction(primary) }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                    .controlSize(.small)
                    .disabled(primary.isWaiting)
                    .pointerCursor()
                    .accessibilityIdentifier("\(error.accessibilityIdentifier).action.\(primary.id)")
            }

            ForEach(error.secondaryActions) { action in
                Button(action.label) { onAction(action) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(action.isWaiting)
                    .pointerCursor()
                    .accessibilityIdentifier("\(error.accessibilityIdentifier).action.\(action.id)")
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(alignment: .leading, spacing: DSSpace.s6) {
        ErrorCallout(error: UserFacingError(
            id: "twitch.signInExpired",
            title: "Twitch sign-in expired",
            cause: "Chat commands stopped working.",
            fix: "Reconnect and WolfWave picks up where it left off.",
            severity: .warning,
            actions: [.reconnectTwitch]
        ))

        ErrorCallout(error: UserFacingError(
            id: "twitch.rateLimited",
            title: "Your sign-in is fine, we're being rate limited",
            cause: "Twitch is throttling requests.",
            fix: "Try again in **30 seconds**.",
            severity: .warning,
            actions: [.retryAfter(seconds: 30)]
        ))

        ErrorCallout(error: UserFacingError(
            id: "settings.resetAborted",
            title: "Reset stopped partway",
            cause: "Your saved Twitch sign-in couldn't be removed, so **nothing was erased**.",
            fix: "Try again, or send a bug report if it keeps failing.",
            severity: .error,
            actions: [.retry, .reportBug]
        ))

        ErrorCallout(error: UserFacingError(
            id: "music.automationDenied",
            title: "Let WolfWave read what's playing",
            cause: "WolfWave only reads the current track. It never plays, pauses, or edits your library.",
            severity: .warning,
            actions: [.openAutomationSettings, .openDocs(anchor: "music-permission")]
        ))
    }
    .padding()
    .frame(width: 520)
}
