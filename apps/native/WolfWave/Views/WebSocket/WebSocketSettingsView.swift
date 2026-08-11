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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                statusColor: serverStatusColor,
                statusSymbol: serverStatusSymbol
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
                for: Notification.Name.websocketServerStateChanged
            )
        ) { notification in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: DSMotion.Duration.base)) {
                if let rawValue = notification.stateString,
                   let state = WebSocketServerService.ServerState(rawValue: rawValue) {
                    serverState = state
                }
                if let clients = notification.clientsCount {
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

    /// Leading chip glyph so server state reads through shape as well as color.
    private var serverStatusSymbol: String {
        switch serverState {
        case .listening: return StatusChip.StateGlyph.on
        case .starting:  return StatusChip.StateGlyph.starting
        case .error:     return StatusChip.StateGlyph.error
        case .stopped:   return StatusChip.StateGlyph.off
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
            withAnimation(reduceMotion ? nil : .easeInOut(duration: DSMotion.Duration.base)) {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(AppConstants.UserDefaults.websocketEnabled)
    private var websocketEnabled = false

    @AppStorage(AppConstants.UserDefaults.streamerModeEnabled)
    private var streamerMode = false

    @AppStorage(AppConstants.UserDefaults.websocketServerPort)
    private var storedPort: Int = Int(AppConstants.WebSocketServer.defaultPort)

    @State private var portText: String = ""

    /// Currently-persisted token. Seeded empty so struct init doesn't hit the
    /// Keychain. Populated by `.task` off-main on first appear, and re-read
    /// after edits/regens so the displayed URL row stays in sync.
    @State private var currentToken: String = ""

    /// Cached same-Mac control credential shown in the Stream Deck row.
    @State private var currentControlToken: String = ""

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
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: DSMotion.Duration.base)) {
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
                HStack(spacing: DSSpace.s1h) {
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
                HStack(spacing: DSSpace.s1h) {
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

            WebSocketTokenEditorRow(
                role: .overlay,
                title: "Overlay Token",
                subtitle: "Read-only. OBS widgets use this token to receive updates.",
                currentToken: $currentToken,
                streamerMode: streamerMode,
                otherToken: currentControlToken
            )

            Divider().padding(.leading, cardPadding)

            WebSocketTokenEditorRow(
                role: .control,
                title: "Stream Deck Control Token",
                subtitle: "Stream Deck uses this token to run commands on this Mac.",
                currentToken: $currentControlToken,
                streamerMode: streamerMode,
                otherToken: currentToken
            )

            Divider().padding(.leading, cardPadding)

            CopyableURLRow(
                label: "Local Address",
                url: connectionURL,
                isStreamerMode: streamerMode,
                actionsDisabled: !websocketEnabled,
                copyAccessibilityLabel: "Copy local connection URL",
                copyAccessibilityIdentifier: "copyConnectionURLButton"
            )
            .padding(.horizontal, cardPadding)
            .padding(.vertical, DSSpace.s4)

            Group {
                if let networkURL = networkConnectionURL {
                    VStack(spacing: 0) {
                        Divider().padding(.leading, cardPadding)
                        CopyableURLRow(
                            label: "Network Address",
                            url: networkURL,
                            subtitle: "Use this for two-PC setups.",
                            isStreamerMode: streamerMode,
                            actionsDisabled: !websocketEnabled,
                            copyAccessibilityLabel: "Copy network connection URL",
                            copyAccessibilityIdentifier: "copyNetworkConnectionURLButton"
                        )
                        .padding(.horizontal, cardPadding)
                        .padding(.vertical, DSSpace.s4)
                    }
                    .id(networkURL)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: DSMotion.Duration.base), value: localNetworkIP)
        }
        .cardStyleUnpadded()
        .onAppear {
            portText = String(storedPort)
        }
        .task {
            guard currentToken.isEmpty || currentControlToken.isEmpty else { return }
            let tokens = await Task.detached(priority: .userInitiated) {
                (
                    WebSocketAuthToken.currentOrCreate(for: .overlay),
                    WebSocketAuthToken.currentOrCreate(for: .control)
                )
            }.value
            currentToken = tokens.0
            currentControlToken = tokens.1
        }
    }
    /// Validates the port text field and, when valid, persists the new port
    /// to UserDefaults and posts a `websocketServerChanged` notification so
    /// the server restarts on the new port.
    private func applyPort() {
        guard isPortValid, let port = UInt16(portText) else { return }
        storedPort = Int(port)
        NotificationCenter.default.postWebSocketServerChanged(port: port)
    }

    /// Posts a `websocketServerChanged` notification without altering settings.
    /// Used after a setting change persists, to nudge the service to re-read.
    private func notifyServerSettingChanged() {
        NotificationCenter.default.postWebSocketServerChanged()
    }
}

// MARK: - WebSocket Token Editor

/// Shared editor for the two role-specific credentials. Keeping one row
/// implementation prevents overlay and Stream Deck validation or masking
/// behavior from drifting while preserving the existing settings-card design.
fileprivate struct WebSocketTokenEditorRow: View {
    let role: WebSocketAuthToken.Role
    let title: String
    let subtitle: String
    @Binding var currentToken: String
    let streamerMode: Bool
    let otherToken: String

    @State private var tokenDraft = ""
    @State private var isTokenRevealed = false
    @State private var tokenError: String?
    @State private var showingRegenerateConfirm = false

    private let cardPadding = AppConstants.SettingsUI.cardPadding

    private var isOverlay: Bool { role == .overlay }

    private var hasTokenEdits: Bool {
        let trimmed = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != currentToken
    }

    private var visibleFieldIdentifier: String {
        isOverlay ? "websocketTokenFieldVisible" : "websocketControlTokenFieldVisible"
    }

    private var hiddenFieldIdentifier: String {
        isOverlay ? "websocketTokenFieldHidden" : "websocketControlTokenFieldHidden"
    }

    private var revealButtonIdentifier: String {
        isOverlay ? "websocketTokenRevealButton" : "websocketControlTokenRevealButton"
    }

    private var copyButtonIdentifier: String {
        isOverlay ? "copyWebsocketTokenButton" : "copyWebsocketControlTokenButton"
    }

    private var errorIdentifier: String {
        isOverlay ? "websocketTokenError" : "websocketControlTokenError"
    }

    private var regenerateButtonIdentifier: String {
        isOverlay ? "regenerateWebsocketTokenButton" : "regenerateWebsocketControlTokenButton"
    }

    private var saveButtonIdentifier: String {
        isOverlay ? "saveWebsocketTokenButton" : "saveWebsocketControlTokenButton"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s2) {
            HStack(alignment: .firstTextBaseline, spacing: DSSpace.s2) {
                VStack(alignment: .leading, spacing: DSSpace.s0) {
                    HStack(spacing: DSSpace.s1h) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: DSFont.Size.sm))
                            .foregroundStyle(.secondary)
                        Text(title).font(.system(size: DSFont.Size.base, weight: .medium))
                        if streamerMode { StreamerModeBadge() }
                    }
                    Text(subtitle)
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }

            HStack(spacing: DSSpace.s1h) {
                Group {
                    if isTokenRevealed && !streamerMode {
                        TextField("Token", text: $tokenDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: DSFont.Size.body, design: .monospaced))
                            .autocorrectionDisabled(true)
                            .onSubmit { saveTokenEdit() }
                            .accessibilityIdentifier(visibleFieldIdentifier)
                    } else {
                        SecureField("Token", text: $tokenDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: DSFont.Size.body, design: .monospaced))
                            .onSubmit { saveTokenEdit() }
                            .disabled(streamerMode)
                            .accessibilityIdentifier(hiddenFieldIdentifier)
                    }
                }

                DSIconButton(
                    systemImage: isTokenRevealed ? "eye.slash" : "eye",
                    action: { isTokenRevealed.toggle() },
                    accessibilityLabel: isTokenRevealed ? "Hide token" : "Reveal token",
                    accessibilityIdentifier: revealButtonIdentifier
                )
                .help(isTokenRevealed ? "Hide token" : "Reveal token")
                .disabled(streamerMode)

                CopyButton(
                    text: currentToken,
                    label: "Copy",
                    copiedLabel: "Copied",
                    isDisabled: currentToken.isEmpty || streamerMode,
                    accessibilityLabel: isOverlay
                        ? "Copy overlay token"
                        : "Copy Stream Deck control token",
                    accessibilityIdentifier: copyButtonIdentifier
                )
            }

            if let tokenError {
                HStack(spacing: DSSpace.s1h) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: DSFont.Size.sm))
                    Text(tokenError).font(.system(size: DSFont.Size.sm))
                }
                .foregroundStyle(.red)
                .accessibilityIdentifier(errorIdentifier)
            }

            HStack(spacing: DSSpace.s2) {
                Button(role: .destructive) {
                    showingRegenerateConfirm = true
                } label: {
                    HStack(spacing: DSSpace.s1) {
                        Image(systemName: "arrow.clockwise").font(.system(size: DSFont.Size.sm))
                        Text("Regenerate").font(.system(size: DSFont.Size.sm))
                    }
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
                .disabled(streamerMode)
                .help(regenerateHelp)
                .accessibilityIdentifier(regenerateButtonIdentifier)

                if hasTokenEdits {
                    Button("Save") { saveTokenEdit() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(streamerMode)
                        .accessibilityIdentifier(saveButtonIdentifier)

                    Button("Cancel") {
                        tokenDraft = currentToken
                        tokenError = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Spacer()
            }
        }
        .padding(.horizontal, cardPadding)
        .padding(.vertical, DSSpace.s4)
        .onAppear {
            if tokenDraft.isEmpty { tokenDraft = currentToken }
        }
        .onChange(of: currentToken) { _, newValue in
            tokenDraft = newValue
            tokenError = nil
        }
        .confirmationDialog(
            isOverlay ? "Regenerate overlay token?" : "Regenerate control token?",
            isPresented: $showingRegenerateConfirm,
            titleVisibility: .visible
        ) {
            Button("Regenerate", role: .destructive) { regenerateToken() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                isOverlay
                    ? "Active overlays disconnect until you copy the new URL back into OBS."
                    : "Stream Deck disconnects until you copy the new control token into its settings."
            )
        }
    }

    private var regenerateHelp: String {
        if streamerMode { return "Turn off Streamer Mode to regenerate this token." }
        return isOverlay
            ? "Generate a new overlay token. Active overlays will disconnect until updated."
            : "Generate a new control token. Stream Deck will disconnect until updated."
    }

    private func saveTokenEdit() {
        let trimmed = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != currentToken else {
            tokenDraft = currentToken
            return
        }
        guard WebSocketAuthToken.isValid(trimmed) else {
            tokenError = "Use exactly 64 hex characters (0-9, a-f)."
            return
        }
        guard otherToken.isEmpty || !WebSocketAuthToken.constantTimeEquals(trimmed, otherToken) else {
            tokenError = "Overlay and control tokens must be different."
            return
        }

        do {
            try WebSocketAuthToken.persist(trimmed, for: role)
            currentToken = trimmed
            tokenDraft = trimmed
            tokenError = nil
            applyTokenToServer(trimmed)
        } catch {
            Log.error(
                "WebSocketSettings: Failed to save " + role.rawValue + " token: "
                    + String(describing: error),
                category: "WebSocket"
            )
            tokenError = "Couldn't save token. Try again."
        }
    }

    private func regenerateToken() {
        do {
            let fresh = try WebSocketAuthToken.rotate(role)
            currentToken = fresh
            tokenDraft = fresh
            tokenError = nil
            applyTokenToServer(fresh)
        } catch {
            Log.error(
                "WebSocketSettings: Failed to rotate " + role.rawValue + " token: "
                    + String(describing: error),
                category: "WebSocket"
            )
            tokenError = "Couldn't save the new token. Your current token is still active."
        }
    }

    private func applyTokenToServer(_ token: String) {
        let server = AppDelegate.shared?.websocketServer
        Task {
            switch role {
            case .overlay:
                await server?.updateOverlayToken(token)
            case .control:
                await server?.updateControlToken(token)
            }
        }
        if isOverlay {
            NotificationCenter.default.post(name: .websocketAuthTokenChanged, object: nil)
        }
    }
}

// MARK: - Browser Source Card

fileprivate struct WebSocketBrowserSourceCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(AppConstants.UserDefaults.streamerModeEnabled)
    private var streamerMode = false

    @AppStorage(AppConstants.UserDefaults.websocketEnabled)
    private var websocketEnabled = false

    @AppStorage(AppConstants.UserDefaults.widgetHTTPEnabled)
    private var widgetHTTPEnabled = false

    @AppStorage(AppConstants.UserDefaults.widgetLayout)
    private var widgetLayout = AppConstants.Widget.Defaults.layout

    @AppStorage(AppConstants.UserDefaults.widgetPort)
    private var storedWidgetPort: Int = Int(AppConstants.WebSocketServer.widgetDefaultPort)

    @State private var widgetPortText: String = ""

    /// Cached read-only overlay token. Seeded once in `.onAppear` so a SwiftUI recompute
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
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            widgetSetupHeader
            widgetSetupCard
        }
        .onAppear {
            widgetPortText = String(storedWidgetPort)
        }
        .task {
            // `.task` re-runs on every structural identity change; skip the
            // Keychain round-trip once the token is already loaded. In-session
            // saves/regenerations arrive via `.websocketAuthTokenChanged` below.
            guard currentToken.isEmpty else { return }
            await reloadToken()
        }
        .onReceive(NotificationCenter.default.publisher(for: .websocketAuthTokenChanged)) { _ in
            Task { await reloadToken() }
        }
    }

    private var widgetSetupHeader: some View {
        SectionHeaderWithStatus(
            title: "Widget Setup",
            subtitle: "Use this link in OBS (Browser Source) or open it in any browser.",
            prominence: .section
        )
    }

    private var widgetSetupCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ToggleSettingRow(
                title: "Enable Widget Webpage",
                subtitle: "Hosts the page you'll add to OBS",
                isOn: $widgetHTTPEnabled,
                isDisabled: !websocketEnabled,
                accessibilityLabel: "Toggle Widget Webpage",
                accessibilityIdentifier: "widgetHTTPEnabledToggle",
                onChange: { _ in
                    NotificationCenter.default.post(
                        name: Notification.Name.widgetHTTPServerChanged,
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
                HStack(spacing: DSSpace.s1h) {
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
                HStack(spacing: DSSpace.s1h) {
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

            CopyableURLRow(
                url: widgetURL,
                isStreamerMode: streamerMode,
                actionsDisabled: !websocketEnabled || !widgetHTTPEnabled,
                urlLineLimit: 2,
                copyLabel: "Copy Link",
                copiedLabel: "Copied",
                copyAccessibilityLabel: "Copy widget URL",
                copyAccessibilityIdentifier: "copyWidgetURLButton"
            ) {
                OpenInBrowserButton(
                    urlString: widgetURL,
                    isDisabled: !websocketEnabled || !widgetHTTPEnabled || streamerMode,
                    accessibilityLabel: "Open widget in browser",
                    accessibilityHint: "Opens the widget in your default browser",
                    accessibilityIdentifier: "openWidgetURLButton"
                )
            }
            .padding(.horizontal, cardPadding)
            .padding(.vertical, DSSpace.s4)

            Group {
                if let networkWidget = networkWidgetURL {
                    VStack(spacing: 0) {
                        Divider().padding(.leading, cardPadding)
                        CopyableURLRow(
                            label: "Network Address",
                            url: networkWidget,
                            subtitle: "Use this for two-PC setups. The localhost link above is safer. This one sends your token over the network unencrypted, so only share it on a network you trust.",
                            isStreamerMode: streamerMode,
                            actionsDisabled: !websocketEnabled || !widgetHTTPEnabled,
                            copyLabel: "Copy Link",
                            copiedLabel: "Copied",
                            copyAccessibilityLabel: "Copy network widget URL",
                            copyAccessibilityIdentifier: "copyNetworkWidgetURLButton"
                        ) {
                            OpenInBrowserButton(
                                urlString: networkWidget,
                                isDisabled: !websocketEnabled || !widgetHTTPEnabled || streamerMode,
                                accessibilityLabel: "Open network widget in browser",
                                accessibilityIdentifier: "openNetworkWidgetURLButton"
                            )
                        }
                        .padding(.horizontal, cardPadding)
                        .padding(.vertical, DSSpace.s4)
                    }
                    .id(networkWidget)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: DSMotion.Duration.base), value: localNetworkIP)

            Divider().padding(.leading, cardPadding)

            CalloutBanner(
                "In OBS, set Width and Height to "
                    + "**\(AppConstants.Widget.recommendedDimensionsText(for: widgetLayout))** "
                    + "for the \(widgetLayout) layout. "
                    + "Enable \"Shutdown source when not visible\" "
                    + "so the widget reconnects properly.",
                style: .info
            )
            .padding(.horizontal, cardPadding)
            .padding(.top, DSSpace.s4)
            .padding(.bottom, cardPadding)
        }
        .cardStyleUnpadded()
    }

    /// Validates the widget HTTP port text field, persists the new port, and
    /// posts a `widgetHTTPServerChanged` notification so the widget server
    /// restarts on the new port.
    private func applyWidgetPort() {
        guard isWidgetPortValid, let port = UInt16(widgetPortText) else { return }
        storedWidgetPort = Int(port)
        NotificationCenter.default.post(
            name: Notification.Name.widgetHTTPServerChanged,
            object: nil
        )
    }

    /// Re-reads the read-only overlay token off the main thread (Keychain I/O) and
    /// publishes it into the card's state. Called on first appearance and
    /// whenever `.websocketAuthTokenChanged` reports a save/regeneration.
    private func reloadToken() async {
        let token = await Task.detached(priority: .userInitiated) {
            WebSocketAuthToken.currentOrCreate(for: .overlay)
        }.value
        currentToken = token
    }
}

// MARK: - Widget Appearance Card

fileprivate struct WebSocketWidgetAppearanceCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Applied (persisted) values. These are the source of truth the overlay
    // reads via `WebSocketServerService.broadcastWidgetConfig()`. The card never
    // writes them on every keystroke, only when the user taps Apply.
    @AppStorage(AppConstants.UserDefaults.widgetTheme)
    private var widgetTheme = AppConstants.Widget.Defaults.theme

    @AppStorage(AppConstants.UserDefaults.widgetLayout)
    private var widgetLayout = AppConstants.Widget.Defaults.layout

    @AppStorage(AppConstants.UserDefaults.widgetTextColor)
    private var widgetTextColor = AppConstants.Widget.Defaults.textColor

    @AppStorage(AppConstants.UserDefaults.widgetBackgroundColor)
    private var widgetBackgroundColor = AppConstants.Widget.Defaults.backgroundColor

    @AppStorage(AppConstants.UserDefaults.widgetFontFamily)
    private var widgetFontFamily = AppConstants.Widget.Defaults.fontFamily

    /// Live edits. Every control binds here and the preview renders this, so
    /// tweaks show instantly without touching the live overlay. `Apply` copies
    /// this into the `@AppStorage` values above and broadcasts; `Revert` drops it.
    @State private var draft: WidgetAppearanceConfig

    /// Font family list loaded off-main on first appear. `availableFontFamilies` enumerates every
    /// installed font (hundreds of entries on design-heavy Macs) and blocks ~100-400ms if invoked
    /// inside `body`. Keep it lazy + off the main thread.
    @State private var fontFamilies: [String] = []

    private let cardPadding = AppConstants.SettingsUI.cardPadding

    init() {
        // Seed the draft from whatever's currently applied. The `@AppStorage`
        // wrappers initialize from their declared defaults; only the draft is
        // overridden here.
        _draft = State(initialValue: WidgetAppearanceConfig.loadApplied())
    }

    /// The currently-applied config, rebuilt from `@AppStorage` so it tracks any
    /// external change. `draft` is compared against this to detect edits.
    private var applied: WidgetAppearanceConfig {
        WidgetAppearanceConfig(
            theme: widgetTheme,
            layout: widgetLayout,
            textColor: widgetTextColor,
            backgroundColor: widgetBackgroundColor,
            fontFamily: widgetFontFamily
        )
    }

    private var isDirty: Bool { draft != applied }

    private var textColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: draft.textColor) ?? .white },
            set: { newColor in
                if let hex = newColor.toHex() { draft.textColor = hex }
            }
        )
    }

    private var backgroundColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: draft.backgroundColor) ?? .black },
            set: { newColor in
                if let hex = newColor.toHex() { draft.backgroundColor = hex }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            widgetAppearanceHeader
            widgetAppearanceCard
            applyBar
            WidgetAppearancePreview(config: draft)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: DSMotion.Duration.fast), value: isDirty)
        .task {
            guard fontFamilies.isEmpty else { return }
            let families = await Task.detached(priority: .userInitiated) {
                NSFontManager.shared.availableFontFamilies.sorted()
            }.value
            fontFamilies = families
        }
    }

    private var widgetAppearanceHeader: some View {
        SectionHeaderWithStatus(
            title: "Widget Appearance",
            subtitle: "Tweak colors, fonts, and layout for your widget.",
            prominence: .section
        )
    }

    private var widgetAppearanceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            twoColumnRow {
                controlCell("Theme") {
                    Picker("", selection: $draft.theme) {
                        ForEach(AppConstants.Widget.themes, id: \.self) { theme in
                            Text(theme).tag(theme)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("Widget theme")
                    .accessibilityIdentifier("widgetThemePicker")
                }
            } trailing: {
                controlCell("Layout") {
                    Picker("", selection: $draft.layout) {
                        ForEach(AppConstants.Widget.layouts, id: \.self) { layout in
                            Text(layout).tag(layout)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("Widget layout")
                    .accessibilityIdentifier("widgetLayoutPicker")
                }
            }

            Divider().padding(.leading, cardPadding)

            // The color row is *always* present (just disabled for preset
            // themes) so switching themes never adds or removes a row. A
            // changing card height shifts everything below it and makes the
            // settings pane scroll-jump.
            twoColumnRow {
                controlCell("Text") {
                    ColorPicker("", selection: textColorBinding, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 40)
                        .accessibilityLabel("Widget text color")
                        .accessibilityIdentifier("widgetTextColorPicker")
                }
            } trailing: {
                controlCell("Background") {
                    ColorPicker("", selection: backgroundColorBinding, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 40)
                        .accessibilityLabel("Widget background color")
                        .accessibilityIdentifier("widgetBackgroundColorPicker")
                }
            }
            .disabled(!draft.themeCustomizable)
            .opacity(draft.themeCustomizable ? 1 : 0.45)

            Text(draft.themeCustomizable
                 ? "Default, Glass, and WolfWave let you pick custom colors."
                 : "\(draft.theme) is a preset. Its colors are fixed.")
                .captionText()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, cardPadding)
                .padding(.bottom, DSSpace.s4)

            Divider().padding(.leading, cardPadding)

            // Font spans the full width (the family name needs the room) but
            // reuses `controlCell` so it reads as a deliberate row, not a
            // leftover beneath the paired controls above.
            controlCell("Font") {
                Picker("", selection: $draft.fontFamily) {
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
            }
            .padding(.vertical, DSSpace.s4)
        }
        .cardStyleUnpadded()
    }

    // MARK: - Apply Bar

    /// Pending-changes footer: an unsaved hint plus Revert / Apply. Everything
    /// above edits `draft`; nothing reaches the live overlay until Apply.
    private var applyBar: some View {
        HStack(spacing: DSSpace.s3) {
            if isDirty {
                Circle()
                    .fill(Color(nsColor: .controlAccentColor))
                    .frame(width: DSSpace.s2, height: DSSpace.s2)
                Text("Unsaved changes").fieldSubtitle()
            } else {
                Text("Overlay is up to date.").fieldSubtitle()
            }
            Spacer(minLength: DSSpace.s2)
            Button("Revert") { draft = applied }
                .disabled(!isDirty)
                .accessibilityIdentifier("widgetAppearanceRevertButton")
            Button("Apply", action: applyChanges)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!isDirty)
                .accessibilityIdentifier("widgetAppearanceApplyButton")
        }
    }

    /// Commit the draft: copy it into the persisted `@AppStorage` values, then
    /// push the new config to every connected overlay.
    private func applyChanges() {
        widgetTheme = draft.theme
        widgetLayout = draft.layout
        widgetTextColor = draft.textColor
        widgetBackgroundColor = draft.backgroundColor
        widgetFontFamily = draft.fontFamily
        broadcastWidgetConfig()
    }

    // MARK: - Layout Helpers

    /// One label-left / control-right cell. Shared by both columns and the
    /// full-width Font row so every appearance control aligns identically.
    @ViewBuilder
    private func controlCell<Control: View>(
        _ label: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: DSSpace.s2) {
            Text(label).font(.system(size: DSFont.Size.base, weight: .medium))
            Spacer(minLength: DSSpace.s2)
            control()
        }
        .padding(.horizontal, cardPadding)
    }

    /// Two equal-width cells split by a hairline divider, matching the app's
    /// other paired settings rows (e.g. Startup / Display Mode).
    @ViewBuilder
    private func twoColumnRow<Leading: View, Trailing: View>(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 0) {
            leading().frame(maxWidth: .infinity)
            Divider()
            trailing().frame(maxWidth: .infinity)
        }
        .padding(.vertical, DSSpace.s4)
    }

    /// Pushes the current widget theme/layout/font/color values to every
    /// connected overlay via `WebSocketServerService.broadcastWidgetConfig()`.
    /// Called from `applyChanges()` when the user taps Apply.
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
            NotificationCenter.default.postWebSocketServerState("listening", clients: 2)
        }
}

#Preview("WebSocket Stopped") {
    @Previewable @AppStorage(AppConstants.UserDefaults.websocketEnabled) var websocketEnabled = false
    WebSocketSettingsView()
        .padding()
        .frame(width: 700)
}
