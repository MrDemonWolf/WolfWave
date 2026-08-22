//
//  ComponentGallery+Rows.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

#if DEBUG
import SwiftUI

extension DebugComponentGalleryCard {

    /// Rows & fields: `InfoRow`, `ToggleSettingRow`, `CommandAliasField`,
    /// `CommandSettingRow`, `CooldownSliderPair`, `LabeledSlider`, `CopyableURLRow`,
    /// `FieldValidationRow`, `LoadingRow`, `SuccessFeedbackRow`, `HintRow`, `StatTile`,
    /// and the `Binding+Sanitized` helpers.
    @ViewBuilder var rowsSection: some View {
        GalleryEntry(typeName: "InfoRow") {
            VStack(spacing: DSSpace.s4) {
                InfoRow(label: "Local Address", value: "ws://localhost:8765")
                InfoRow(label: "Version", value: "1.2.0", isMonospaced: false)
            }
        }

        GalleryEntry(typeName: "ToggleSettingRow", width: GalleryWidth.wide) {
            VStack(spacing: DSSpace.s6) {
                ToggleSettingRow(
                    title: "Enable Feature",
                    subtitle: "A short description of what this does",
                    isOn: .constant(true),
                    accessibilityLabel: "Enable Feature",
                    accessibilityIdentifier: "gallery.featureToggle"
                )
                .cardStyle()
                ToggleSettingRow(
                    title: "Disabled Feature",
                    subtitle: "This one is disabled",
                    isOn: .constant(false),
                    isDisabled: true,
                    accessibilityLabel: "Disabled Feature",
                    accessibilityIdentifier: "gallery.disabledToggle"
                )
                .cardStyle()
            }
        }

        GalleryEntry(typeName: "CommandAliasField", width: GalleryWidth.wide) {
            CommandAliasField(aliases: $aliases, accessibilityIdentifier: "gallery.aliases")
        }

        GalleryEntry(typeName: "CommandSettingRow", width: GalleryWidth.full) {
            VStack(spacing: 1) {
                CommandSettingRow(
                    title: "!song Command",
                    triggers: "!song  ·  !currentsong  ·  !nowplaying",
                    isOn: $songOn,
                    accessibilityLabel: "Enable song command",
                    accessibilityIdentifier: "gallery.song",
                    cooldown: .init(global: $songGlobal, user: $songUser),
                    aliases: $songAliases,
                    aliasAccessibilityIdentifier: "gallery.songAliases"
                )
                CommandSettingRow(
                    title: "!last Command",
                    triggers: "!last  ·  !lastsong  ·  !prevsong",
                    isOn: $lastOn,
                    accessibilityLabel: "Enable last command",
                    accessibilityIdentifier: "gallery.last"
                )
                CommandSettingRow(
                    title: "!wolfwave Command",
                    triggers: "!wolfwave  ·  what WolfWave is + where to get it",
                    isOn: $infoOn,
                    accessibilityLabel: "Enable wolfwave command",
                    accessibilityIdentifier: "gallery.wolfwave",
                    isLast: true
                ) {
                    Picker("Reply", selection: $replyStyle) {
                        Text("Credit + maker").tag("credit")
                        Text("How to get it").tag("howto")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(maxWidth: AppConstants.SettingsUI.inlineFieldMaxWidth)
                }
            }
            .cardStyleUnpadded()
        }

        GalleryEntry(typeName: "CooldownSliderPair", width: GalleryWidth.wide) {
            CooldownSliderPair(
                everyone: .init(label: "Everyone", value: $everyone),
                perPerson: .init(label: "Per person", value: $perUser)
            )
        }

        GalleryEntry(typeName: "LabeledSlider", width: GalleryWidth.wide) {
            VStack(spacing: DSSpace.s4) {
                LabeledSlider(label: "Everyone", value: $everyone, range: 5...120, format: { "\(Int($0))s" })
                LabeledSlider(label: "Per person", value: $perUser, range: 5...300, format: { "\(Int($0))s" })
            }
        }

        GalleryEntry(typeName: "CopyableURLRow", width: GalleryWidth.wide) {
            VStack(spacing: DSSpace.s6) {
                CopyableURLRow(
                    label: "Local Address",
                    url: "ws://localhost:8765/?token=abcdef",
                    isStreamerMode: false,
                    copyAccessibilityLabel: "Copy local connection URL"
                )
                Divider()
                CopyableURLRow(
                    label: "Network Address",
                    url: "ws://192.168.1.20:8765/?token=abcdef",
                    subtitle: "Use this for two-PC setups.",
                    isStreamerMode: false,
                    copyAccessibilityLabel: "Copy network connection URL"
                )
                Divider()
                CopyableURLRow(
                    url: "http://localhost:8766",
                    isStreamerMode: false,
                    urlLineLimit: 2,
                    copyLabel: "Copy Link",
                    copiedLabel: "Copied",
                    copyAccessibilityLabel: "Copy widget URL"
                ) {
                    OpenInBrowserButton(urlString: "http://localhost:8766", accessibilityLabel: "Open widget in browser")
                }
                Divider()
                CopyableURLRow(
                    label: "Network Address",
                    url: "http://192.168.1.20:8766/?token=abcdef",
                    subtitle: "Use this for two-PC setups.",
                    isStreamerMode: true,
                    copyLabel: "Copy Link",
                    copiedLabel: "Copied",
                    copyAccessibilityLabel: "Copy network widget URL"
                ) {
                    OpenInBrowserButton(
                        urlString: "http://192.168.1.20:8766",
                        isDisabled: true,
                        accessibilityLabel: "Open network widget in browser"
                    )
                }
            }
        }

        GalleryEntry(typeName: "FieldValidationRow", width: GalleryWidth.wide, note: ".idle renders nothing") {
            VStack(alignment: .leading, spacing: DSSpace.s4) {
                FieldValidationRow(state: .idle)
                FieldValidationRow(state: .validating("Verifying channel\u{2026}"))
                FieldValidationRow(state: .valid("Channel verified"))
                FieldValidationRow(
                    state: .invalid("No Twitch channel by that name. Check the spelling, then choose Join.")
                )
                FieldValidationRow(state: .failed(UserFacingError(
                    id: "twitch.signInExpired",
                    title: "Twitch sign-in expired",
                    fix: "Reconnect, then choose Join.",
                    severity: .warning
                )))
                FieldValidationRow(state: .failed(UserFacingError(
                    id: "widget.tokenFormat",
                    title: "Use exactly 64 hex characters",
                    cause: "Only 0-9 and a-f are allowed.",
                    severity: .error
                )))
            }
        }

        GalleryEntry(typeName: "LoadingRow", width: GalleryWidth.narrow) {
            VStack(spacing: DSSpace.s4) {
                LoadingRow(text: "Waiting for Twitch…")
                LoadingRow(text: "Testing…")
            }
        }

        GalleryEntry(typeName: "SuccessFeedbackRow") {
            VStack(spacing: DSSpace.s4) {
                SuccessFeedbackRow(text: "Discord Status enabled!")
                SuccessFeedbackRow(text: "You're all set!", fontWeight: .medium)
            }
        }

        GalleryEntry(typeName: "HintRow", width: GalleryWidth.wide) {
            VStack(alignment: .leading, spacing: DSSpace.s3) {
                HintRow("Cooldowns don't apply to you or your mods.")
                HintRow("Nothing is uploaded. Everything stays on this Mac.", systemImage: "lock.fill")
            }
        }

        GalleryEntry(typeName: "StatTile", width: GalleryWidth.wide) {
            HStack(spacing: 0) {
                StatTile(value: "129", secondary: "27m", caption: "This week")
                Divider().frame(height: DSSpace.s11)
                StatTile(value: "22", secondary: "4m", caption: "Today")
                Divider().frame(height: DSSpace.s11)
                StatTile(value: "129", secondary: "27m", caption: "All time")
            }
        }

        GalleryEntry(typeName: "Binding+Sanitized", note: "snapped(to:fallback:) over a stored 99") {
            HStack(spacing: DSSpace.s4) {
                Picker("Window", selection: $unsnappedWindow.snapped(to: [15, 30, 60], fallback: 30)) {
                    Text("15s").tag(15)
                    Text("30s").tag(30)
                    Text("60s").tag(60)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                Text("stored: \(unsnappedWindow)")
                    .font(.system(size: DSFont.Size.sm, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
#endif
