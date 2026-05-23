//
//  DebugLogsAndEventsCard.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 5/16/26.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.indigo)
                Text("Logs & Events")
                    .sectionSubHeader()
            }

            logsSection
            Divider()
            firehoseSection
        }
        .id(refreshTick)
        .cardStyle()
    }

    // MARK: - Logs

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Log File")
                .font(.system(size: DSFont.Size.body, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            let url = Log.exportLogFile()
            let size = Log.logFileSize()
            let lines = Log.logLineCount()

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(url?.path ?? "(no log file)")
                        .font(.system(size: DSFont.Size.sm, design: .monospaced))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Text("\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) · \(lines) lines")
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(.secondary)
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
                    if let url {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .pointerCursor()
                .disabled(url == nil)

                Button {
                    if let path = url?.path {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(path, forType: .string)
                    }
                } label: {
                    Label("Copy Path", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .pointerCursor()
                .disabled(url == nil)

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
        VStack(alignment: .leading, spacing: 8) {
            Text("Notification Firehose")
                .font(.system(size: DSFont.Size.body, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

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
                    .foregroundStyle(postStatus.hasPrefix("Posted") ? .green : .red)
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
