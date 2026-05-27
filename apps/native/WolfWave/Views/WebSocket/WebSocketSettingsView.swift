//
//  WebSocketSettingsView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-01-13.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
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
            withAnimation(.easeInOut(duration: DSMotion.Duration.base)) {
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

    /// Pulls the latest server state + client count from the shared
    /// `WebSocketServerService` so the view's chips stay in sync with the
    /// service's actual state.
    private func refreshServerState() {
        guard let appDelegate = AppDelegate.shared else { return }
        serverState = appDelegate.websocketServer?.state ?? .stopped
        clientCount = appDelegate.websocketServer?.connectionCount ?? 0
    }

    /// Re-queries the cached LAN IPv4 address on the main actor and animates
    /// the change when the value differs from the current view state.
    private func refreshLocalIP() async {
        let ip = await NetworkInfoService.shared.refreshIPv4()
        await MainActor.run {
            guard ip != localNetworkIP else { return }
            withAnimation(.easeInOut(duration: DSMotion.Duration.base)) {
                localNetworkIP = ip
            }
        }
    }

    /// Watches the system network path and refreshes the cached LAN IP when it changes.
    /// Subscribes to the process-wide `NetworkInfoService.pathUpdates()` stream so re-entering
    /// this settings pane doesn't pay `NWPathMonitor.start` again.
    private func monitorNetworkPath() async {
        for await _ in NetworkInfoService.pathUpdates() {
            await refreshLocalIP()
        }
    }
}

// MARK: - Server Card

fileprivate struct WebSocketServerCard: View {
    @AppStorage(AppConstants.UserDefaults.websocketEnabled)
    private var websocketEnabled = false

    @AppStorage(AppConstants.UserDefaults.streamerModeEnabled)
    private var streamerMode = false

    @AppStorage(AppConstants.UserDefaults.websocketServerPort)
    private var storedPort: Int = Int(AppConstants.WebSocketServer.defaultPort)

    @State private var portText: String = ""

    /// Currently-persisted token. Seeded empty so struct init doesn't hit the
    /// Keychain — populated by `.task` off-main on first appear, and re-read
    /// after edits/regens so the displayed URL row stays in sync.
    @State private var currentToken: String = ""

    /// Live edit buffer for the token field. Seeded from `currentToken` and only
    /// committed when the user hits Save or presses return.
    @State private var tokenDraft: String = ""

    /// `true` reveals the token; default hidden behind a `SecureField`.
    @State private var isTokenRevealed: Bool = false

    /// Inline validation message shown beneath the token field, mirroring the
    /// port-field error pattern. `nil` when the draft is valid or unchanged.
    @State private var tokenError: String? = nil

    let serverState: WebSocketServerService.ServerState
    let localNetworkIP: String?

    private let cardPadding = AppConstants.SettingsUI.cardPadding

    private var connectionURL: String {
        "ws://localhost:\(storedPort)/?token=\(currentToken)"
    }

    private var networkConnectionURL: String? {
        guard let ip = localNetworkIP else { return nil }
        return "ws://\(ip):\(storedPort)/?token=\(currentToken)"
    }

    private var hasTokenEdits: Bool {
        let trimmed = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != currentToken
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
                    withAnimation(.easeInOut(duration: DSMotion.Duration.base)) {
                        notifyServerSettingChanged()
                    }
                }
            )
            .padding(.horizontal, cardPadding)
            .padding(.vertical, DSSpace.s4)

            Divider().padding(.leading, cardPadding)

            HStack(spacing: DSSpace.s4) {
                VStack(alignment: .leading, spacing: DSSpace.s0) {
                    Text("Port").font(.system(size: DSFont.Size.base, weight: .medium))
                    Text(verbatim: "Default: \(AppConstants.WebSocketServer.defaultPort)")
                        .font(.system(size: DSFont.Size.sm))
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
            .padding(.vertical, DSSpace.s4)
            .opacity(websocketEnabled ? 0.5 : 1.0)

            if !portText.isEmpty && !isPortValid {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: DSFont.Size.sm))
                    Text(verbatim: "Port must be between \(AppConstants.WebSocketServer.minPort) and \(AppConstants.WebSocketServer.maxPort).")
                        .font(.system(size: DSFont.Size.sm))
                }
                .foregroundStyle(.red)
                .padding(.horizontal, cardPadding)
                .padding(.bottom, DSSpace.s2)
            }

            if websocketEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(.secondary)
                    Text("Disable the server to change the port.")
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, cardPadding)
                .padding(.bottom, DSSpace.s2)
            }

            Divider().padding(.leading, cardPadding)

            authTokenRow

            Divider().padding(.leading, cardPadding)

            HStack(spacing: DSSpace.s2) {
                VStack(alignment: .leading, spacing: DSSpace.s0) {
                    HStack(spacing: DSSpace.s2) {
                        Text("Local Address")
                            .font(.system(size: DSFont.Size.sm, weight: .medium))
                            .foregroundStyle(.secondary)
                        if streamerMode { StreamerModeBadge() }
                    }
                    Text(StreamerMode.mask(connectionURL, style: .url, isOn: streamerMode))
                        .font(.system(size: DSFont.Size.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                Spacer()
                CopyButton(
                    text: connectionURL,
                    isDisabled: !websocketEnabled || streamerMode,
                    accessibilityLabel: "Copy local connection URL",
                    accessibilityIdentifier: "copyConnectionURLButton"
                )
            }
            .padding(.horizontal, cardPadding)
            .padding(.vertical, DSSpace.s4)

            Group {
                if let networkURL = networkConnectionURL {
                    VStack(spacing: 0) {
                        Divider().padding(.leading, cardPadding)
                        HStack(spacing: DSSpace.s2) {
                            VStack(alignment: .leading, spacing: DSSpace.s0) {
                                HStack(spacing: DSSpace.s2) {
                                    Text("Network Address")
                                        .font(.system(size: DSFont.Size.sm, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    if streamerMode { StreamerModeBadge() }
                                }
                                Text(StreamerMode.mask(networkURL, style: .url, isOn: streamerMode))
                                    .font(.system(size: DSFont.Size.body, design: .monospaced))
                                    .textSelection(.enabled)
                                    .contentTransition(.opacity)
                                Text("Use this for two-PC setups.")
                                    .font(.system(size: DSFont.Size.xs))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            CopyButton(
                                text: networkURL,
                                isDisabled: !websocketEnabled || streamerMode,
                                accessibilityLabel: "Copy network connection URL",
                                accessibilityIdentifier: "copyNetworkConnectionURLButton"
                            )
                        }
                        .padding(.horizontal, cardPadding)
                        .padding(.vertical, DSSpace.s4)
                    }
                    .id(networkURL)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: DSMotion.Duration.base), value: localNetworkIP)
        }
        .cardStyleUnpadded()
        .onAppear {
            portText = String(storedPort)
            tokenDraft = currentToken
        }
        .task {
            guard currentToken.isEmpty else { return }
            let token = await Task.detached(priority: .userInitiated) {
                WebSocketAuthToken.currentOrCreate()
            }.value
            await MainActor.run {
                currentToken = token
                if tokenDraft.isEmpty { tokenDraft = token }
            }
        }
    }

    // MARK: - Auth Token Row

    @ViewBuilder
    private var authTokenRow: some View {
        VStack(alignment: .leading, spacing: DSSpace.s2) {
            HStack(alignment: .firstTextBaseline, spacing: DSSpace.s2) {
                VStack(alignment: .leading, spacing: DSSpace.s0) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: DSFont.Size.sm))
                            .foregroundStyle(.secondary)
                        Text("Auth Token").font(.system(size: DSFont.Size.base, weight: .medium))
                        if streamerMode { StreamerModeBadge() }
                    }
                    Text("Required. Overlays must present this token to connect.")
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }

            HStack(spacing: 6) {
                Group {
                    if isTokenRevealed && !streamerMode {
                        TextField("Token", text: $tokenDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: DSFont.Size.body, design: .monospaced))
                            .autocorrectionDisabled(true)
                            .onSubmit { saveTokenEdit() }
                            .accessibilityIdentifier("websocketTokenFieldVisible")
                    } else {
                        SecureField("Token", text: $tokenDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: DSFont.Size.body, design: .monospaced))
                            .onSubmit { saveTokenEdit() }
                            .disabled(streamerMode)
                            .accessibilityIdentifier("websocketTokenFieldHidden")
                    }
                }

                DSIconButton(
                    systemImage: isTokenRevealed ? "eye.slash" : "eye",
                    action: { isTokenRevealed.toggle() },
                    accessibilityLabel: isTokenRevealed ? "Hide token" : "Reveal token",
                    accessibilityIdentifier: "websocketTokenRevealButton"
                )
                .help(isTokenRevealed ? "Hide token" : "Reveal token")
                .disabled(streamerMode)

                CopyButton(
                    text: currentToken,
                    label: "Copy",
                    copiedLabel: "Copied",
                    isDisabled: currentToken.isEmpty || streamerMode,
                    accessibilityLabel: "Copy auth token",
                    accessibilityIdentifier: "copyWebsocketTokenButton"
                )
            }

            if let tokenError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: DSFont.Size.sm))
                    Text(tokenError)
                        .font(.system(size: DSFont.Size.sm))
                }
                .foregroundStyle(.red)
                .accessibilityIdentifier("websocketTokenError")
            }

            HStack(spacing: DSSpace.s2) {
                Button {
                    regenerateToken()
                } label: {
                    HStack(spacing: DSSpace.s1) {
                        Image(systemName: "arrow.clockwise").font(.system(size: DSFont.Size.sm))
                        Text("Regenerate").font(.system(size: DSFont.Size.sm))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(streamerMode)
                .help(streamerMode
                    ? "Turn off Streamer Mode to regenerate the token."
                    : "Generate a new random token. Active overlays will disconnect until updated.")
                .accessibilityIdentifier("regenerateWebsocketTokenButton")

                if hasTokenEdits {
                    Button {
                        saveTokenEdit()
                    } label: {
                        Text("Save").font(.system(size: DSFont.Size.sm))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(streamerMode)
                    .accessibilityIdentifier("saveWebsocketTokenButton")

                    Button {
                        tokenDraft = currentToken
                        tokenError = nil
                    } label: {
                        Text("Cancel").font(.system(size: DSFont.Size.sm))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()
            }
        }
        .padding(.horizontal, cardPadding)
        .padding(.vertical, 12)
    }

    /// Persists `tokenDraft` to Keychain, swaps the token on the live service,
    /// and refreshes the displayed URL row. No-op when nothing changed.
    ///
    /// Tokens are gated through `WebSocketAuthToken.isValid` (hex-only, 16–128
    /// chars) so a user-supplied string can never contain `</script>` or other
    /// characters that would break out of the JS string context when
    /// `WidgetHTTPService` substitutes the token into the served `widget.html`.
    private func saveTokenEdit() {
        let trimmed = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != currentToken else {
            tokenDraft = currentToken
            return
        }
        guard WebSocketAuthToken.isValid(trimmed) else {
            Log.warn(
                "WebSocketSettings: Rejected custom token — must be hex characters (16–128).",
                category: "WebSocket"
            )
            tokenError = "Use 16–128 hex chars (0–9, a–f)."
            return
        }
        tokenError = nil
        do {
            try KeychainService.saveToken(trimmed)
            currentToken = trimmed
            tokenDraft = trimmed
            applyTokenToServer(trimmed)
        } catch {
            Log.error("WebSocketSettings: Failed to save custom token: \(error)", category: "WebSocket")
            tokenError = "Couldn't save token. Try again."
        }
    }

    /// Mints a fresh random token, persists it, and pushes it onto the service.
    private func regenerateToken() {
        let fresh = WebSocketAuthToken.rotate()
        currentToken = fresh
        tokenDraft = fresh
        tokenError = nil
        applyTokenToServer(fresh)
    }

    /// Pushes a token swap onto the live `WebSocketServerService` so existing
    /// clients are dropped and forced to re-handshake. Also bounces the widget
    /// HTTP server so served HTML re-bakes the new value.
    private func applyTokenToServer(_ token: String) {
        let server = AppDelegate.shared?.websocketServer
        Task { await server?.updateAuthToken(token) }
    }

    /// Validates the port text field and, when valid, persists the new port
    /// to UserDefaults and posts a `websocketServerChanged` notification so
    /// the server restarts on the new port.
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

    /// Posts a `websocketServerChanged` notification without altering settings.
    /// Used after a setting change persists, to nudge the service to re-read.
    private func notifyServerSettingChanged() {
        NotificationCenter.default.post(
            name: NSNotification.Name(AppConstants.Notifications.websocketServerChanged),
            object: nil
        )
    }
}

// MARK: - Browser Source Card

fileprivate struct WebSocketBrowserSourceCard: View {
    @AppStorage(AppConstants.UserDefaults.streamerModeEnabled)
    private var streamerMode = false

    @AppStorage(AppConstants.UserDefaults.websocketEnabled)
    private var websocketEnabled = false

    @AppStorage(AppConstants.UserDefaults.widgetHTTPEnabled)
    private var widgetHTTPEnabled = false

    @AppStorage(AppConstants.UserDefaults.widgetPort)
    private var storedWidgetPort: Int = Int(AppConstants.WebSocketServer.widgetDefaultPort)

    @State private var widgetPortText: String = ""

    /// Cached auth token. Seeded once in `.onAppear` so a SwiftUI recompute
    /// never reaches into the Keychain (which `WebSocketAuthToken.currentOrCreate()`
    /// would otherwise do, with side effects, on every render).
    @State private var currentToken: String = ""

    let localNetworkIP: String?

    private let cardPadding = AppConstants.SettingsUI.cardPadding

    private var widgetURL: String {
        let port = storedWidgetPort > 0 ? storedWidgetPort : Int(AppConstants.WebSocketServer.widgetDefaultPort)
        return "http://localhost:\(port)"
    }

    private var networkWidgetURL: String? {
        guard let ip = localNetworkIP, !currentToken.isEmpty else { return nil }
        let port = storedWidgetPort > 0 ? storedWidgetPort : Int(AppConstants.WebSocketServer.widgetDefaultPort)
        return "http://\(ip):\(port)/?token=\(currentToken)"
    }

    private var isWidgetPortValid: Bool {
        guard let port = UInt16(widgetPortText) else { return false }
        return port >= AppConstants.WebSocketServer.minPort
            && port <= AppConstants.WebSocketServer.maxPort
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: DSSpace.s2) {
                    Image(systemName: "rectangle.inset.filled.and.person.filled")
                        .font(.system(size: DSFont.Size.md))
                        .foregroundStyle(Color(nsColor: .controlAccentColor))
                    Text("Widget Setup").sectionSubHeader()
                }
                Text("Use this link in OBS (Browser Source) or open it in any browser.")
                    .font(.system(size: DSFont.Size.body))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, cardPadding)
            .padding(.top, cardPadding)
            .padding(.bottom, DSSpace.s4)

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
            .padding(.vertical, DSSpace.s4)
            .opacity(websocketEnabled ? 1.0 : 0.5)

            Divider().padding(.leading, cardPadding)

            HStack(spacing: DSSpace.s4) {
                VStack(alignment: .leading, spacing: DSSpace.s0) {
                    Text("Widget Port (Advanced)").font(.system(size: DSFont.Size.base, weight: .medium))
                    Text(verbatim: "Default: \(AppConstants.WebSocketServer.widgetDefaultPort)")
                        .font(.system(size: DSFont.Size.sm))
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
            .padding(.vertical, DSSpace.s4)
            .opacity(websocketEnabled && widgetHTTPEnabled ? 1.0 : 0.5)

            if !widgetPortText.isEmpty && !isWidgetPortValid {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: DSFont.Size.sm))
                    Text(verbatim: "Port must be between \(AppConstants.WebSocketServer.minPort) and \(AppConstants.WebSocketServer.maxPort).")
                        .font(.system(size: DSFont.Size.sm))
                }
                .foregroundStyle(.red)
                .padding(.horizontal, cardPadding)
                .padding(.bottom, DSSpace.s2)
            }

            if widgetHTTPEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(.secondary)
                    Text("Disable the widget server to change the port.")
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, cardPadding)
                .padding(.bottom, DSSpace.s2)
            }

            Divider().padding(.leading, cardPadding)

            VStack(alignment: .leading, spacing: DSSpace.s2) {
                if streamerMode {
                    HStack { StreamerModeBadge(); Spacer() }
                }
                Text(StreamerMode.mask(widgetURL, style: .url, isOn: streamerMode))
                    .font(.system(size: DSFont.Size.sm, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: DSSpace.s2) {
                    CopyButton(
                        text: widgetURL,
                        label: "Copy Link",
                        copiedLabel: "Copied",
                        isDisabled: !websocketEnabled || !widgetHTTPEnabled || streamerMode,
                        accessibilityLabel: "Copy widget URL",
                        accessibilityIdentifier: "copyWidgetURLButton"
                    )
                    Button {
                        if let url = URL(string: widgetURL) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: DSSpace.s1) {
                            Image(systemName: "safari").font(.system(size: DSFont.Size.sm))
                            Text("Open").font(.system(size: DSFont.Size.sm))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!websocketEnabled || !widgetHTTPEnabled || streamerMode)
                    .accessibilityLabel("Open widget in browser")
                    .accessibilityHint("Opens the widget in your default browser")
                    .accessibilityIdentifier("openWidgetURLButton")
                }
            }
            .padding(.horizontal, cardPadding)
            .padding(.vertical, DSSpace.s4)

            Group {
                if let networkWidget = networkWidgetURL {
                    VStack(spacing: 0) {
                        Divider().padding(.leading, cardPadding)
                        HStack(spacing: DSSpace.s2) {
                            VStack(alignment: .leading, spacing: DSSpace.s0) {
                                HStack(spacing: DSSpace.s2) {
                                    Text("Network Address")
                                        .font(.system(size: DSFont.Size.sm, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    if streamerMode { StreamerModeBadge() }
                                }
                                Text(StreamerMode.mask(networkWidget, style: .url, isOn: streamerMode))
                                    .font(.system(size: DSFont.Size.body, design: .monospaced))
                                    .textSelection(.enabled)
                                    .contentTransition(.opacity)
                                Text("Use this for two-PC setups.")
                                    .font(.system(size: DSFont.Size.xs))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            HStack(spacing: DSSpace.s2) {
                                CopyButton(
                                    text: networkWidget,
                                    label: "Copy Link",
                                    copiedLabel: "Copied",
                                    isDisabled: !websocketEnabled || !widgetHTTPEnabled || streamerMode,
                                    accessibilityLabel: "Copy network widget URL",
                                    accessibilityIdentifier: "copyNetworkWidgetURLButton"
                                )
                                Button {
                                    if let url = URL(string: networkWidget) {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    HStack(spacing: DSSpace.s1) {
                                        Image(systemName: "safari").font(.system(size: DSFont.Size.sm))
                                        Text("Open").font(.system(size: DSFont.Size.sm))
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(!websocketEnabled || !widgetHTTPEnabled || streamerMode)
                                .accessibilityLabel("Open network widget in browser")
                                .accessibilityIdentifier("openNetworkWidgetURLButton")
                            }
                        }
                        .padding(.horizontal, cardPadding)
                        .padding(.vertical, DSSpace.s4)
                    }
                    .id(networkWidget)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeInOut(duration: DSMotion.Duration.base), value: localNetworkIP)

            Divider().padding(.leading, cardPadding)

            HStack(alignment: .top, spacing: DSSpace.s2) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: DSFont.Size.body))
                    .foregroundStyle(DSColor.info)
                Text("In OBS, set the Width and Height to **\(AppConstants.Widget.recommendedDimensionsText)** for best results. Enable \"Shutdown source when not visible\" so the widget reconnects properly.")
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DSSpace.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DSColor.info.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.sm))
            .padding(.horizontal, cardPadding)
            .padding(.top, DSSpace.s4)
            .padding(.bottom, cardPadding)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.SettingsUI.cardCornerRadius))
        .onAppear {
            widgetPortText = String(storedWidgetPort)
        }
        .task {
            let token = await Task.detached(priority: .userInitiated) {
                WebSocketAuthToken.currentOrCreate()
            }.value
            await MainActor.run { currentToken = token }
        }
    }

    /// Validates the widget HTTP port text field, persists the new port, and
    /// posts a `widgetHTTPServerChanged` notification so the widget server
    /// restarts on the new port.
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

    /// Font family list loaded off-main on first appear. `availableFontFamilies` enumerates every
    /// installed font (hundreds of entries on design-heavy Macs) and blocks ~100–400ms if invoked
    /// inside `body`. Keep it lazy + off the main thread.
    @State private var fontFamilies: [String] = []

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
                HStack(spacing: DSSpace.s2) {
                    Image(systemName: "paintbrush.fill")
                        .font(.system(size: DSFont.Size.md))
                        .foregroundStyle(Color(nsColor: .controlAccentColor))
                    Text("Widget Appearance").sectionSubHeader()
                }
                Text("Tweak colors, fonts, and layout for your widget.")
                    .font(.system(size: DSFont.Size.body))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, cardPadding)
            .padding(.top, cardPadding)
            .padding(.bottom, DSSpace.s4)

            Divider().padding(.leading, cardPadding)

            HStack(spacing: 0) {
                HStack(spacing: DSSpace.s2) {
                    Text("Theme").font(.system(size: DSFont.Size.base, weight: .medium))
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

                HStack(spacing: DSSpace.s2) {
                    Text("Layout").font(.system(size: DSFont.Size.base, weight: .medium))
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
            .padding(.vertical, DSSpace.s4)

            if widgetTheme == "Default" || widgetTheme == "Glass" {
                Divider().padding(.leading, cardPadding)

                HStack(spacing: 0) {
                    HStack(spacing: DSSpace.s2) {
                        Text("Text Color").font(.system(size: DSFont.Size.base, weight: .medium))
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

                    HStack(spacing: DSSpace.s2) {
                        Text("Bg Color").font(.system(size: DSFont.Size.base, weight: .medium))
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
                .padding(.vertical, DSSpace.s4)
            }

            Divider().padding(.leading, cardPadding)

            HStack(spacing: DSSpace.s4) {
                Text("Font").font(.system(size: DSFont.Size.base, weight: .medium))
                Spacer()
                Picker("", selection: $widgetFontFamily) {
                    Text("System Default").tag("System Default")
                    if !fontFamilies.isEmpty {
                        Divider()
                        ForEach(fontFamilies, id: \.self) { font in
                            Text(font).tag(font)
                        }
                    }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Widget font")
                .accessibilityIdentifier("widgetFontPicker")
                .onChange(of: widgetFontFamily) { _, _ in broadcastWidgetConfig() }
            }
            .padding(.horizontal, cardPadding)
            .padding(.vertical, DSSpace.s4)
        }
        .cardStyleUnpadded()
        .task {
            guard fontFamilies.isEmpty else { return }
            let families = await Task.detached(priority: .userInitiated) {
                NSFontManager.shared.availableFontFamilies.sorted()
            }.value
            fontFamilies = families
        }
    }

    /// Pushes the current widget theme/layout/font/color values to every
    /// connected overlay via `WebSocketServerService.broadcastWidgetConfig()`.
    /// Called from `onChange` of each customization control.
    private func broadcastWidgetConfig() {
        let server = AppDelegate.shared?.websocketServer
        Task { await server?.broadcastWidgetConfig() }
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
