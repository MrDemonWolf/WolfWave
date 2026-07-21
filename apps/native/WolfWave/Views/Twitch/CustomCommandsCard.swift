//
//  CustomCommandsCard.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-07-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI

/// Custom Commands card for the Twitch settings pane.
///
/// Lists the user's own chat commands and hosts the add/edit sheet. Backed by
/// the shared ``CustomCommandStore`` singleton (the same instance the dispatcher
/// reads), so a saved edit takes effect on the next chat line.
struct CustomCommandsCard: View {

    /// The shared store; `@State` pins the singleton's identity for the view's
    /// lifetime while Observation tracks its property reads.
    @State private var store = CustomCommandStore.shared

    /// The command currently open in the editor sheet, if any.
    @State private var editing: CustomCommand?

    /// `true` when `editing` is a brand-new command (Save appends) vs an edit.
    @State private var isNewCommand = false

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s6) {
            SectionHeaderWithStatus(
                title: "Custom Commands",
                subtitle: "Make your own chat commands with a fixed reply.",
                prominence: .section
            )

            if store.commands.isEmpty {
                emptyState
            } else {
                VStack(spacing: 1) {
                    ForEach(store.commands) { command in
                        row(for: command)
                    }
                }
                .cardStyleUnpadded()
            }

            Button {
                isNewCommand = true
                editing = CustomCommand()
            } label: {
                Label("Add command", systemImage: "plus")
            }
            .controlSize(.small)
            .accessibilityIdentifier("addCustomCommand")

            HintRow("Use variables like $user, $touser, $args, $1, $song in your reply.")
        }
        .sheet(item: $editing) { command in
            CustomCommandEditor(
                command: command,
                isNew: isNewCommand,
                store: store,
                onSave: { saved in
                    if isNewCommand {
                        store.add(saved)
                    } else {
                        store.update(saved)
                    }
                    editing = nil
                },
                onDelete: {
                    store.delete(id: command.id)
                    editing = nil
                },
                onCancel: { editing = nil }
            )
        }
    }

    // MARK: - Rows

    private var emptyState: some View {
        Text("No custom commands yet. Add one to reply to a chat trigger.")
            .fieldSubtitle()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppConstants.SettingsUI.cardPadding)
            .cardStyle()
    }

    private func row(for command: CustomCommand) -> some View {
        HStack(spacing: DSSpace.s3) {
            VStack(alignment: .leading, spacing: DSSpace.s0) {
                Text(command.normalizedTrigger.isEmpty ? "(no trigger)" : command.normalizedTrigger)
                    .font(.system(size: DSFont.Size.base, weight: .semibold))
                    .foregroundStyle(command.enabled ? .primary : .secondary)

                Text(command.response.isEmpty ? "No reply set" : command.response)
                    .font(.system(size: DSFont.Size.sm))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: DSSpace.s2)

            StatusChip(text: command.permission.label, color: .accentColor)

            Toggle("", isOn: enabledBinding(for: command))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel("Enable \(command.normalizedTrigger)")
                .accessibilityIdentifier("customCommandToggle.\(command.normalizedTrigger)")
                .accessibilityValue(command.enabled ? "Enabled" : "Disabled")

            DSIconButton(
                systemImage: "pencil",
                action: {
                    isNewCommand = false
                    editing = command
                },
                accessibilityLabel: "Edit \(command.normalizedTrigger)"
            )
        }
        .padding(.horizontal, AppConstants.SettingsUI.cardPadding)
        .padding(.vertical, DSSpace.s3)
        .overlay(alignment: .bottom) {
            if command.id != store.commands.last?.id {
                Divider().padding(.leading, AppConstants.SettingsUI.cardPadding)
            }
        }
    }

    /// A binding that flips a single command's `enabled` flag through the store
    /// (so the change persists and re-renders the list).
    private func enabledBinding(for command: CustomCommand) -> Binding<Bool> {
        Binding(
            get: { command.enabled },
            set: { newValue in
                var updated = command
                updated.enabled = newValue
                store.update(updated)
            }
        )
    }
}

// MARK: - Editor

/// Add/edit sheet for one custom command. Keeps a working copy so Cancel is a
/// true no-op; validation blocks Save on an empty or duplicate trigger.
private struct CustomCommandEditor: View {

    @State private var draft: CustomCommand
    let isNew: Bool
    let store: CustomCommandStore
    let onSave: (CustomCommand) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    init(
        command: CustomCommand,
        isNew: Bool,
        store: CustomCommandStore,
        onSave: @escaping (CustomCommand) -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: command)
        self.isNew = isNew
        self.store = store
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    private var triggerEmpty: Bool { draft.normalizedTrigger.isEmpty }
    private var triggerConflicts: Bool {
        store.triggerConflicts(draft.trigger, excluding: draft.id)
    }
    private var isValid: Bool { !triggerEmpty && !triggerConflicts }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpace.s5) {
            Text(isNew ? "New Command" : "Edit Command")
                .paneTitle()

            VStack(alignment: .leading, spacing: DSSpace.s2) {
                Text("Trigger").sectionEyebrow()
                TextField("!hug", text: $draft.trigger)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("customCommandTrigger")
                if triggerConflicts {
                    Text("Another command already uses that trigger.")
                        .font(.system(size: DSFont.Size.sm))
                        .foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: DSSpace.s2) {
                Text("Reply").sectionEyebrow()
                TextField("$user gives $touser a big hug!", text: $draft.response, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...5)
                    .accessibilityIdentifier("customCommandResponse")
            }

            HStack(spacing: DSSpace.s2) {
                Text("Who can use it").sectionEyebrow()
                Spacer()
                Picker("Permission", selection: $draft.permission) {
                    ForEach(CommandPermission.allCases) { permission in
                        Text(permission.label).tag(permission)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(maxWidth: AppConstants.SettingsUI.inlineFieldMaxWidth)
                .accessibilityIdentifier("customCommandPermission")
            }

            CommandAliasField(
                aliases: $draft.aliases,
                accessibilityIdentifier: "customCommandAliases"
            )

            CooldownSliderPair(
                everyone: .init(
                    label: "Everyone",
                    value: $draft.globalCooldown,
                    range: 0...30,
                    step: 5,
                    accessibilityIdentifier: "customCommand.everyoneCooldown"
                ),
                perPerson: .init(
                    label: "Per person",
                    value: $draft.userCooldown,
                    range: 0...60,
                    step: 5,
                    accessibilityIdentifier: "customCommand.perUserCooldown"
                )
            )

            variableLegend

            Spacer(minLength: 0)

            HStack {
                if !isNew {
                    Button("Delete", role: .destructive, action: onDelete)
                        .accessibilityIdentifier("deleteCustomCommand")
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(normalized()) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
                    .accessibilityIdentifier("saveCustomCommand")
            }
        }
        .padding(DSSpace.s7)
        .frame(width: 460, height: 520)
    }

    /// A short reference of the supported variables.
    private var variableLegend: some View {
        VStack(alignment: .leading, spacing: DSSpace.s1) {
            Text("Variables").sectionEyebrow()
            Text("$user · $touser · $args · $1–$9 · $song · $lastsong")
                .font(.system(size: DSFont.Size.sm))
                .foregroundStyle(.secondary)
        }
    }

    /// Store the trigger in its normalized form so the list and matcher agree.
    private func normalized() -> CustomCommand {
        var result = draft
        result.trigger = draft.normalizedTrigger
        return result
    }
}

// MARK: - Preview

#Preview("Custom Commands") {
    CustomCommandsCard()
        .padding()
        .frame(width: 700)
}
