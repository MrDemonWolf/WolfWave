//
//  FieldValidationRow.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-14.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Inline validation feedback shown directly under a text field.
///
/// Replaces three hand-rolled indicators that had drifted apart: the Twitch
/// channel field, its diverged copy in the onboarding Twitch step, and the
/// Stream Widgets token field. Between them they used three different error
/// glyphs (`exclamationmark.octagon.fill`, `xmark.circle.fill`,
/// `exclamationmark.circle.fill`) and raw `.red` / `.orange` rather than the
/// semantic tokens.
///
/// The important behavior change: ``State/failed(_:)`` renders the real reason
/// **inline**. The Twitch field used to show "Couldn't check channel" and hide
/// the actual cause in a `.help()` tooltip, which is invisible to anyone not
/// hovering and was the bug that started this work.
///
/// ```swift
/// TextField("yourchannel", text: $channel)
/// FieldValidationRow(state: viewModel.channelValidation)
/// ```
struct FieldValidationRow: View {

    // MARK: - State

    /// What the field currently knows about its contents.
    enum State: Equatable {
        /// Nothing to say yet. Renders nothing.
        case idle
        /// A check is in flight.
        case validating(String)
        /// The value is good.
        case valid(String)
        /// The value is wrong and the user can fix it by typing.
        case invalid(String)
        /// The check itself failed. Carries the full error so the reason is
        /// visible rather than buried in a tooltip.
        case failed(UserFacingError)
    }

    // MARK: - Properties

    let state: State

    // MARK: - Init

    init(state: State) {
        self.state = state
    }

    // MARK: - Private Helpers

    private var tint: Color {
        switch state {
        case .idle, .validating: return .secondary
        case .valid: return DSColor.success
        case .invalid: return DSColor.error
        case .failed(let error):
            switch error.severity {
            case .error: return DSColor.error
            case .warning: return DSColor.warning
            case .info: return DSColor.info
            }
        }
    }

    /// One glyph vocabulary across every field in the app.
    private var symbol: String? {
        switch state {
        case .idle, .validating: return nil
        case .valid: return "checkmark.circle.fill"
        case .invalid: return "xmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var text: String {
        switch state {
        case .idle: return ""
        case .validating(let message): return message
        case .valid(let message): return message
        case .invalid(let message): return message
        case .failed(let error): return error.accessibilityLabel
        }
    }

    private var identifier: String {
        switch state {
        case .idle: return "fieldValidation.idle"
        case .validating: return "fieldValidation.validating"
        case .valid: return "fieldValidation.valid"
        case .invalid: return "fieldValidation.invalid"
        case .failed(let error): return "fieldValidation.\(error.id)"
        }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if case .idle = state {
                EmptyView()
            } else {
                HStack(alignment: .firstTextBaseline, spacing: DSSpace.s1) {
                    glyph
                    Text(InlineMarkdown.attributed(text))
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(text)
                .accessibilityIdentifier(identifier)
            }
        }
    }

    @ViewBuilder
    private var glyph: some View {
        if case .validating = state {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.mini)
                .accessibilityHidden(true)
        } else if let symbol {
            Image(systemName: symbol)
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(alignment: .leading, spacing: DSSpace.s4) {
        FieldValidationRow(state: .validating("Verifying channel\u{2026}"))
        FieldValidationRow(state: .valid("Channel verified"))
        FieldValidationRow(state: .invalid("No Twitch channel by that name. Check the spelling, then choose Join."))
        FieldValidationRow(state: .failed(UserFacingError(
            id: "twitch.signInExpired",
            title: "Twitch sign-in expired",
            fix: "Reconnect, then choose Join.",
            severity: .warning
        )))
        FieldValidationRow(state: .failed(UserFacingError(
            id: "widget.tokenFormat",
            title: "Use exactly 64 hex characters",
            cause: "Only 0-9 and a-f are allowed.",
            severity: .error
        )))
    }
    .padding()
    .frame(width: 420)
}
