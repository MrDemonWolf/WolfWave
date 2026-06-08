//
//  CommandSettingRow.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-06-04.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Cooldown configuration for a command row: the Everyone (global) and
/// Per-person (per-user) second values plus their ranges. Ranges are parameters
/// because they differ per pane (Twitch song commands cap the global cooldown at
/// 30s, History's `!stats` allows up to 60s).
struct CommandCooldown {
    let global: Binding<Double>
    let user: Binding<Double>
    var globalRange: ClosedRange<Double> = 0...30
    var userRange: ClosedRange<Double> = 0...60
    var step: Double = 5
}

/// One chat-command row for the "list inside a card" settings pattern.
///
/// At rest it shows a single `ToggleSettingRow` (command name + trigger list +
/// switch). When the command is **on** it reveals one compact details block:
/// optional Everyone/Per-person cooldown sliders, an optional "Custom aliases"
/// field, then any caller-supplied `extra` content (e.g. the `!wolfwave` reply
/// picker). The whole command carries a single trailing `Divider` (gated by
/// `isLast`) instead of one per sub-row, which is what makes the card compact.
///
/// Drop instances into a `VStack(spacing: 1) { … }.cardStyleUnpadded()` so the
/// hairlines line up. Shared by the Twitch Bot Commands and Song Request
/// Commands panes; the cooldown sliders reuse ``LabeledSlider`` and the alias
/// field reuses ``CommandAliasField``.
struct CommandSettingRow<Extra: View>: View {

    // MARK: - Properties

    let title: String
    let triggers: String
    @Binding var isOn: Bool
    let accessibilityLabel: String
    let accessibilityIdentifier: String

    var cooldown: CommandCooldown?
    var aliases: Binding<String>?
    var aliasPlaceholder: String
    var aliasAccessibilityLabel: String
    var aliasAccessibilityIdentifier: String?

    var isLast: Bool
    var onChange: ((Bool) -> Void)?
    @ViewBuilder let extra: () -> Extra

    // MARK: - Init

    init(
        title: String,
        triggers: String,
        isOn: Binding<Bool>,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        cooldown: CommandCooldown? = nil,
        aliases: Binding<String>? = nil,
        aliasPlaceholder: String = "e.g. np, track",
        aliasAccessibilityLabel: String = "Custom aliases",
        aliasAccessibilityIdentifier: String? = nil,
        isLast: Bool = false,
        onChange: ((Bool) -> Void)? = nil,
        @ViewBuilder extra: @escaping () -> Extra
    ) {
        self.title = title
        self.triggers = triggers
        self._isOn = isOn
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.cooldown = cooldown
        self.aliases = aliases
        self.aliasPlaceholder = aliasPlaceholder
        self.aliasAccessibilityLabel = aliasAccessibilityLabel
        self.aliasAccessibilityIdentifier = aliasAccessibilityIdentifier
        self.isLast = isLast
        self.onChange = onChange
        self.extra = extra
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ToggleSettingRow(
                title: title,
                subtitle: triggers,
                isOn: $isOn,
                accessibilityLabel: accessibilityLabel,
                accessibilityIdentifier: accessibilityIdentifier,
                onChange: onChange
            )
            .padding(.horizontal, AppConstants.SettingsUI.cardPadding)
            .padding(.top, DSSpace.s4)
            .padding(.bottom, showsDetails ? DSSpace.s2 : DSSpace.s4)

            if showsDetails {
                details
            }
        }
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
                    .padding(.leading, AppConstants.SettingsUI.cardPadding)
            }
        }
    }

    // MARK: - Private Helpers

    /// Whether the caller supplied trailing `extra` content. A toggle-only row
    /// (no cooldown, no aliases, `Extra == EmptyView`) renders just the switch,
    /// so the details block (and its padding) is skipped entirely.
    private var hasExtra: Bool { Extra.self != EmptyView.self }

    /// The expandable details block only appears when the command is on *and*
    /// there is something to show.
    private var showsDetails: Bool {
        isOn && (cooldown != nil || aliases != nil || hasExtra)
    }

    // MARK: - Private Views

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: DSSpace.s2) {
            if let cooldown {
                CooldownSliderPair(
                    everyone: .init(
                        label: "Everyone",
                        value: cooldown.global,
                        range: cooldown.globalRange,
                        step: cooldown.step,
                        accessibilityIdentifier: "\(accessibilityIdentifier).everyoneCooldown"
                    ),
                    perPerson: .init(
                        label: "Per person",
                        value: cooldown.user,
                        range: cooldown.userRange,
                        step: cooldown.step,
                        accessibilityIdentifier: "\(accessibilityIdentifier).perUserCooldown"
                    )
                )
            }

            if let aliases {
                CommandAliasField(
                    aliases: aliases,
                    placeholder: aliasPlaceholder,
                    accessibilityLabel: aliasAccessibilityLabel,
                    accessibilityIdentifier: aliasAccessibilityIdentifier
                )
            }

            extra()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppConstants.SettingsUI.cardPadding)
        .padding(.bottom, DSSpace.s4)
    }
}

// MARK: - No-extra convenience init

extension CommandSettingRow where Extra == EmptyView {
    /// Convenience initializer for command rows that need no trailing `extra`
    /// content (the common case). Defaults the `extra` slot to `EmptyView`.
    init(
        title: String,
        triggers: String,
        isOn: Binding<Bool>,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        cooldown: CommandCooldown? = nil,
        aliases: Binding<String>? = nil,
        aliasPlaceholder: String = "e.g. np, track",
        aliasAccessibilityLabel: String = "Custom aliases",
        aliasAccessibilityIdentifier: String? = nil,
        isLast: Bool = false,
        onChange: ((Bool) -> Void)? = nil
    ) {
        self.init(
            title: title,
            triggers: triggers,
            isOn: isOn,
            accessibilityLabel: accessibilityLabel,
            accessibilityIdentifier: accessibilityIdentifier,
            cooldown: cooldown,
            aliases: aliases,
            aliasPlaceholder: aliasPlaceholder,
            aliasAccessibilityLabel: aliasAccessibilityLabel,
            aliasAccessibilityIdentifier: aliasAccessibilityIdentifier,
            isLast: isLast,
            onChange: onChange,
            extra: { EmptyView() }
        )
    }
}

// MARK: - Preview

#Preview("Command rows") {
    struct Wrapper: View {
        @State private var songOn = true
        @State private var lastOn = false
        @State private var infoOn = true
        @State private var songGlobal: Double = 15
        @State private var songUser: Double = 15
        @State private var songAliases = "np, track"
        @State private var replyStyle = "credit"

        var body: some View {
            VStack(spacing: 1) {
                CommandSettingRow(
                    title: "!song Command",
                    triggers: "!song  ·  !currentsong  ·  !nowplaying",
                    isOn: $songOn,
                    accessibilityLabel: "Enable song command",
                    accessibilityIdentifier: "preview.song",
                    cooldown: .init(global: $songGlobal, user: $songUser),
                    aliases: $songAliases,
                    aliasAccessibilityIdentifier: "preview.songAliases"
                )

                CommandSettingRow(
                    title: "!last Command",
                    triggers: "!last  ·  !lastsong  ·  !prevsong",
                    isOn: $lastOn,
                    accessibilityLabel: "Enable last command",
                    accessibilityIdentifier: "preview.last"
                )

                CommandSettingRow(
                    title: "!wolfwave Command",
                    triggers: "!wolfwave  ·  what WolfWave is + where to get it",
                    isOn: $infoOn,
                    accessibilityLabel: "Enable wolfwave command",
                    accessibilityIdentifier: "preview.wolfwave",
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
            .padding()
            .frame(width: 640)
        }
    }
    return Wrapper()
}
