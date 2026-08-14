//
//  UserFacingError.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-14.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// A failure described the way a streamer needs to hear it: what broke, why,
/// what to do, and a button that does it.
///
/// Every user-visible failure resolves to one of these. Services map their own
/// error types into it next to the type itself, so the structure survives the
/// trip to the UI instead of being flattened into a `String` at the view-model
/// seam. That flattening is what produced "Couldn't check channel" for four
/// unrelated causes, with the real reason reachable only through a tooltip.
///
/// This generalizes ``PlaylistSetupStatus``, which already proved the shape
/// works here by carrying its own message, action label, and severity.
///
/// Deliberately free of SwiftUI: ``Severity`` is semantic, and the view layer
/// owns the mapping to a tint. That keeps the model `Sendable`, testable
/// without a renderer, and usable from an actor.
///
/// ## Where these appear
///
/// macOS reserves modal alerts for things the user cannot proceed without
/// answering. A failed background reconnect is not that. So:
///
/// - **Inline** (``ErrorCallout``) for ambient state: a connection dropped, a
///   permission is off, a server won't start. The pane keeps working around it.
/// - **Alert** only when the user just asked for something and it failed
///   outright, so the answer belongs to the action they took: an import, an
///   export, a reset. The app has three of these today and should not grow many
///   more.
/// - **Under the field** (``FieldValidationRow``) when the failure is about
///   what was typed.
///
/// ```swift
/// UserFacingError(
///     id: "twitch.signInExpired",
///     title: "Twitch sign-in expired",
///     cause: "Twitch rejected the saved sign-in.",
///     fix: "Reconnect and WolfWave picks up where it left off.",
///     severity: .warning,
///     actions: [.reconnectTwitch]
/// )
/// ```
nonisolated struct UserFacingError: Equatable, Sendable, Identifiable {

    // MARK: - Severity

    /// How loudly the failure should read. Maps to a `CalloutBanner.Style` in
    /// the view layer.
    enum Severity: String, Equatable, Sendable, CaseIterable {
        /// Something the user wanted is not working and will not fix itself.
        case error
        /// Degraded, recoverable, or waiting on the user or a third party.
        case warning
        /// Not a failure. A state worth naming before the user goes looking.
        case info
    }

    // MARK: - Properties

    /// Stable identifier, also used for the accessibility identifier so a state
    /// with no render path fails its test instead of passing invisibly.
    /// Convention: `domain.camelCaseCause`, e.g. `twitch.rateLimited`.
    let id: String

    /// What broke, in words the user recognizes. Never names a subsystem, a
    /// status code, or a Swift type.
    let title: String

    /// Why it broke. Present only when it changes what the user should do.
    let cause: String?

    /// What to do about it. Matches the primary action's label when there is one.
    let fix: String?

    let severity: Severity

    /// Offered actions, most useful first. Empty when there is nothing the app
    /// can do on the user's behalf.
    let actions: [ErrorAction]

    /// Anchor on the troubleshooting docs page, when one covers this failure.
    let docsAnchor: String?

    // MARK: - Init

    init(
        id: String,
        title: String,
        cause: String? = nil,
        fix: String? = nil,
        severity: Severity = .error,
        actions: [ErrorAction] = [],
        docsAnchor: String? = nil
    ) {
        self.id = id
        self.title = title
        self.cause = cause
        self.fix = fix
        self.severity = severity
        self.actions = actions
        self.docsAnchor = docsAnchor
    }

    // MARK: - Public Methods

    /// Body copy for the banner: cause then fix, whichever are present.
    ///
    /// Rendered through `InlineMarkdown`, so `**bold**` in either field works.
    var message: String {
        [cause, fix].compactMap { $0 }.joined(separator: " ")
    }

    /// The action a banner should render as its filled button, if any.
    var primaryAction: ErrorAction? { actions.first }

    /// Remaining actions, rendered as bordered buttons beside the primary.
    var secondaryActions: [ErrorAction] { Array(actions.dropFirst()) }

    /// Accessibility identifier for the rendered banner.
    var accessibilityIdentifier: String { "errorCallout.\(id)" }

    /// Spoken label combining the title and body, so VoiceOver never has to
    /// reach a tooltip to learn the real reason.
    var accessibilityLabel: String {
        message.isEmpty ? title : "\(title). \(message)"
    }
}

// MARK: - ErrorAction

/// Something WolfWave can do about a failure, expressed as intent rather than a
/// closure.
///
/// Keeping intents as data means ``UserFacingError`` stays `Sendable` and
/// `Equatable`, a test can assert which fix was offered without a view, and the
/// mapping from intent to behavior lives in exactly one place in the UI layer.
nonisolated enum ErrorAction: Equatable, Sendable, Identifiable {

    /// Start the Twitch OAuth flow again. Only correct when the token is
    /// genuinely bad or a scope is missing, never when the sign-in verified fine.
    case reconnectTwitch
    /// Re-run sign-in because the current token belongs to the wrong account.
    case signInAsBroadcaster
    /// Retry whatever just failed.
    case retry
    /// Retry, but not yet. Carries the server's `Retry-After` in seconds.
    case retryAfter(seconds: Int)
    /// System Settings › Privacy & Security › Automation.
    case openAutomationSettings
    /// System Settings › General › Login Items.
    case openLoginItems
    /// System Settings › Notifications.
    case openNotificationSettings
    /// Reopen the Song Requests setup sheet, optionally at a given step.
    case openSongRequestSetup(step: Int?)
    /// Ask Sparkle to check again.
    case checkForUpdates
    /// Reopen the file picker after an import or export failed.
    case chooseAnotherFile
    /// Open the troubleshooting docs at an anchor.
    case openDocs(anchor: String)
    /// Open a pre-filled GitHub issue.
    case reportBug

    /// Stable identity for `ForEach` and for asserting on offered actions.
    var id: String {
        switch self {
        case .reconnectTwitch: return "reconnectTwitch"
        case .signInAsBroadcaster: return "signInAsBroadcaster"
        case .retry: return "retry"
        case .retryAfter(let seconds): return "retryAfter.\(seconds)"
        case .openAutomationSettings: return "openAutomationSettings"
        case .openLoginItems: return "openLoginItems"
        case .openNotificationSettings: return "openNotificationSettings"
        case .openSongRequestSetup(let step): return "openSongRequestSetup.\(step.map(String.init) ?? "start")"
        case .checkForUpdates: return "checkForUpdates"
        case .chooseAnotherFile: return "chooseAnotherFile"
        case .openDocs(let anchor): return "openDocs.\(anchor)"
        case .reportBug: return "reportBug"
        }
    }

    /// Button label.
    ///
    /// Title-style capitalization, per the macOS HIG and the labels already
    /// shipping in this app ("Check Again", "Open System Settings",
    /// "Set Up Song Requests"). Note that banner *titles* stay sentence case,
    /// matching `CalloutBanner`'s existing titles; only controls are title case.
    ///
    /// `reportBug` keeps the trailing ellipsis because it opens something
    /// further, which is the macOS meaning of that ellipsis, and because the
    /// Advanced pane already spells it that way.
    var label: String {
        switch self {
        case .reconnectTwitch: return "Reconnect with Twitch"
        case .signInAsBroadcaster: return "Sign In as Broadcaster"
        case .retry: return "Try Again"
        case .retryAfter(let seconds): return "Try Again in \(seconds)s"
        case .openAutomationSettings: return "Open System Settings"
        case .openLoginItems: return "Open Login Items"
        case .openNotificationSettings: return "Open System Settings"
        case .openSongRequestSetup: return "Set Up Song Requests"
        case .checkForUpdates: return "Check Again"
        case .chooseAnotherFile: return "Choose Another File"
        case .openDocs: return "Learn More"
        case .reportBug: return "Report a Bug\u{2026}"
        }
    }

    /// Whether the action is currently offered but not yet usable, e.g. a
    /// rate-limit countdown that has not elapsed.
    var isWaiting: Bool {
        if case .retryAfter = self { return true }
        return false
    }
}
