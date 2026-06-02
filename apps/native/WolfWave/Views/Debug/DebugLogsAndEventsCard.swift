//
//  DebugLogsAndEventsCard.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-16.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

#if DEBUG
import AppKit
import SwiftUI

/// DEBUG-only card combining log file utilities with a notification firehose for
/// manually posting any app-internal `NotificationCenter` event.
struct DebugLogsAndEventsCard: View {
    @State private var selectedNotification: String =
        AppConstants.Notifications.allNames.first ?? ""
    @State private var userInfoJSON: String = "{}"
    @State private var postStatus: String?
    @State private var refreshTick = 0

    /// Log file stats — loaded off-main via `.task(id: refreshTick)` so the
    /// card paints instantly. `logLineCount()` streams the entire log file
    /// through `fileQueue.sync` and would stall first paint on big logs.
    @State private var logURL: URL?
    @State private var logSize: Int64 = 0
    @State private var logLines: Int = 0
    @State private var logStatsLoaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            Text("Log file stats, export, and notification probes.")
                .font(.system(size: DSFont.Size.body))
                .foregroundStyle(.secondary)

            logsSection
            Divider()
            firehoseSection
        }
        .cardStyle()
        .task(id: refreshTick) {
            logStatsLoaded = false
            let stats = await Task.detached(priority: .userInitiated) {
                (url: Log.exportLogFile(), size: Log.logFileSize(), lines: Log.logLineCount())
            }.value
            await MainActor.run {
                logURL = stats.url
                logSize = stats.size
                logLines = stats.lines
                logStatsLoaded = true
            }
        }
    }

    // MARK: - Logs

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: DSSpace.s2) {
            Text("Log file")
                .sectionEyebrow()

            HStack(alignment: .top) {
                if logStatsLoaded {
                    VStack(alignment: .leading, spacing: DSSpace.s0) {
                        Text(logURL?.path ?? "(no log file)")
                            .font(.system(size: DSFont.Size.sm, design: .monospaced))
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Text("\(ByteFormatting.string(logSize)) · \(logLines) lines")
                            .font(.system(size: DSFont.Size.sm))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    LoadingRow(text: "Reading log file…")
                }
                Spacer()
                Button {
                    refreshTick &+= 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .pointerCursor()
            }

            HStack {
                Button {
                    if let url = logURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .pointerCursor()
                .disabled(logURL == nil)

                Button {
                    if let path = logURL?.path {
                        Pasteboard.copy(path)
                    }
                } label: {
                    Label("Copy Path", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .pointerCursor()
                .disabled(logURL == nil)

                Button(role: .destructive) {
                    Log.clearLogFile()
                    refreshTick &+= 1
                } label: {
                    Label("Clear Log", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .pointerCursor()
            }

            HStack {
                Button { Log.debug("Debug test line from Debug tab", category: "DevTools") } label: {
                    Text("Log .debug").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .pointerCursor()
                Button { Log.info("Info test line from Debug tab", category: "DevTools") } label: {
                    Text("Log .info").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .pointerCursor()
                Button { Log.warn("Warn test line from Debug tab", category: "DevTools") } label: {
                    Text("Log .warn").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .pointerCursor()
                Button { Log.error("Error test line from Debug tab", category: "DevTools") } label: {
                    Text("Log .error").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .pointerCursor()
            }
        }
    }

    // MARK: - Notification Firehose

    private var firehoseSection: some View {
        VStack(alignment: .leading, spacing: DSSpace.s2) {
            Text("Notification firehose")
                .sectionEyebrow()

            Text("Post any app notification with optional JSON userInfo.")
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.secondary)

            Picker("Name", selection: $selectedNotification) {
                ForEach(AppConstants.Notifications.allNames, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .pickerStyle(.menu)

            TextEditor(text: $userInfoJSON)
                .font(.system(size: DSFont.Size.sm, design: .monospaced))
                .frame(minHeight: 60, maxHeight: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            HStack {
                Button {
                    post()
                } label: {
                    Label("Post Notification", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .pointerCursor()

                Button {
                    userInfoJSON = "{}"
                    postStatus = nil
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .pointerCursor()
            }

            if let postStatus {
                Text(postStatus)
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(postStatus.hasPrefix("Posted") ? DSColor.success : DSColor.error)
            }
        }
    }

    private func post() {
        let trimmed = userInfoJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        var userInfo: [AnyHashable: Any] = [:]
        if !trimmed.isEmpty, trimmed != "{}" {
            guard let data = trimmed.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                postStatus = "Invalid JSON"
                return
            }
            userInfo = parsed
        }
        NotificationCenter.default.post(
            name: NSNotification.Name(selectedNotification),
            object: nil,
            userInfo: userInfo.isEmpty ? nil : userInfo
        )
        postStatus = "Posted \(selectedNotification)"
        Log.info("Posted notification \(selectedNotification) (dev)", category: "DevTools")
    }
}

#Preview {
    DebugLogsAndEventsCard()
        .padding()
        .frame(width: 600)
}
#endif
