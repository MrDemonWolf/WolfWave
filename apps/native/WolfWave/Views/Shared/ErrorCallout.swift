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
    }

    /// Primary action reads as the filled button; the rest stay bordered, which
    /// is the macOS convention for "one obvious next step, other ways out".
    private var actionRow: some View {
        HStack(spacing: DSSpace.s2) {
            if let primary = error.primaryAction {
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
