//
//  StreamDeckSettingsView.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-17.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Stream Deck control: the capability switch, the credential, and how to set up
/// the plugin.
///
/// Split out of Stream Widgets, which had both credentials one divider apart in
/// a single card. They share a server and a port but not a threat model: the
/// overlay token is read-only and reachable across the LAN, while this one runs
/// commands and is refused from anything but literal loopback. Rendering them as
/// siblings said, through proximity alone, that they were interchangeable.
struct StreamDeckSettingsView: View {

    /// Sends the user to Stream Widgets, which owns the shared server switch.
    let openStreamWidgets: () -> Void

    @AppStorage(AppConstants.UserDefaults.streamDeckControlEnabled)
    private var controlEnabled = AppConstants.UserDefaults.Defaults.streamDeckControlEnabled

    @AppStorage(AppConstants.UserDefaults.websocketEnabled)
    private var websocketEnabled = false

    @AppStorage(AppConstants.UserDefaults.streamerModeEnabled)
    private var streamerMode = false

    @State private var currentControlToken: String = ""

    /// The overlay credential, read but never shown here. The editor needs it to
    /// reject a control token that collides with it.
    @State private var currentOverlayToken: String = ""

    private let cardPadding = AppConstants.SettingsUI.cardPadding

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.SettingsUI.sectionSpacing) {
            SectionHeaderWithStatus(
                title: "Stream Deck",
                subtitle: "Run WolfWave from a Stream Deck key.",
                statusText: status.text,
                statusColor: status.color,
                statusSymbol: status.symbol
            )

            controlCard
            tokenCard
            setupCard
        }
        .task {
            guard currentControlToken.isEmpty || currentOverlayToken.isEmpty else { return }
            let tokens = await Task.detached(priority: .userInitiated) {
                (
                    WebSocketAuthToken.currentOrCreate(for: .control),
                    WebSocketAuthToken.currentOrCreate(for: .overlay)
                )
            }.value
            currentControlToken = tokens.0
            currentOverlayToken = tokens.1
        }
    }

    // MARK: - Status

    /// Reports the first thing standing between the user and a working key, so
    /// the chip is never a bare "Off" that leaves them hunting for which switch.
    /// Resolution lives in ``StreamDeckPaneStatus`` so the precedence rule is
    /// testable without the view.
    private var status: StreamDeckPaneStatus.Resolved {
        StreamDeckPaneStatus.resolve(
            controlEnabled: controlEnabled,
            serverEnabled: websocketEnabled
        )
    }

    // MARK: - Control Card

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ToggleSettingRow(
                title: "Allow Stream Deck commands",
                subtitle: "Let a Stream Deck key skip songs, hold the queue, and toggle your overlay.",
                isOn: $controlEnabled,
                accessibilityLabel: "Toggle Stream Deck commands",
                accessibilityIdentifier: "streamDeckControlEnabledToggle"
            )
            .padding(.horizontal, cardPadding)
            .padding(.vertical, DSSpace.s4)

            Divider().padding(.leading, cardPadding)

            HintRow(
                "Commands are only accepted from this Mac. A Stream Deck on another"
                    + " machine, or anything on your network, is refused.",
                systemImage: "lock.laptopcomputer"
            )
            .padding(.horizontal, cardPadding)
            .padding(.bottom, DSSpace.s4)

            // The coupling, stated rather than hidden. Both panes are served by
            // one WebSocketServerService on one port, so turning this on while
            // the server is off does nothing, and a key would just sit there
            // looking broken.
            if !websocketEnabled {
                VStack(alignment: .leading, spacing: DSSpace.s2) {
                    CalloutBanner(
                        "Stream Deck and your overlay share one connection, and it's currently off."
                            + " Turn on Stream Widgets and your keys start working.",
                        title: "The connection is off",
                        style: .warning,
                        systemImage: "bolt.horizontal.circle"
                    )
                    Button("Open Stream Widgets", action: openStreamWidgets)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityIdentifier("streamDeckOpenStreamWidgetsButton")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, cardPadding)
                .padding(.bottom, DSSpace.s4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyleUnpadded()
    }

    // MARK: - Token Card

    private var tokenCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DSSpace.s1) {
                CardEyebrowHeader("Control token", systemImage: "key.fill")
                Text("Paste this into the plugin's settings in the Stream Deck app. Treat it like a password: anything holding it can drive WolfWave from this Mac.")
                    .fieldSubtitle()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, cardPadding)
            .padding(.top, DSSpace.s4)

            // No divider: the eyebrow above is this card's only header, and the
            // row below carries its own field label. A rule between them read as
            // two separate headed sections stacked in one card.
            WebSocketTokenEditorRow(
                role: .control,
                title: "Stream Deck Control Token",
                subtitle: "Different from your overlay token, and it must stay different.",
                currentToken: $currentControlToken,
                streamerMode: streamerMode,
                otherToken: currentOverlayToken
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyleUnpadded()
    }

    // MARK: - Setup Card

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: DSSpace.s3) {
            CardEyebrowHeader("Setting it up", systemImage: "list.number")

            VStack(alignment: .leading, spacing: DSSpace.s2) {
                ForEach(Array(Self.setupSteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: DSSpace.s2) {
                        Text(verbatim: "\(index + 1).")
                            .font(.system(size: DSFont.Size.sm, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(
                                width: DSDimension.Settings.stepNumberGutter,
                                alignment: .trailing
                            )
                        Text(step)
                            .fieldSubtitle()
                    }
                    // Combined so VoiceOver announces "1. Build the plugin…" as
                    // one item instead of reading the numeral on its own.
                    .accessibilityElement(children: .combine)
                }
            }

            HintRow(
                "No Stream Deck hardware? The Stream Deck mobile app gives you six keys for free.",
                systemImage: "iphone"
            )

            OpenInBrowserButton(
                urlString: AppConstants.URLs.streamDeckGuide,
                title: "Stream Deck Setup Guide",
                accessibilityLabel: "Open the Stream Deck setup guide",
                accessibilityIdentifier: "streamDeckDocsButton"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(cardPadding)
        .cardStyleUnpadded()
    }

    /// Kept as plain data so the copy is reviewable in one place rather than
    /// scattered through the view builder.
    ///
    /// Step 1 says "build it" rather than naming the Elgato Marketplace: the
    /// plugin is not listed there yet, and this pane was the only place in the
    /// product claiming otherwise. Step 4 names the port alone because the
    /// plugin pins the host to loopback and exposes no field for it.
    private static let setupSteps = [
        "Build the plugin from the repo and double-click it to install. The guide below has the commands.",
        "Drag a WolfWave key onto a page in the Stream Deck app.",
        "Open the key's settings and paste the control token above.",
        "Leave the port alone unless you changed it in Stream Widgets."
    ]
}
