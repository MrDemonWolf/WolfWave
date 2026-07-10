//
//  DebugInspectorsCard.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-16.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

#if DEBUG
import AppKit
import Combine
import SwiftUI

/// DEBUG-only card for inspecting persistent state: UserDefaults values, Keychain
/// presence flags, and bundle/build metadata. Never displays Keychain values.
struct DebugInspectorsCard: View {
    @State private var refreshTick = 0
    @State private var filter: String = ""

    /// Keychain presence flags, loaded off-main via `.task(id: refreshTick)`
    /// so the card paints instantly. Each `KeychainService.load…()` call is a
    /// `SecItemCopyMatching` syscall; running 5 in `body` per render is wasteful.
    @State private var keychainPresence: [String: Bool] = [:]
    @State private var keychainLoaded = false

    /// Backstop poll interval. UserDefaults edits surface instantly via
    /// `didChangeNotification`, but the Keychain has no change notification,
    /// so a low-frequency tick keeps presence flags honest after an out-of-app
    /// login/logout or a token rotation the Twitch notification didn't cover.
    private static let pollInterval: Duration = .seconds(2)

    /// Any UserDefaults write across the app fires `didChangeNotification` on
    /// the writing thread, and playback state can write it rapidly. Throttle to
    /// the main run loop so each burst yields at most one `@State` bump (kept on
    /// main, so the Keychain reload it triggers can't fire faster than ~2.5/s).
    private let defaultsChanged = NotificationCenter.default
        .publisher(for: UserDefaults.didChangeNotification)
        .throttle(for: .milliseconds(400), scheduler: RunLoop.main, latest: true)

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            HStack(alignment: .top, spacing: DSSpace.s2) {
                Text("Live state from Keychain and services. Read-only.")
                    .font(.system(size: DSFont.Size.body))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    refreshTick &+= 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .pointerCursor()
                .help("Refresh values")
            }

            bundleSection
            Divider()
            keychainSection
            Divider()
            userDefaultsSection
        }
        .cardStyle()
        .task(id: refreshTick) {
            let presence = await Task.detached(priority: .userInitiated) {
                [
                    "token": KeychainService.loadToken() != nil,
                    "twitchToken": KeychainService.loadTwitchToken() != nil,
                    "twitchUsername": KeychainService.loadTwitchUsername() != nil,
                    "twitchBotUserID": KeychainService.loadTwitchBotUserID() != nil,
                    "twitchChannelID": KeychainService.loadTwitchChannelID() != nil,
                ]
            }.value
            await MainActor.run {
                keychainPresence = presence
                keychainLoaded = true
            }
        }
        // Twitch login writes its token + IDs to the Keychain on a background
        // path; without this the card keeps showing the pre-login presence until
        // the user hits refresh. Bumping the tick re-runs `.task(id:)` above.
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.twitchConnectionStateChanged)) { _ in
            refreshTick &+= 1
        }
        // A UserDefaults write anywhere in the app (toggles in other panes,
        // service state) bumps the tick, so the defaults rows reflect edits live
        // without waiting on the poll. Throttled + main-delivered above.
        .onReceive(defaultsChanged) { _ in
            refreshTick &+= 1
        }
        // Backstop poll for state with no change notification (Keychain).
        // Structured concurrency cancels the loop when the card disappears,
        // matching DebugMetricsCard; no subscription to tear down.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled else { break }
                refreshTick &+= 1
            }
        }
    }

    // MARK: - Bundle / Build

    private var bundleSection: some View {
        VStack(alignment: .leading, spacing: DSSpace.s1h) {
            Text("Bundle & build")
                .sectionEyebrow()

            inspectorRow("Version", AppConstants.AppInfo.shortVersion)
            inspectorRow("Build", AppConstants.AppInfo.buildNumber)
            inspectorRow("Bundle ID", Bundle.main.bundleIdentifier ?? "N/A")
            inspectorRow("macOS", ProcessInfo.processInfo.operatingSystemVersionString)
            inspectorRow("Locale", Locale.current.identifier)
            inspectorRow("Config", configurationString)

            HStack {
                Spacer()
                Button {
                    Pasteboard.copy(buildInfoJSON)
                } label: {
                    Label("Copy as JSON", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .pointerCursor()
            }
        }
    }

    // MARK: - Keychain

    private var keychainSection: some View {
        VStack(alignment: .leading, spacing: DSSpace.s1h) {
            Text("Keychain")
                .sectionEyebrow()

            Text("Shows which credentials are stored. Values never displayed.")
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.secondary)

            if keychainLoaded {
                keychainRow("WebSocket Auth Token", present: keychainPresence["token"] ?? false) {
                    KeychainService.deleteToken()
                }
                keychainRow("Twitch OAuth Token", present: keychainPresence["twitchToken"] ?? false) {
                    KeychainService.deleteTwitchToken()
                }
                keychainRow("Twitch Username", present: keychainPresence["twitchUsername"] ?? false) {
                    KeychainService.deleteTwitchUsername()
                }
                keychainRow("Twitch Bot User ID", present: keychainPresence["twitchBotUserID"] ?? false) {
                    KeychainService.deleteTwitchBotUserID()
                }
                keychainRow("Twitch Channel ID", present: keychainPresence["twitchChannelID"] ?? false) {
                    KeychainService.deleteTwitchChannelID()
                }
            } else {
                LoadingRow(text: "Reading Keychain…")
            }
        }
    }

    // MARK: - UserDefaults

    private var userDefaultsSection: some View {
        VStack(alignment: .leading, spacing: DSSpace.s1h) {
            HStack {
                Text("User defaults")
                    .sectionEyebrow()
                Spacer()
                TextField("Filter", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 160)
            }

            let keys = AppConstants.UserDefaults.allKeys
                .filter { filter.isEmpty || $0.localizedCaseInsensitiveContains(filter) }
                .sorted()

            ForEach(keys, id: \.self) { key in
                userDefaultsRow(key: key)
            }
        }
    }

    // MARK: - Row Builders

    private func inspectorRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: DSFont.Size.body))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.system(size: DSFont.Size.body, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func keychainRow(_ label: String, present: Bool, onDelete: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: present ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(present ? DSColor.success : .secondary)
            Text(label)
                .font(.system(size: DSFont.Size.body))
            Spacer()
            if present {
                Button {
                    onDelete()
                    refreshTick &+= 1
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(DSColor.error)
                }
                .buttonStyle(.borderless)
                .pointerCursor()
                .help("Delete from Keychain")
            }
        }
    }

    private func userDefaultsRow(key: String) -> some View {
        _ = refreshTick
        let value = UserDefaults.standard.object(forKey: key)
        return HStack(alignment: .top, spacing: DSSpace.s2) {
            Text(key)
                .font(.system(size: DSFont.Size.sm, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 200, alignment: .leading)
            Text(formatValue(value))
                .font(.system(size: DSFont.Size.sm, design: .monospaced))
                .foregroundStyle(value == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                UserDefaults.standard.removeObject(forKey: key)
                refreshTick &+= 1
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .pointerCursor()
            .help("Remove key")
            .disabled(value == nil)
        }
    }

    // MARK: - Helpers

    /// Reads an arbitrary Info.plist string for ad-hoc inspector rows. Version
    /// and build intentionally use `AppConstants.AppInfo` instead so their
    /// fallbacks match the rest of the app.
    private func bundleString(_ key: String) -> String {
        Bundle.main.infoDictionary?[key] as? String ?? "N/A"
    }

    private var configurationString: String {
        #if DEBUG
        return "DEBUG"
        #else
        return "RELEASE"
        #endif
    }

    private var buildInfoJSON: String {
        let dict: [String: String] = [
            "version": AppConstants.AppInfo.shortVersion,
            "build": AppConstants.AppInfo.buildNumber,
            "bundleID": Bundle.main.bundleIdentifier ?? "",
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "locale": Locale.current.identifier,
            "configuration": configurationString,
        ]
        // A `[String: String]` is always a valid JSON object; the guard is here
        // for symmetry with the other call sites so the pattern reads the same.
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }

    private func formatValue(_ value: Any?) -> String {
        guard let value else { return "<unset>" }
        switch value {
        case let bool as Bool: return bool ? "true" : "false"
        case let string as String: return "\"\(string)\""
        case let number as NSNumber: return number.stringValue
        default: return String(describing: value)
        }
    }
}

#Preview {
    DebugInspectorsCard()
        .padding()
        .frame(width: 600)
}
#endif
