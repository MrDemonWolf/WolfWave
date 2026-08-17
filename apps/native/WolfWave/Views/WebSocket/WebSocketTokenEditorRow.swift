//
//  WebSocketTokenEditorRow.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-17.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

// MARK: - WebSocket Token Editor

/// Shared editor for the two role-specific credentials. Keeping one row
/// implementation prevents overlay and Stream Deck validation or masking
/// behavior from drifting while preserving the existing settings-card design.
struct WebSocketTokenEditorRow: View {
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
                category: .websocket
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
                category: .websocket
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
