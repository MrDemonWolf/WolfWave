//
//  CustomCommandStore.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-07-14.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Persists the user's custom chat commands as JSON in `UserDefaults` and exposes
/// them as an observable list for the settings UI.
///
/// The dispatcher reads ``enabledCommands`` on the MainActor each time it matches
/// a message, so edits take effect on the next chat line without re-registration.
@Observable
@MainActor
final class CustomCommandStore {

    /// Shared instance read by the dispatcher and the settings pane.
    static let shared = CustomCommandStore()

    /// All commands, in display/persistence order.
    private(set) var commands: [CustomCommand] = []

    /// Enabled commands with a usable trigger. This is what the dispatcher runs.
    var enabledCommands: [CustomCommand] {
        commands.filter { $0.enabled && !$0.normalizedTrigger.isEmpty }
    }

    private let defaults: UserDefaults
    private let key = AppConstants.UserDefaults.customCommands

    /// - Parameter defaults: Injection seam for tests; production uses `.standard`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Mutation

    /// Appends a new command and persists.
    func add(_ command: CustomCommand) {
        commands.append(command)
        save()
    }

    /// Replaces the command with the same `id` (no-op if absent) and persists.
    func update(_ command: CustomCommand) {
        guard let index = commands.firstIndex(where: { $0.id == command.id }) else { return }
        commands[index] = command
        save()
    }

    /// Removes the command with `id` and persists.
    func delete(id: UUID) {
        commands.removeAll { $0.id == id }
        save()
    }

    /// Whether `trigger` (any alias too) is already claimed by a command other
    /// than `excluding`. Used by the editor to block duplicate triggers, which
    /// the dispatcher resolves by first-match and would otherwise shadow.
    func triggerConflicts(_ trigger: String, excluding id: UUID?) -> Bool {
        let candidate = CustomCommand.normalizeTrigger(trigger)
        guard !candidate.isEmpty else { return false }
        return commands.contains { command in
            command.id != id && command.allTriggerTokens.contains(candidate)
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: key) else { return }
        commands = (try? JSONCoders.default.decode([CustomCommand].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONCoders.defaultEncoder.encode(commands) else { return }
        defaults.set(data, forKey: key)
    }
}

// MARK: - Trigger tokens

nonisolated extension CustomCommand {
    /// The normalized primary trigger plus every normalized alias.
    var allTriggerTokens: [String] {
        var tokens = [normalizedTrigger]
        tokens += aliases.split(separator: ",")
            .map { CustomCommand.normalizeTrigger(String($0)) }
        return tokens.filter { !$0.isEmpty }
    }
}
