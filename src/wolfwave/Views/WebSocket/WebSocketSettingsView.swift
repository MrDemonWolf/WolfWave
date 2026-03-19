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

    @AppStorage(AppConstants.UserDefaults.widgetHTTPEnabled)
    private var widgetHTTPEnabled = false

    @AppStorage(AppConstants.UserDefaults.widgetPort)
    private var storedWidgetPort: Int = Int(AppConstants.WebSocketServer.widgetDefaultPort)

    @AppStorage(AppConstants.UserDefaults.widgetTheme)
    private var widgetTheme = "Default"

    @AppStorage(AppConstants.UserDefaults.widgetLayout)
    private var widgetLayout = "Horizontal"

    @AppStorage(AppConstants.UserDefaults.widgetTextColor)
    private var widgetTextColor = "#FFFFFF"

    @AppStorage(AppConstants.UserDefaults.widgetBackgroundColor)
    private var widgetBackgroundColor = "#1A1A2E"

    @AppStorage(AppConstants.UserDefaults.widgetFontFamily)
    private var widgetFontFamily = "System Default"

    // MARK: - State

    @State private var fontSearch = ""
    @State private var portText: String = ""
    @State private var widgetPortText: String = ""
    @State private var serverState: WebSocketServerService.ServerState = .stopped
    @State private var clientCount: Int = 0
    @State private var copiedWidgetURL = false
    @State private var copiedConnectionURL = false

    private let cardPadding = AppConstants.SettingsUI.cardPadding

    private var widgetURL: String {
        let port = storedWidgetPort > 0 ? storedWidgetPort : Int(AppConstants.WebSocketServer.widgetDefaultPort)
        return "http://localhost:\(port)"
    }

    private var connectionURL: String {
        "ws://localhost:\(storedPort)"
    }

    private var isPortValid: Bool {
        guard let port = UInt16(portText) else { return false }
        return port >= AppConstants.WebSocketServer.minPort
            && port <= AppConstants.WebSocketServer.maxPort
    }

    private var isWidgetPortValid: Bool {
        guard let port = UInt16(widgetPortText) else { return false }
        return port >= AppConstants.WebSocketServer.minPort
            && port <= AppConstants.WebSocketServer.maxPort
    }

    private var availableFonts: [String] {
        let allFonts = NSFontManager.shared.availableFontFamilies.sorted()
        if fontSearch.isEmpty { return allFonts }
        return allFonts.filter { $0.localizedCaseInsensitiveContains(fontSearch) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.SettingsUI.sectionSpacing) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 10) {
                    Text("Stream Widgets")
                        .font(.system(size: 17, weight: .semibold))

                    Spacer()

                    statusChip
                        .animation(.easeInOut(duration: 0.2), value: serverState)
                        .animation(.easeInOut(duration: 0.2), value: clientCount)
                }

                Text("Show your current song on your stream using a widget.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            serverSettingsCard

            browserSourceCard

            widgetAppearanceCard
        }
        .onAppear {
            portText = String(storedPort)
            widgetPortText = String(storedWidgetPort)
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

    // MARK: - Server Settings Card

    private var serverSettingsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Enable toggle row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Widget Server")
                        .font(.system(size: 13, weight: .medium))
                    Text("Required for the widget to work")
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
            .padding(.horizontal, cardPadding)
            .padding(.vertical, 12)

            Divider()
                .padding(.leading, cardPadding)

            // Port row
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
            .padding(.horizontal, cardPadding)
            .padding(.vertical, 12)

            if !portText.isEmpty && !isPortValid {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                    Text(verbatim: "Port must be between \(AppConstants.WebSocketServer.minPort) and \(AppConstants.WebSocketServer.maxPort).")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.red)
                .padding(.horizontal, cardPadding)
                .padding(.bottom, 8)
            }

            Divider()
                .padding(.leading, cardPadding)

            // Connection URL row
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local Address")
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
            .padding(.horizontal, cardPadding)
            .padding(.vertical, 12)

        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))
    }

    // MARK: - Browser Source Card

    private var browserSourceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.inset.filled.and.person.filled")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(nsColor: .controlAccentColor))
                    Text("OBS Setup")
                        .font(.system(size: 15, weight: .semibold))
                }

                Text("Copy this link and add it as a 'Browser' source in OBS.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, cardPadding)
            .padding(.top, cardPadding)
            .padding(.bottom, 12)

            Divider()
                .padding(.leading, cardPadding)

            // Widget HTTP server toggle row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Visual Widget")
                        .font(.system(size: 13, weight: .medium))
                    Text("This creates the webpage for your stream")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Toggle("", isOn: $widgetHTTPEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .pointerCursor()
                    .disabled(!websocketEnabled)
                    .accessibilityLabel("Enable Widget Web Server")
                    .accessibilityIdentifier("widgetHTTPEnabledToggle")
                    .onChange(of: widgetHTTPEnabled) { _, _ in
                        NotificationCenter.default.post(
                            name: NSNotification.Name(AppConstants.Notifications.widgetHTTPServerChanged),
                            object: nil
                        )
                    }
            }
            .padding(.horizontal, cardPadding)
            .padding(.vertical, 12)
            .opacity(websocketEnabled ? 1.0 : 0.5)

            Divider()
                .padding(.leading, cardPadding)

            // Widget port row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Widget Port (Advanced)")
                        .font(.system(size: 13, weight: .medium))
                    Text(verbatim: "Default: \(AppConstants.WebSocketServer.widgetDefaultPort)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                TextField("Port", text: $widgetPortText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .multilineTextAlignment(.center)
                    .disabled(!websocketEnabled || !widgetHTTPEnabled)
                    .accessibilityLabel("Widget server port")
                    .accessibilityIdentifier("widgetPortField")
                    .onSubmit {
                        applyWidgetPort()
                    }
            }
            .padding(.horizontal, cardPadding)
            .padding(.vertical, 12)
            .opacity(websocketEnabled && widgetHTTPEnabled ? 1.0 : 0.5)

            if !widgetPortText.isEmpty && !isWidgetPortValid {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                    Text(verbatim: "Port must be between \(AppConstants.WebSocketServer.minPort) and \(AppConstants.WebSocketServer.maxPort).")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.red)
                .padding(.horizontal, cardPadding)
                .padding(.bottom, 8)
            }

            Divider()
                .padding(.leading, cardPadding)

            // Browser Source URL
            VStack(alignment: .leading, spacing: 8) {
                Text(widgetURL)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
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
                            Text(copiedWidgetURL ? "Copied" : "Copy Link")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Copy widget URL")
                    .accessibilityIdentifier("copyWidgetURLButton")

                    Button {
                        if let url = URL(string: widgetURL) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "safari")
                                .font(.system(size: 11))
                            Text("Open")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!websocketEnabled || !widgetHTTPEnabled)
                    .accessibilityLabel("Open widget in browser")
                    .accessibilityIdentifier("openWidgetURLButton")
                }
            }
            .padding(.horizontal, cardPadding)
            .padding(.vertical, 12)

            // Info tip
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.blue)
                Text("In OBS, set the Width and Height to **\(AppConstants.Widget.recommendedDimensionsText)** for best results. Enable \"Shutdown source when not visible\" for clean reconnects.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, cardPadding)
            .padding(.bottom, cardPadding)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))
    }

    // MARK: - Widget Appearance Card

    private var widgetAppearanceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "paintbrush.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(nsColor: .controlAccentColor))
                    Text("Widget Appearance")
                        .font(.system(size: 15, weight: .semibold))
                }

                Text("Tweak colors, fonts, and layout for your overlay.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, cardPadding)
            .padding(.top, cardPadding)
            .padding(.bottom, 12)

            Divider()
                .padding(.leading, cardPadding)

            // Theme row
            HStack(spacing: 12) {
                Text("Theme")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Picker("", selection: $widgetTheme) {
                    ForEach(AppConstants.Widget.themes, id: \.self) { theme in
                        Text(theme).tag(theme)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
                .accessibilityLabel("Widget theme")
                .accessibilityIdentifier("widgetThemePicker")
                .onChange(of: widgetTheme) { _, _ in
                    broadcastWidgetConfig()
                }
            }
            .padding(.horizontal, cardPadding)
            .padding(.vertical, 12)

            Divider()
                .padding(.leading, cardPadding)

            // Layout row
            HStack(spacing: 12) {
                Text("Layout")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Picker("", selection: $widgetLayout) {
                    ForEach(AppConstants.Widget.layouts, id: \.self) { layout in
                        Text(layout).tag(layout)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
                .accessibilityLabel("Widget layout")
                .accessibilityIdentifier("widgetLayoutPicker")
                .onChange(of: widgetLayout) { _, _ in
                    broadcastWidgetConfig()
                }
            }
            .padding(.horizontal, cardPadding)
            .padding(.vertical, 12)

            if widgetTheme == "Default" || widgetTheme == "Glass" {
                Divider()
                    .padding(.leading, cardPadding)

                // Text Color row
                HStack(spacing: 12) {
                    Text("Text Color")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: widgetTextColor) ?? .white)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
                        TextField("#FFFFFF", text: $widgetTextColor)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                            .font(.system(size: 12, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .accessibilityLabel("Widget text color")
                            .accessibilityIdentifier("widgetTextColorField")
                            .onSubmit { broadcastWidgetConfig() }
                    }
                }
                .padding(.horizontal, cardPadding)
                .padding(.vertical, 12)

                Divider()
                    .padding(.leading, cardPadding)

                // Background Color row
                HStack(spacing: 12) {
                    Text("Background Color")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: widgetBackgroundColor) ?? .black)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
                        TextField("#1A1A2E", text: $widgetBackgroundColor)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                            .font(.system(size: 12, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .accessibilityLabel("Widget background color")
                            .accessibilityIdentifier("widgetBackgroundColorField")
                            .onSubmit { broadcastWidgetConfig() }
                    }
                }
                .padding(.horizontal, cardPadding)
                .padding(.vertical, 12)
            }

            Divider()
                .padding(.leading, cardPadding)

            // Font row
            HStack(spacing: 12) {
                Text("Font")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Picker("", selection: $widgetFontFamily) {
                    Text("System Default").tag("System Default")
                    Divider()
                    ForEach(availableFonts, id: \.self) { font in
                        Text(font).tag(font)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
                .accessibilityLabel("Widget font")
                .accessibilityIdentifier("widgetFontPicker")
                .onChange(of: widgetFontFamily) { _, _ in
                    broadcastWidgetConfig()
                }
            }
            .padding(.horizontal, cardPadding)
            .padding(.vertical, 12)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))
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

    private func applyWidgetPort() {
        guard isWidgetPortValid, let port = UInt16(widgetPortText) else { return }
        storedWidgetPort = Int(port)
        NotificationCenter.default.post(
            name: NSNotification.Name(AppConstants.Notifications.widgetHTTPServerChanged),
            object: nil
        )
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

    private func broadcastWidgetConfig() {
        AppDelegate.shared?.websocketServer?.broadcastWidgetConfig()
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

#Preview("WebSocket Listening with Clients") {
    @Previewable @AppStorage(AppConstants.UserDefaults.websocketEnabled) var websocketEnabled = true
    @Previewable @AppStorage(AppConstants.UserDefaults.widgetHTTPEnabled) var widgetHTTPEnabled = true
    
    let view = WebSocketSettingsView()
    return view
        .padding()
        .frame(width: 700)
        .onAppear {
            // Simulate server listening with clients
            NotificationCenter.default.post(
                name: NSNotification.Name(AppConstants.Notifications.websocketServerStateChanged),
                object: nil,
                userInfo: [
                    "state": "listening",
                    "clients": 2
                ]
            )
        }
}

#Preview("WebSocket Stopped") {
    @Previewable @AppStorage(AppConstants.UserDefaults.websocketEnabled) var websocketEnabled = false
    
    WebSocketSettingsView()
        .padding()
        .frame(width: 700)
}
#Preview("WebSocket Starting") {
    @Previewable @AppStorage(AppConstants.UserDefaults.websocketEnabled) var websocketEnabled = true
    
    let view = WebSocketSettingsView()
    return view
        .padding()
        .frame(width: 700)
        .onAppear {
            NotificationCenter.default.post(
                name: NSNotification.Name(AppConstants.Notifications.websocketServerStateChanged),
                object: nil,
                userInfo: ["state": "starting"]
            )
        }
}

#Preview("WebSocket Error State") {
    @Previewable @AppStorage(AppConstants.UserDefaults.websocketEnabled) var websocketEnabled = true
    
    let view = WebSocketSettingsView()
    return view
        .padding()
        .frame(width: 700)
        .onAppear {
            NotificationCenter.default.post(
                name: NSNotification.Name(AppConstants.Notifications.websocketServerStateChanged),
                object: nil,
                userInfo: ["state": "error"]
            )
        }
}

#Preview("Custom Theme Settings") {
    @Previewable @AppStorage(AppConstants.UserDefaults.websocketEnabled) var websocketEnabled = true
    @Previewable @AppStorage(AppConstants.UserDefaults.widgetTheme) var widgetTheme = "Default"
    
    WebSocketSettingsView()
        .padding()
        .frame(width: 700)
}

