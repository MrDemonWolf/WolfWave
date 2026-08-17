//
//  WebSocketCustomOverlayCard.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-17.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// The raw WebSocket feed: port, overlay credential, and the two addresses a
/// hand-built overlay connects to.
///
/// Split out of the connection card, and placed last in the pane, because it
/// serves a different person. Someone who just wants a now-playing box on stream
/// needs the Browser Source card above and nothing here; only someone writing
/// their own overlay needs an address and a token. Leading with these rows made
/// a two-click setup look like a programming task.
struct WebSocketCustomOverlayCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(AppConstants.UserDefaults.websocketEnabled)
    private var websocketEnabled = false

    @AppStorage(AppConstants.UserDefaults.streamerModeEnabled)
    private var streamerMode = false

    @AppStorage(AppConstants.UserDefaults.websocketServerPort)
    private var storedPort: Int = Int(AppConstants.WebSocketServer.defaultPort)

    @State private var portText: String = ""

    /// Currently-persisted overlay token. Seeded empty so struct init doesn't hit
    /// the Keychain. Populated by `.task` off-main on first appear, and re-read
    /// after edits or regenerations so the address rows stay in sync.
    @State private var currentToken: String = ""

    /// The control credential, read but never shown here. The editor needs it to
    /// reject an overlay token that collides with it; the two must stay distinct
    /// or the role separation in `WebSocketAuthToken` collapses.
    @State private var currentControlToken: String = ""

    let localNetworkIP: String?

    private let cardPadding = AppConstants.SettingsUI.cardPadding

    /// `nil` until the token is loaded.
    ///
    /// `currentToken` starts empty and is filled by `.task` after the view
    /// appears, so on the first frame these rendered a URL ending in `?token=`.
    /// Copying during that window hands OBS an address that authenticates as
    /// nothing and fails silently, which is a far worse outcome than briefly
    /// showing no address at all.
    private var connectionURL: String? {
        guard !currentToken.isEmpty else { return nil }
        return "ws://localhost:\(storedPort)/?token=\(currentToken)"
    }

    private var networkConnectionURL: String? {
        guard let ip = localNetworkIP, !currentToken.isEmpty else { return nil }
        return "ws://\(ip):\(storedPort)/?token=\(currentToken)"
    }

    private var isPortValid: Bool {
        guard let port = UInt16(portText) else { return false }
        return port >= AppConstants.WebSocketServer.minPort
            && port <= AppConstants.WebSocketServer.maxPort
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DSSpace.s1) {
                CardEyebrowHeader("Build your own overlay", systemImage: "curlybraces")
                Text("Skip this unless you're writing your own overlay. Connect to the address below and WolfWave sends a JSON message on every track change.")
                    .fieldSubtitle()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, cardPadding)
            .padding(.top, DSSpace.s4)
            .padding(.bottom, DSSpace.s3)

            Divider().padding(.leading, cardPadding)

            portRow

            Divider().padding(.leading, cardPadding)

            WebSocketTokenEditorRow(
                role: .overlay,
                title: "Overlay Token",
                subtitle: "Read-only. Anything holding it can watch your now-playing, nothing more.",
                currentToken: $currentToken,
                streamerMode: streamerMode,
                otherToken: currentControlToken
            )

            Divider().padding(.leading, cardPadding)

            if let connectionURL {
                CopyableURLRow(
                    label: "Local Address",
                    url: connectionURL,
                    subtitle: "For an overlay running on this Mac.",
                    isStreamerMode: streamerMode,
                    actionsDisabled: !websocketEnabled,
                    copyAccessibilityLabel: "Copy local connection URL",
                    copyAccessibilityIdentifier: "copyConnectionURLButton"
                )
                .padding(.horizontal, cardPadding)
                .padding(.vertical, DSSpace.s4)
            } else {
                LoadingRow(text: "Loading address\u{2026}")
                    .padding(.horizontal, cardPadding)
                    .padding(.vertical, DSSpace.s4)
            }

            Group {
                if let networkURL = networkConnectionURL {
                    VStack(spacing: 0) {
                        Divider().padding(.leading, cardPadding)
                        CopyableURLRow(
                            label: "Network Address",
                            url: networkURL,
                            subtitle: "For an overlay on a second PC, on the same network.",
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

    // MARK: - Port

    /// The port field, plus the reason it is locked when it is.
    ///
    /// The lock note is rendered *above* the disabled field rather than below it.
    /// Underneath, it was only found after the user had already tried to type
    /// into a greyed-out box and wondered what was broken.
    private var portRow: some View {
        VStack(alignment: .leading, spacing: DSSpace.s2) {
            if websocketEnabled {
                HintRow(
                    "Turn Stream Widgets off to change the port.",
                    systemImage: "lock.fill"
                )
            }

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
            .opacity(websocketEnabled ? 0.5 : 1.0)

            if !portText.isEmpty && !isPortValid {
                HStack(spacing: DSSpace.s1h) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: DSFont.Size.sm))
                    Text(verbatim: "Port must be between \(AppConstants.WebSocketServer.minPort) and \(AppConstants.WebSocketServer.maxPort).")
                        .font(.system(size: DSFont.Size.sm))
                }
                .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, cardPadding)
        .padding(.vertical, DSSpace.s4)
    }

    /// Validates the port text field and, when valid, persists the new port to
    /// UserDefaults and posts a `websocketServerChanged` notification so the
    /// server restarts on the new port.
    private func applyPort() {
        guard isPortValid, let port = UInt16(portText) else { return }
        storedPort = Int(port)
        NotificationCenter.default.postWebSocketServerChanged(port: port)
    }
}
