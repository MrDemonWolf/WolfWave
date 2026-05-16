//
//  WebSocketSettingsView.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/17/26.
//

import Network
import SwiftUI

/// Now-playing widget settings: server port, enable/disable toggle, status, and widget URL.
///
/// The view is decomposed into three sibling cards so a state change in one card doesn't
/// invalidate the others. Network IP discovery is cached in `@State` and refreshed off-main
/// via `NWPathMonitor` to avoid running `getifaddrs` on every render.
struct WebSocketSettingsView: View {
    @AppStorage(AppConstants.UserDefaults.websocketEnabled)
    private var websocketEnabled = false

    // MARK: - State

    // Seed from live services + cached IP so the first frame already reflects reality
    // instead of flashing "Stopped" or an empty Network Address row.
    @State private var serverState: WebSocketServerService.ServerState =
        AppDelegate.shared?.websocketServer?.state ?? .stopped
    @State private var clientCount: Int =
        AppDelegate.shared?.websocketServer?.connectionCount ?? 0
    @State private var localNetworkIP: String? = NetworkInfoService.cachedIPv4

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.SettingsUI.sectionSpacing) {
            SectionHeaderWithStatus(
                title: "Stream Widgets",
                subtitle: "Stream your current song to overlays and widgets.",
                statusText: serverStatusText,
                statusColor: serverStatusColor
            )

            WebSocketServerCard(serverState: serverState, localNetworkIP: localNetworkIP)

            WebSocketBrowserSourceCard(localNetworkIP: localNetworkIP)
                .transition(.opacity)

            WebSocketWidgetAppearanceCard()
                .transition(.opacity)
        }
        .task(id: websocketEnabled) {
            refreshServerState()
            await refreshLocalIP()
        }
        .task {
            await monitorNetworkPath()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSNotification.Name(AppConstants.Notifications.websocketServerStateChanged)
            )
        ) { notification in
            withAnimation(.easeInOut(duration: 0.2)) {
                if let rawValue = notification.userInfo?["state"] as? String,
                   let state = WebSocketServerService.ServerState(rawValue: rawValue) {
                    serverState = state
                }
                if let clients = notification.userInfo?["clients"] as? Int {
                    clientCount = clients
                }
            }
        }
    }

    // MARK: - Status helpers

    private var serverStatusText: String {
        switch serverState {
        case .listening:
            return clientCount > 0 ? "\(clientCount) connected" : "Listening"
        case .starting:
            return "Starting"
        case .error:
            return "Connection error"
        case .stopped:
            return "Stopped"
        }
    }

    private var serverStatusColor: Color {
        switch serverState {
        case .listening: return .green
        case .starting:  return .orange
        case .error:     return .red
        case .stopped:   return .gray
        }
    }

    private func refreshServerState() {
        guard let appDelegate = AppDelegate.shared else { return }
        serverState = appDelegate.websocketServer?.state ?? .stopped
        clientCount = appDelegate.websocketServer?.connectionCount ?? 0
    }

    private func refreshLocalIP() async {
        let ip = await NetworkInfoService.shared.refreshIPv4()
        await MainActor.run {
            guard ip != localNetworkIP else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                localNetworkIP = ip
            }
        }
    }

    /// Watches the system network path and refreshes the cached LAN IP when it changes.
    private func monitorNetworkPath() async {
        let monitor = NWPathMonitor()
        let stream = AsyncStream<NWPath> { continuation in
            monitor.pathUpdateHandler = { path in
                continuation.yield(path)
            }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: .global(qos: .utility))
        }
        for await _ in stream {
            await refreshLocalIP()
        }
    }
}

// MARK: - Server Card

fileprivate struct WebSocketServerCard: View {
    @AppStorage(AppConstants.UserDefaults.websocketEnabled)
    private var websocketEnabled = false

    @AppStorage(AppConstants.UserDefaults.websocketServerPort)
    private var storedPort: Int = Int(AppConstants.WebSocketServer.defaultPort)

    @State private var portText: String = ""

    let serverState: WebSocketServerService.ServerState
    let localNetworkIP: String?

    private let cardPadding = AppConstants.SettingsUI.cardPadding

    private var connectionURL: String { "ws://localhost:\(storedPort)" }

    private var networkConnectionURL: String? {
        guard let ip = localNetworkIP else { return nil }
        return "ws://\(ip):\(storedPort)"
    }

    private var isPortValid: Bool {
        guard let port = UInt16(portText) else { return false }
        return port >= AppConstants.WebSocketServer.minPort
            && port <= AppConstants.WebSocketServer.maxPort
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ToggleSettingRow(
                title: "Enable Stream Widgets",
                subtitle: "Show live song updates in your overlay.",
                isOn: $websocketEnabled,
                accessibilityLabel: "Toggle Stream Widgets",
                accessibilityIdentifier: "websocketEnabledToggle",
                onChange: { _ in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        notifyServerSettingChanged()
                    }
                }
            )
            .padding(.horizontal, cardPadding)
            .padding(.vertical, 12)

            Divider().padding(.leading, cardPadding)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Port").font(.system(size: 13, weight: .medium))
                    Text(verbatim: "Default: \(AppConstants.WebSocketServer.defaultPort)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                TextField("Port", text: $portText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .multilineTextAlignment(.center)
                    .disabled(websocketEnabled)
                    .accessibilityLabel("Server port")
                    .accessibilityIdentifier("websocketPortField")
                    .onSubmit { applyPort() }
            }
            .padding(.horizontal, cardPadding)
            .padding(.vertical, 12)
            .opacity(websocketEnabled ? 0.5 : 1.0)

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

            if websocketEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("Disable the server to change the port.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, cardPadding)
                .padding(.bottom, 8)
            }

            Divider().padding(.leading, cardPadding)

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
                CopyButton(
                    text: connectionURL,
                    isDisabled: !websocketEnabled,
                    accessibilityLabel: "Copy local connection URL",
                    accessibilityIdentifier: "copyConnectionURLButton"
                )
            }
            .padding(.horizontal, cardPadding)
            .padding(.vertical, 12)

            Group {
                if let networkURL = networkConnectionURL {
                    VStack(spacing: 0) {
                        Divider().padding(.leading, cardPadding)
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Network Address")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text(networkURL)
                                    .font(.system(size: 12, design: .monospaced))
                                    .textSelection(.enabled)
                                    .contentTransition(.opacity)
                                Text("Use this for two-PC setups.")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            CopyButton(
                                text: networkURL,
                                isDisabled: !websocketEnabled,
                                accessibilityLabel: "Copy network connection URL",
                                accessibilityIdentifier: "copyNetworkConnectionURLButton"
                            )
                        }
                        .padding(.horizontal, cardPadding)
                        .padding(.vertical, 12)
                    }
                    .id(networkURL)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: localNetworkIP)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))
        .onAppear { portText = String(storedPort) }
    }

    private func applyPort() {
        guard isPortValid, let port = UInt16(portText) else { return }
        storedPort = Int(port)
        let userInfo: [String: Any] = ["port": port]
        NotificationCenter.default.post(
            name: NSNotification.Name(AppConstants.Notifications.websocketServerChanged),
            object: nil,
            userInfo: userInfo
        )
    }

    private func notifyServerSettingChanged() {
        NotificationCenter.default.post(
            name: NSNotification.Name(AppConstants.Notifications.websocketServerChanged),
            object: nil
        )
    }
}

// MARK: - Browser Source Card

fileprivate struct WebSocketBrowserSourceCard: View {
    @AppStorage(AppConstants.UserDefaults.websocketEnabled)
    private var websocketEnabled = false

    @AppStorage(AppConstants.UserDefaults.widgetHTTPEnabled)
    private var widgetHTTPEnabled = false

    @AppStorage(AppConstants.UserDefaults.widgetPort)
    private var storedWidgetPort: Int = Int(AppConstants.WebSocketServer.widgetDefaultPort)

    @State private var widgetPortText: String = ""

    let localNetworkIP: String?

    private let cardPadding = AppConstants.SettingsUI.cardPadding

    private var widgetURL: String {
        let port = storedWidgetPort > 0 ? storedWidgetPort : Int(AppConstants.WebSocketServer.widgetDefaultPort)
        return "http://localhost:\(port)"
    }

    private var networkWidgetURL: String? {
        guard let ip = localNetworkIP else { return nil }
        let port = storedWidgetPort > 0 ? storedWidgetPort : Int(AppConstants.WebSocketServer.widgetDefaultPort)
        return "http://\(ip):\(port)"
    }

    private var isWidgetPortValid: Bool {
        guard let port = UInt16(widgetPortText) else { return false }
        return port >= AppConstants.WebSocketServer.minPort
            && port <= AppConstants.WebSocketServer.maxPort
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.inset.filled.and.person.filled")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(nsColor: .controlAccentColor))
                    Text("Widget Setup").sectionSubHeader()
                }
                Text("Use this link in OBS (Browser Source) or open it in any browser.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, cardPadding)
            .padding(.top, cardPadding)
            .padding(.bottom, 12)

            Divider().padding(.leading, cardPadding)

            ToggleSettingRow(
                title: "Enable Widget Webpage",
                subtitle: "Hosts the page you'll add to OBS",
                isOn: $widgetHTTPEnabled,
                isDisabled: !websocketEnabled,
                accessibilityLabel: "Toggle Widget Webpage",
                accessibilityIdentifier: "widgetHTTPEnabledToggle",
                onChange: { _ in
                    NotificationCenter.default.post(
                        name: NSNotification.Name(AppConstants.Notifications.widgetHTTPServerChanged),
                        object: nil
                    )
                }
            )
            .padding(.horizontal, cardPadding)
            .padding(.vertical, 12)
            .opacity(websocketEnabled ? 1.0 : 0.5)

            Divider().padding(.leading, cardPadding)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Widget Port (Advanced)").font(.system(size: 13, weight: .medium))
                    Text(verbatim: "Default: \(AppConstants.WebSocketServer.widgetDefaultPort)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                TextField("Port", text: $widgetPortText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .multilineTextAlignment(.center)
                    .disabled(widgetHTTPEnabled)
                    .accessibilityLabel("Widget server port")
                    .accessibilityIdentifier("widgetPortField")
                    .onSubmit { applyWidgetPort() }
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

            if widgetHTTPEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("Disable the widget server to change the port.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, cardPadding)
                .padding(.bottom, 8)
            }

            Divider().padding(.leading, cardPadding)

            VStack(alignment: .leading, spacing: 8) {
                Text(widgetURL)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    CopyButton(
                        text: widgetURL,
                        label: "Copy Link",
                        copiedLabel: "Copied",
                        isDisabled: !websocketEnabled || !widgetHTTPEnabled,
                        accessibilityLabel: "Copy widget URL",
                        accessibilityIdentifier: "copyWidgetURLButton"
                    )
                    Button {
                        if let url = URL(string: widgetURL) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "safari").font(.system(size: 11))
                            Text("Open").font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!websocketEnabled || !widgetHTTPEnabled)
                    .accessibilityLabel("Open widget in browser")
                    .accessibilityHint("Opens the widget in your default browser")
                    .accessibilityIdentifier("openWidgetURLButton")
                }
            }
            .padding(.horizontal, cardPadding)
            .padding(.vertical, 12)

            Group {
                if let networkWidget = networkWidgetURL {
                    VStack(spacing: 0) {
                        Divider().padding(.leading, cardPadding)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Network Address")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(networkWidget)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .contentTransition(.opacity)
                            Text("Use this for two-PC setups.")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, cardPadding)
                        .padding(.vertical, 12)
                    }
                    .id(networkWidget)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: localNetworkIP)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.blue)
                Text("In OBS, set the Width and Height to **\(AppConstants.Widget.recommendedDimensionsText)** for best results. Enable \"Shutdown source when not visible\" so the widget reconnects properly.")
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
        .onAppear { widgetPortText = String(storedWidgetPort) }
    }

    private func applyWidgetPort() {
        guard isWidgetPortValid, let port = UInt16(widgetPortText) else { return }
        storedWidgetPort = Int(port)
        NotificationCenter.default.post(
            name: NSNotification.Name(AppConstants.Notifications.widgetHTTPServerChanged),
            object: nil
        )
    }
}

// MARK: - Widget Appearance Card

fileprivate struct WebSocketWidgetAppearanceCard: View {
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

    /// Cached, sorted font family list. `availableFontFamilies` is fast but the sort isn't free
    /// — keep it out of `body`.
    private static let sortedFontFamilies: [String] = NSFontManager.shared.availableFontFamilies.sorted()

    private let cardPadding = AppConstants.SettingsUI.cardPadding

    private var textColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: widgetTextColor) ?? .white },
            set: { newColor in
                if let hex = newColor.toHex() { widgetTextColor = hex }
                broadcastWidgetConfig()
            }
        )
    }

    private var backgroundColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: widgetBackgroundColor) ?? .black },
            set: { newColor in
                if let hex = newColor.toHex() { widgetBackgroundColor = hex }
                broadcastWidgetConfig()
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "paintbrush.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(nsColor: .controlAccentColor))
                    Text("Widget Appearance").sectionSubHeader()
                }
                Text("Tweak colors, fonts, and layout for your widget.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, cardPadding)
            .padding(.top, cardPadding)
            .padding(.bottom, 12)

            Divider().padding(.leading, cardPadding)

            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("Theme").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Picker("", selection: $widgetTheme) {
                        ForEach(AppConstants.Widget.themes, id: \.self) { theme in
                            Text(theme).tag(theme)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("Widget theme")
                    .accessibilityIdentifier("widgetThemePicker")
                    .onChange(of: widgetTheme) { _, _ in broadcastWidgetConfig() }
                }
                .padding(.horizontal, cardPadding)
                .frame(maxWidth: .infinity)

                Divider()

                HStack(spacing: 8) {
                    Text("Layout").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Picker("", selection: $widgetLayout) {
                        ForEach(AppConstants.Widget.layouts, id: \.self) { layout in
                            Text(layout).tag(layout)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("Widget layout")
                    .accessibilityIdentifier("widgetLayoutPicker")
                    .onChange(of: widgetLayout) { _, _ in broadcastWidgetConfig() }
                }
                .padding(.horizontal, cardPadding)
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 12)

            if widgetTheme == "Default" || widgetTheme == "Glass" {
                Divider().padding(.leading, cardPadding)

                HStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text("Text Color").font(.system(size: 13, weight: .medium))
                        Spacer()
                        ColorPicker("", selection: textColorBinding, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 40)
                            .accessibilityLabel("Widget text color")
                            .accessibilityIdentifier("widgetTextColorPicker")
                    }
                    .padding(.horizontal, cardPadding)
                    .frame(maxWidth: .infinity)

                    Divider()

                    HStack(spacing: 8) {
                        Text("Bg Color").font(.system(size: 13, weight: .medium))
                        Spacer()
                        ColorPicker("", selection: backgroundColorBinding, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 40)
                            .accessibilityLabel("Widget background color")
                            .accessibilityIdentifier("widgetBackgroundColorPicker")
                    }
                    .padding(.horizontal, cardPadding)
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 12)
            }

            Divider().padding(.leading, cardPadding)

            HStack(spacing: 12) {
                Text("Font").font(.system(size: 13, weight: .medium))
                Spacer()
                Picker("", selection: $widgetFontFamily) {
                    Text("System Default").tag("System Default")
                    Divider()
                    ForEach(Self.sortedFontFamilies, id: \.self) { font in
                        Text(font).tag(font)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Widget font")
                .accessibilityIdentifier("widgetFontPicker")
                .onChange(of: widgetFontFamily) { _, _ in broadcastWidgetConfig() }
            }
            .padding(.horizontal, cardPadding)
            .padding(.vertical, 12)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))
    }

    private func broadcastWidgetConfig() {
        AppDelegate.shared?.websocketServer?.broadcastWidgetConfig()
    }
}

// MARK: - Preview

#Preview("WebSocket Listening with Clients") {
    @Previewable @AppStorage(AppConstants.UserDefaults.websocketEnabled) var websocketEnabled = true
    @Previewable @AppStorage(AppConstants.UserDefaults.widgetHTTPEnabled) var widgetHTTPEnabled = true

    WebSocketSettingsView()
        .padding()
        .frame(width: 700)
        .onAppear {
            NotificationCenter.default.post(
                name: NSNotification.Name(AppConstants.Notifications.websocketServerStateChanged),
                object: nil,
                userInfo: ["state": "listening", "clients": 2]
            )
        }
}

#Preview("WebSocket Stopped") {
    @Previewable @AppStorage(AppConstants.UserDefaults.websocketEnabled) var websocketEnabled = false
    WebSocketSettingsView()
        .padding()
        .frame(width: 700)
}
