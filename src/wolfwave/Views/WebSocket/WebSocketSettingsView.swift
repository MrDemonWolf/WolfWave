//
//  WebSocketSettingsView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import SwiftUI

/// Stream overlay settings: server port, enable/disable toggle, status, and widget URL.
struct WebSocketSettingsView: View {
    // MARK: - User Settings

    @AppStorage(AppConstants.UserDefaults.websocketEnabled)
    private var websocketEnabled = false

    @AppStorage(AppConstants.UserDefaults.websocketServerPort)
    private var storedPort: Int = Int(AppConstants.WebSocketServer.defaultPort)

    // MARK: - State

    @State private var portText: String = ""
    @State private var serverState: WebSocketServerService.ServerState = .stopped
    @State private var clientCount: Int = 0
    @State private var copiedWidgetURL = false
    @State private var copiedConnectionURL = false

    private var widgetURL: String {
        #if DEBUG
        "http://localhost:3000/widget/?port=\(storedPort)"
        #else
        "https://mrdemonwolf.github.io/wolfwave/widget/?port=\(storedPort)"
        #endif
    }

    private var connectionURL: String {
        "ws://localhost:\(storedPort)"
    }

    private var isPortValid: Bool {
        guard let port = UInt16(portText) else { return false }
        return port >= AppConstants.WebSocketServer.minPort
            && port <= AppConstants.WebSocketServer.maxPort
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 10) {
                    Text("OBS Widget")
                        .font(.system(size: 17, weight: .semibold))

                    Spacer()

                    statusChip
                        .animation(.easeInOut(duration: 0.2), value: serverState)
                        .animation(.easeInOut(duration: 0.2), value: clientCount)
                }

                Text("Display your currently playing track as an overlay on your stream.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Port")
                            .font(.system(size: 13, weight: .medium))
                        Text(verbatim: "Default: \(AppConstants.WebSocketServer.defaultPort)")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    TextField("Port", text: $portText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.center)
                        .accessibilityLabel("Server port")
                        .accessibilityIdentifier("websocketPortField")
                        .onSubmit {
                            applyPort()
                        }
                }

                if !portText.isEmpty && !isPortValid {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                        Text(verbatim: "Port must be between \(AppConstants.WebSocketServer.minPort) and \(AppConstants.WebSocketServer.maxPort).")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.red)
                }

                Divider()
                    .padding(.vertical, 2)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable WebSocket server")
                            .font(.system(size: 13, weight: .medium))
                        Text("Broadcast now playing data to connected overlays")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Toggle("", isOn: $websocketEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .pointerCursor()
                        .accessibilityLabel("Enable WebSocket server")
                        .accessibilityIdentifier("websocketEnabledToggle")
                        .onChange(of: websocketEnabled) { _, newValue in
                            notifyServerSettingChanged()
                        }
                }

                Divider()
                    .padding(.vertical, 2)

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connection URL")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(connectionURL)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    Spacer()

                    Button {
                        copyToClipboard(connectionURL)
                        copiedConnectionURL = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copiedConnectionURL = false
                        }
                    } label: {
                        Image(systemName: copiedConnectionURL ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Copy connection URL")
                    .accessibilityIdentifier("copyConnectionURLButton")
                }
            }
            .padding(AppConstants.SettingsUI.cardPadding)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))

            Divider()
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.inset.filled.and.person.filled")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(nsColor: .controlAccentColor))
                        Text("Browser Source URL")
                            .font(.system(size: 15, weight: .semibold))
                    }

                    Text("Copy this URL and paste it into a Browser Source in OBS.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(widgetURL)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        copyToClipboard(widgetURL)
                        copiedWidgetURL = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copiedWidgetURL = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copiedWidgetURL ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11))
                            Text(copiedWidgetURL ? "Copied" : "Copy URL")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Copy widget URL")
                    .accessibilityIdentifier("copyWidgetURLButton")
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                    Text("Set the Browser Source size to **500 x 120** for best results. Enable \"Shutdown source when not visible\" for clean reconnects.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(AppConstants.SettingsUI.cardPadding)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))
        }
        .onAppear {
            portText = String(storedPort)
            refreshServerState()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSNotification.Name(AppConstants.Notifications.websocketServerStateChanged)
            )
        ) { notification in
            if let rawValue = notification.userInfo?["state"] as? String,
               let state = WebSocketServerService.ServerState(rawValue: rawValue) {
                serverState = state
            }
            if let clients = notification.userInfo?["clients"] as? Int {
                clientCount = clients
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var statusChip: some View {
        switch serverState {
        case .listening:
            if clientCount > 0 {
                StatusChip(
                    text: "\(clientCount) connected",
                    color: .green
                )
            } else {
                StatusChip(text: "Listening", color: .green)
            }
        case .starting:
            StatusChip(text: "Starting", color: .orange)
        case .error:
            StatusChip(text: "Error", color: .red)
        case .stopped:
            StatusChip(text: "Stopped", color: .gray)
        }
    }

    // MARK: - Helpers

    private func refreshServerState() {
        if let appDelegate = AppDelegate.shared {
            serverState = appDelegate.websocketServer?.state ?? .stopped
            clientCount = appDelegate.websocketServer?.connectionCount ?? 0
        }
    }

    private func applyPort() {
        guard isPortValid, let port = UInt16(portText) else { return }
        storedPort = Int(port)
        notifyServerSettingChanged(port: port)
    }

    private func notifyServerSettingChanged(port: UInt16? = nil) {
        var userInfo: [String: Any] = [:]
        if let port {
            userInfo["port"] = port
        }
        NotificationCenter.default.post(
            name: NSNotification.Name(AppConstants.Notifications.websocketServerChanged),
            object: nil,
            userInfo: userInfo.isEmpty ? nil : userInfo
        )
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Status Chip

private struct StatusChip: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview {
    WebSocketSettingsView()
        .padding()
}
