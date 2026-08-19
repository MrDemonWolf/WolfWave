//
//  AsyncActionButton.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-18.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// A button that owns the lifecycle of one `async` action: it swaps its label
/// for a spinner while the work runs, disables itself so the action cannot be
/// double-fired, and shows a brief checkmark on success.
///
/// This is the macOS-native shape of the pattern (App Store "Get", Xcode,
/// System Settings): the spinner *replaces* the label rather than sitting
/// beside it, and the control never changes width between states. The width
/// lock comes from `stableWidth(ghosts:)`, which measures the idle label, the
/// spinner, and the checkmark and pins the button to the widest of the three.
///
/// Error *presentation* stays with the caller. A thrown error returns the
/// button to idle without a checkmark; the surrounding view is expected to own
/// its own `CalloutBanner` or status string, as the settings panes already do.
///
/// ```swift
/// AsyncActionButton(title: "Join Channel", systemImage: "checkmark.circle.fill") {
///     try await viewModel.joinChannel()
/// }
/// ```
struct AsyncActionButton: View {

    // MARK: - Nested Types

    /// Visual treatment. Mirrors the styles the settings panes already use;
    /// applied through a private `ViewModifier` because `buttonStyle` returns
    /// different opaque types per branch.
    enum Style {
        case bordered
        case borderedProminent
        case borderless
    }

    /// Where the button is in the action lifecycle.
    private enum Phase: Equatable {
        case idle
        case running
        case succeeded
    }

    // MARK: - Properties

    /// Idle label text. Also the VoiceOver label.
    let title: String

    /// Optional leading SF Symbol for the idle label.
    var systemImage: String? = nil

    /// Set `.destructive` to tint the label with `DSColor.error`. Matches
    /// `DestructiveButton`: the red lives on the label, never as a `.tint`
    /// that would fill the whole control.
    var role: ButtonRole? = nil

    var style: Style = .bordered

    var size: ControlSize = .small

    /// Caller-owned disable reason (an unmet precondition, a dirty-state gate,
    /// a view-model teardown flag). Combined with the in-flight disable.
    var isDisabled: Bool = false

    /// Semantic tint for the control (green "approve", orange "hold"). Left nil
    /// for the neutral bordered look most settings rows use.
    var tint: Color? = nil

    /// Label point size. `DSFont.Size.body` matches the settings panes;
    /// `DSFont.Size.sm` matches the denser queue rows.
    var labelSize: CGFloat = DSFont.Size.body

    /// Stretch to the container's width, as the debug cards and full-width
    /// action rows do. A stretched button cannot resize when the label swaps,
    /// so it skips the `stableWidth` lock entirely.
    var fillsWidth: Bool = false

    /// Set `false` for actions whose result is obvious on screen anyway, so the
    /// checkmark would be noise.
    var showsSuccess: Bool = true

    /// How long the success checkmark holds before reverting to idle.
    var successDuration: TimeInterval = 2.0

    var accessibilityIdentifier: String? = nil

    /// The work to run. A thrown error returns the button to idle.
    let action: () async throws -> Void

    @State private var phase: Phase = .idle
    @State private var task: Task<Void, Never>?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        let button = Button(role: role, action: run) {
            label
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: DSMotion.Duration.base),
                    value: phase
                )
        }
        .modifier(AsyncActionButtonStyleModifier(style: style, size: size))
        .tint(tint)
        .disabled(isDisabled || phase == .running)
        .pointerCursor()
        .modifier(AsyncActionButtonWidthModifier(fillsWidth: fillsWidth, ghosts: {
            idleLabel
            spinnerLabel
            successLabel
        }))
        .onDisappear {
            task?.cancel()
            task = nil
        }
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)

        button.accessibilityIdentifier(optional: accessibilityIdentifier)
    }

    // MARK: - Private Views

    @ViewBuilder
    private var label: some View {
        switch phase {
        case .idle:
            idleLabel
        case .running:
            spinnerLabel
        case .succeeded:
            successLabel
        }
    }

    private var idleLabel: some View {
        Group {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .font(.system(size: labelSize, weight: .medium))
        .foregroundStyle(labelStyle)
        .frame(maxWidth: fillsWidth ? .infinity : nil)
    }

    private var spinnerLabel: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .controlSize(.mini)
            .accessibilityHidden(true)
    }

    private var successLabel: some View {
        Image(systemName: "checkmark")
            .font(.system(size: labelSize, weight: .semibold))
            .foregroundStyle(DSColor.success)
            .accessibilityHidden(true)
    }

    /// Destructive labels carry the red themselves. A tinted control lets the
    /// button style colour its own label, so we stay out of the way there.
    private var labelStyle: AnyShapeStyle {
        if role == .destructive {
            AnyShapeStyle(DSColor.error)
        } else if tint != nil {
            AnyShapeStyle(.tint)
        } else {
            AnyShapeStyle(.primary)
        }
    }

    private var accessibilityValue: String {
        switch phase {
        case .idle: ""
        case .running: "Working"
        case .succeeded: "Done"
        }
    }

    // MARK: - Private Helpers

    /// Starts the action. Re-entrant taps are dropped: the button is disabled
    /// while running, and this guard covers the keyboard-activation race.
    private func run() {
        guard phase != .running else { return }
        task?.cancel()
        phase = .running
        task = Task { @MainActor in
            do {
                try await action()
            } catch {
                phase = .idle
                return
            }
            guard !Task.isCancelled else { return }
            guard showsSuccess else {
                phase = .idle
                return
            }
            phase = .succeeded
            try? await Task.sleep(for: .seconds(successDuration))
            guard !Task.isCancelled else { return }
            phase = .idle
        }
    }
}

// MARK: - Width Modifier

/// Applies the `stableWidth` lock only when the button sizes to its label. A
/// `fillsWidth` button takes the container's width, and `stableWidth` ends in
/// `fixedSize(horizontal: true)`, which would fight that.
private struct AsyncActionButtonWidthModifier<Ghosts: View>: ViewModifier {
    let fillsWidth: Bool
    @ViewBuilder let ghosts: () -> Ghosts

    func body(content: Content) -> some View {
        if fillsWidth {
            content.frame(maxWidth: .infinity)
        } else {
            content.stableWidth(ghosts: ghosts)
        }
    }
}

// MARK: - Style Modifier

private struct AsyncActionButtonStyleModifier: ViewModifier {
    let style: AsyncActionButton.Style
    let size: ControlSize

    func body(content: Content) -> some View {
        switch style {
        case .bordered:
            content.buttonStyle(.bordered).controlSize(size)
        case .borderedProminent:
            content.buttonStyle(.borderedProminent).controlSize(size)
        case .borderless:
            content.buttonStyle(.borderless).controlSize(size)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: DSSpace.s4) {
        AsyncActionButton(title: "Join Channel", systemImage: "checkmark.circle.fill") {
            try await Task.sleep(for: .seconds(2))
        }
        AsyncActionButton(title: "Fetch link", style: .borderedProminent) {
            try await Task.sleep(for: .seconds(2))
        }
        AsyncActionButton(title: "Clear Queue", role: .destructive) {
            try await Task.sleep(for: .seconds(1))
        }
        AsyncActionButton(title: "Always fails") {
            try await Task.sleep(for: .seconds(1))
            throw CocoaError(.fileNoSuchFile)
        }
        AsyncActionButton(title: "Blocked", isDisabled: true) {}
    }
    .padding()
    .frame(width: 320)
}
