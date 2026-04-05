//
//  ConnectionTestButton.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 4/4/26.
//

import SwiftUI

/// Reusable inline pill button for testing a service connection.
///
/// Cycles through idle → testing → success/failure, then auto-resets after 3 seconds.
/// Use for Discord, Twitch, or any service that can report a connection result.
///
/// Usage:
/// ```swift
/// ConnectionTestButton(label: "Check Discord", icon: "antenna.radiowaves.left.and.right") { completion in
///     service.testConnection(completion: completion)
/// }
/// ```
struct ConnectionTestButton: View {

    // MARK: - Properties

    let label: String
    let icon: String
    let action: (@escaping (Bool) -> Void) -> Void

    // MARK: - State

    enum TestResult: Equatable {
        case idle, testing, success, failure
    }

    @State private var result: TestResult = .idle
    @State private var clearTask: Task<Void, Never>?

    // MARK: - Body

    var body: some View {
        Button {
            runTest()
        } label: {
            switch result {
            case .idle:
                Label(label, systemImage: icon)
                    .font(.system(size: 12, weight: .medium))
            case .testing:
                HStack(spacing: 6) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                    Text("Testing...")
                        .font(.system(size: 12))
                }
            case .success:
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
            case .failure:
                Label("Failed", systemImage: "xmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .buttonStyle(.bordered)
        .tint(buttonTint)
        .controlSize(.small)
        .frame(minWidth: 130)
        .disabled(result == .testing)
        .pointerCursor()
        .accessibilityValue(accessibilityValue)
    }

    // MARK: - Helpers

    private var buttonTint: Color? {
        switch result {
        case .success: return .green
        case .failure: return .red
        default: return nil
        }
    }

    private var accessibilityValue: String {
        switch result {
        case .idle:    return "Not tested"
        case .testing: return "Testing"
        case .success: return "Connected"
        case .failure: return "Failed"
        }
    }

    private func runTest() {
        result = .testing
        action { success in
            withAnimation {
                result = success ? .success : .failure
            }
            scheduleReset()
        }
    }

    private func scheduleReset() {
        clearTask?.cancel()
        clearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation {
                result = .idle
            }
        }
    }
}
