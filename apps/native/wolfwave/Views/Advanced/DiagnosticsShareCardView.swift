//
//  DiagnosticsShareCardView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 5/22/26.
//

import AppKit
import SwiftUI

// MARK: - Diagnostics Share Card View

/// Advanced-settings card for the privacy-preserving, on-device diagnostics
/// opt-in. Surfaces the MetricKit toggle, the anonymous launch count, and the
/// latest diagnostic summary. No data ever leaves the device.
struct DiagnosticsShareCardView: View {

    // MARK: - State

    @AppStorage(AppConstants.UserDefaults.shareDiagnosticsEnabled)
    private var shareEnabled = false

    @State private var launchCount = DiagnosticsService.shared.launchCount
    @State private var summary = DiagnosticsService.shared.diagnosticSummary

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            VStack(alignment: .leading, spacing: DSSpace.s1) {
                Text("Diagnostics & Privacy")
                    .font(.system(size: DSFont.Size.base, weight: .semibold))

                Text("WolfWave can collect crash and performance diagnostics using Apple's on-device MetricKit. Reports stay on your Mac — nothing is ever uploaded.")
                    .font(.system(size: DSFont.Size.body))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(isOn: $shareEnabled) {
                Text("Collect on-device diagnostics")
                    .font(.system(size: DSFont.Size.body, weight: .medium))
            }
            .toggleStyle(.switch)
            .onChange(of: shareEnabled) { _, enabled in
                DiagnosticsService.shared.setEnabled(enabled)
            }
            .accessibilityIdentifier("shareDiagnosticsToggle")

            Divider()

            metricRow("App launches", "\(launchCount)")

            if let summary {
                metricRow("Last diagnostics", summary)
            }

            Button {
                revealPayloadFolder()
            } label: {
                Label("Reveal Diagnostics Folder", systemImage: "folder")
                    .font(.system(size: DSFont.Size.body, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .pointerCursor()
            .accessibilityHint("Opens the on-device folder where diagnostic reports are stored")
        }
        .cardStyle()
    }

    // MARK: - Helpers

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: DSFont.Size.body))
            Spacer()
            Text(value)
                .font(.system(size: DSFont.Size.body, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    /// Creates (if needed) and reveals the on-device diagnostics folder in Finder.
    private func revealPayloadFolder() {
        let dir = DiagnosticsService.shared.payloadDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }
}
