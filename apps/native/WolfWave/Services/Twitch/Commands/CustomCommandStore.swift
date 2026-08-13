//
//  CustomCommandStore.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-07-15.
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
    init(defaults: UserDefaults = DefaultsStore.store) {
        self.defaults = defaults
        load()
    }

    // MARK: - Mutation

    /// Appends a new command and persists.
    func add(_ command: CustomCommand) {
        guard let normalized = CustomCommand.normalizedForImport(commands + [command]) else {
            return
        }
        commands = normalized
        save()
    }

    /// Replaces the command with the same `id` (no-op if absent) and persists.
    func update(_ command: CustomCommand) {
        guard let index = commands.firstIndex(where: { $0.id == command.id }) else { return }
        var updated = commands
        updated[index] = command
        guard let normalized = CustomCommand.normalizedForImport(updated) else { return }
        commands = normalized
        save()
    }

    /// Removes the command with `id` and persists.
    func delete(id: UUID) {
        commands.removeAll { $0.id == id }
        save()
    }

    /// Removes every command and persists the empty live snapshot.
    ///
    /// Factory reset calls this before deleting the backing preference so the
    /// shared store cannot later re-save a stale in-memory command list after a
    /// failed relaunch.
    func clearAll() {
        commands.removeAll()
        save()
    }

    /// Whether `trigger` (any alias too) is already claimed by a command other
    /// than `excluding`. Used by the editor to block duplicate triggers, which
    /// the dispatcher resolves by first-match and would otherwise shadow.
    func commandConflicts(_ candidate: CustomCommand) -> Bool {
        guard CustomCommand.normalizedForImport([candidate]) != nil else { return true }
        let claimed = Set(
            commands
                .filter { $0.id != candidate.id }
                .flatMap(\.allTriggerTokens)
        )
        return candidate.allTriggerTokens.contains { claimed.contains($0) }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: key) else {
            commands = []
            return
        }
        guard let decoded = try? JSONCoders.default.decode([CustomCommand].self, from: data),
              let normalized = CustomCommand.normalizedForExistingStorage(decoded) else {
            commands = []
            return
        }
        commands = normalized
        if normalized != decoded { save() }
    }

    /// Atomically replaces the live and persisted command snapshot during
    /// settings import. Invalid bytes leave the current commands untouched.
    @discardableResult
    func replaceFromImportedData(_ data: Data) -> Bool {
        guard let decoded = try? JSONCoders.default.decode(
            [CustomCommand].self,
            from: data
        ),
        let imported = CustomCommand.normalizedForImport(decoded),
        let normalizedData = try? JSONCoders.defaultEncoder.encode(imported)
        else { return false }
        commands = imported
        defaults.set(normalizedData, forKey: key)
        return true
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
