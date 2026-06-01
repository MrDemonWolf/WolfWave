//
//  DebugInspectorsCard.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-16.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

#if DEBUG
import AppKit
import SwiftUI

/// DEBUG-only card for inspecting persistent state — UserDefaults values, Keychain
/// presence flags, and bundle/build metadata. Never displays Keychain values.
struct DebugInspectorsCard: View {
    @State private var refreshTick = 0
    @State private var filter: String = ""

    /// Keychain presence flags — loaded off-main via `.task(id: refreshTick)`
    /// so the card paints instantly. Each `KeychainService.load…()` call is a
    /// `SecItemCopyMatching` syscall; running 5 in `body` per render is wasteful.
    @State private var keychainPresence: [String: Bool] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            VStack(alignment: .leading, spacing: DSSpace.s1) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(DSColor.info)
                    Text("State Inspectors")
                        .sectionSubHeader()
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
                Text("Live state from Keychain and services. Read-only.")
                    .font(.system(size: DSFont.Size.body))
                    .foregroundStyle(.secondary)
            }

            bundleSection
            Divider()
            keychainSection
            Divider()
            userDefaultsSection
        }
        .id(refreshTick)
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
            await MainActor.run { keychainPresence = presence }
        }
    }

    // MARK: - Bundle / Build

    private var bundleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Bundle & build")
                .sectionEyebrow()

            inspectorRow("Version", bundleString("CFBundleShortVersionString"))
            inspectorRow("Build", bundleString("CFBundleVersion"))
            inspectorRow("Bundle ID", Bundle.main.bundleIdentifier ?? "—")
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Keychain")
                .sectionEyebrow()

            Text("Shows which credentials are stored. Values never displayed.")
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.secondary)

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
        }
    }

    // MARK: - UserDefaults

    private var userDefaultsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
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

    private func bundleString(_ key: String) -> String {
        Bundle.main.infoDictionary?[key] as? String ?? "—"
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
            "version": bundleString("CFBundleShortVersionString"),
            "build": bundleString("CFBundleVersion"),
            "bundleID": Bundle.main.bundleIdentifier ?? "",
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "locale": Locale.current.identifier,
            "configuration": configurationString,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
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
