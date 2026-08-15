//
//  DebugLogViewerCard.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-14.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

#if DEBUG
import AppKit
import SwiftUI

/// DEBUG-only live tail of the app log.
///
/// The Debug tab previously showed the log file's path, size, and line count and
/// nothing else, so reading what the app had just done meant leaving the app for
/// Console.app or a text editor. This shows the log itself, filtered, while the
/// bug is happening.
///
/// Reading is incremental: ``LogTailCursor`` primes from the last
/// ``primingBytes`` and afterwards pulls only appended bytes, so the poll costs
/// a `stat` plus whatever was actually written. Parsing goes through
/// ``LogRecord``, the same reader the format is specified against, rather than a
/// second ad-hoc regex.
struct DebugLogViewerCard: View {

    /// How much history to show on open, and after a clear or rotation.
    private static let primingBytes: UInt64 = 256 * 1024

    /// Upper bound on retained records, so a chatty session cannot grow this
    /// view without limit. Oldest are dropped.
    private static let maxRecords = 2_000

    private static let pollInterval: Duration = .seconds(1)

    @State private var cursor = LogTailCursor()
    @State private var records: [LogRecord] = []
    @State private var minimumLevel: LogLevel?
    @State private var category: LogCategory?
    @State private var searchText = ""
    @State private var following = true
    @State private var expanded: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s4) {
            Text("Live tail of the app log. Updates while you use the app.")
                .font(.system(size: DSFont.Size.body))
                .foregroundStyle(.secondary)

            controls
            logList
            footer
        }
        .cardStyle()
        .task {
            while !Task.isCancelled {
                await pollOnce()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: DSSpace.s2) {
            HStack(spacing: DSSpace.s2) {
                Picker("Level", selection: $minimumLevel) {
                    Text("All").tag(LogLevel?.none)
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.rawValue.capitalized).tag(LogLevel?.some(level))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Toggle(isOn: $following) {
                    Label("Follow", systemImage: following ? "arrow.down.to.line" : "pause")
                }
                .toggleStyle(.button)
                .pointerCursor()
                .help("Keep scrolling to the newest line as it arrives.")
            }

            HStack(spacing: DSSpace.s2) {
                Picker("Category", selection: $category) {
                    Text("All categories").tag(LogCategory?.none)
                    ForEach(LogCategory.allCases, id: \.self) { value in
                        Text(value.rawValue).tag(LogCategory?.some(value))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 180)

                TextField("Search messages and fields", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .pointerCursor()
                }
            }
        }
    }

    // MARK: - List

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if filtered.isEmpty {
                        Text(records.isEmpty
                            ? "Nothing logged yet. Use the test-line buttons below."
                            : "No lines match the current filter.")
                            .font(.system(size: DSFont.Size.sm))
                            .foregroundStyle(.secondary)
                            .padding(DSSpace.s4)
                    } else {
                        ForEach(filtered) { record in
                            row(record)
                                .id(record.id)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 320)
            .background(
                RoundedRectangle(cornerRadius: DSRadius.sm)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.sm)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .onChange(of: records.count) {
                guard following, let last = filtered.last else { return }
                withAnimation(.easeOut(duration: DSMotion.Duration.fast)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func row(_ record: LogRecord) -> some View {
        VStack(alignment: .leading, spacing: DSSpace.s0) {
            HStack(alignment: .firstTextBaseline, spacing: DSSpace.s2) {
                Text(SharedFormatters.logTimestamp.string(from: record.timestamp))
                    .foregroundStyle(.secondary)
                Text(record.level.rawValue)
                    .foregroundStyle(color(for: record.level))
                    .frame(width: 44, alignment: .leading)
                Text(record.category)
                    .foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .leading)
                Text(record.message)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .font(.system(size: DSFont.Size.sm, design: .monospaced))
            .textSelection(.enabled)

            if expanded.contains(record.id) {
                VStack(alignment: .leading, spacing: DSSpace.s0) {
                    Text(record.location)
                        .foregroundStyle(.secondary)
                    ForEach(record.fields, id: \.key) { field in
                        Text("\(field.key) = \(field.value)")
                    }
                }
                .font(.system(size: DSFont.Size.xs, design: .monospaced))
                .textSelection(.enabled)
                .padding(.leading, DSSpace.s7)
                .padding(.top, DSSpace.s0)
            } else if !record.fields.isEmpty {
                Text(record.fields.map { "\($0.key)=\($0.value)" }.joined(separator: "  "))
                    .font(.system(size: DSFont.Size.xs, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.leading, DSSpace.s7)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, DSSpace.s2)
        .padding(.vertical, DSSpace.s0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if expanded.contains(record.id) {
                expanded.remove(record.id)
            } else {
                expanded.insert(record.id)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("\(filtered.count) of \(records.count) lines")
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                Pasteboard.copy(filtered.map(\.raw).joined(separator: "\n"))
            } label: {
                Label("Copy Visible", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .pointerCursor()
            .disabled(filtered.isEmpty)

            Button {
                records.removeAll()
                expanded.removeAll()
            } label: {
                Label("Clear View", systemImage: "eye.slash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .pointerCursor()
            .help("Clears this view only. The log file is untouched.")
            .disabled(records.isEmpty)
        }
    }

    // MARK: - Filtering

    private var filtered: [LogRecord] {
        let needle = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return records.filter { record in
            if let minimumLevel, severity(record.level) < severity(minimumLevel) { return false }
            if let category, record.category != category.rawValue { return false }
            guard !needle.isEmpty else { return true }
            if record.message.lowercased().contains(needle) { return true }
            return record.fields.contains {
                $0.key.lowercased().contains(needle) || $0.value.lowercased().contains(needle)
            }
        }
    }

    private func severity(_ level: LogLevel) -> Int {
        switch level {
        case .debug: return 0
        case .info: return 1
        case .warn: return 2
        case .error: return 3
        }
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .debug: return .secondary
        case .info: return DSColor.info
        case .warn: return DSColor.warning
        case .error: return DSColor.error
        }
    }

    // MARK: - Tailing

    /// Reads whatever has been appended since the last tick and appends the
    /// parsed records.
    private func pollOnce() async {
        let snapshot = cursor
        let result = await Task.detached(priority: .utility) {
            Self.readNewLines(cursor: snapshot)
        }.value

        cursor = result.cursor
        guard !result.lines.isEmpty else { return }

        // Parse the batch as one document so a continuation line folds into the
        // record above it instead of being dropped on its own.
        let parsed = LogRecord.parse(contents: result.lines.joined(separator: "\n"))
        guard !parsed.isEmpty else { return }

        // `LogRecord.parse(contents:)` numbers ids per batch. Re-key against the
        // running list so SwiftUI identity stays unique across polls.
        let base = (records.last?.id ?? -1) + 1
        records.append(contentsOf: parsed.enumerated().map { index, record in
            record.reidentified(base + index)
        })

        if records.count > Self.maxRecords {
            records.removeFirst(records.count - Self.maxRecords)
        }
    }

    /// File-side half of a poll. Runs off the main actor.
    ///
    /// `nonisolated` because the module defaults to `MainActor` isolation and this
    /// is called from `Task.detached` precisely so the file read never blocks the
    /// UI.
    nonisolated private static func readNewLines(cursor: LogTailCursor) -> (cursor: LogTailCursor, lines: [String]) {
        var cursor = cursor
        guard let url = Log.exportLogFile(),
              let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
        else { return (cursor, []) }

        guard let range = cursor.planRead(fileSize: size.uint64Value, primingBytes: primingBytes),
              let handle = try? FileHandle(forReadingFrom: url)
        else { return (cursor, []) }
        defer { try? handle.close() }

        try? handle.seek(toOffset: range.lowerBound)
        guard let data = try? handle.read(upToCount: Int(range.upperBound - range.lowerBound)),
              let text = String(data: data, encoding: .utf8)
        else { return (cursor, []) }

        return (cursor, cursor.consume(text))
    }
}

// MARK: - Identity

private extension LogRecord {
    /// Returns a copy carrying a new list identity.
    func reidentified(_ newID: Int) -> LogRecord {
        LogRecord(
            id: newID,
            timestamp: timestamp,
            level: level,
            category: category,
            location: location,
            message: message,
            fields: fields,
            raw: raw
        )
    }
}

#Preview {
    DebugLogViewerCard()
        .padding()
        .frame(width: 700)
}
#endif
