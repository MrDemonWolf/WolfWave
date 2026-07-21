//
//  CustomCommandTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-07-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Testing
import Foundation
@testable import WolfWave

// MARK: - Context Fixture

private func makeContext(
    username: String = "viewer",
    isModerator: Bool = false,
    isBroadcaster: Bool = false,
    isSubscriber: Bool = false,
    isVIP: Bool = false
) -> BotCommandContext {
    BotCommandContext(
        userID: "123",
        username: username,
        isModerator: isModerator,
        isBroadcaster: isBroadcaster,
        isSubscriber: isSubscriber,
        isVIP: isVIP,
        messageID: "m1"
    )
}

// MARK: - Permission

@Suite("CommandPermission")
struct CommandPermissionTests {

    @Test("everyone always allows")
    func everyone() {
        #expect(CommandPermission.everyone.allows(makeContext()))
    }

    @Test("subscriber allows subs, VIPs, mods, broadcaster; not plain viewers")
    func subscriber() {
        let perm = CommandPermission.subscriber
        #expect(!perm.allows(makeContext()))
        #expect(perm.allows(makeContext(isSubscriber: true)))
        #expect(perm.allows(makeContext(isVIP: true)))
        #expect(perm.allows(makeContext(isModerator: true)))
        #expect(perm.allows(makeContext(isBroadcaster: true)))
    }

    @Test("vip allows VIPs and privileged, not subs")
    func vip() {
        let perm = CommandPermission.vip
        #expect(!perm.allows(makeContext(isSubscriber: true)))
        #expect(perm.allows(makeContext(isVIP: true)))
        #expect(perm.allows(makeContext(isModerator: true)))
    }

    @Test("moderator allows mods and broadcaster only")
    func moderator() {
        let perm = CommandPermission.moderator
        #expect(!perm.allows(makeContext(isVIP: true)))
        #expect(perm.allows(makeContext(isModerator: true)))
        #expect(perm.allows(makeContext(isBroadcaster: true)))
    }

    @Test("broadcaster allows only the broadcaster")
    func broadcaster() {
        let perm = CommandPermission.broadcaster
        #expect(!perm.allows(makeContext(isModerator: true)))
        #expect(perm.allows(makeContext(isBroadcaster: true)))
    }
}

// MARK: - Renderer

@Suite("CustomCommandRenderer")
struct CustomCommandRendererTests {

    private let vars = CustomCommandVariables(currentSong: "Howl", lastSong: "Moonrise")

    @Test("substitutes sender for $user and $sender")
    func user() {
        let out = CustomCommandRenderer.render(
            template: "hi $user / $sender", sender: "Luna", args: [], vars: .empty)
        #expect(out == "hi Luna / Luna")
    }

    @Test("$touser uses first arg with @ stripped, else sender")
    func touser() {
        let hit = CustomCommandRenderer.render(
            template: "$user hugs $touser", sender: "Luna", args: ["@Bob"], vars: .empty)
        #expect(hit == "Luna hugs Bob")

        let fallback = CustomCommandRenderer.render(
            template: "$touser", sender: "Luna", args: [], vars: .empty)
        #expect(fallback == "Luna")
    }

    @Test("$args joins all arguments, $1..$9 are positional")
    func args() {
        let out = CustomCommandRenderer.render(
            template: "[$args] first=$1 third=$3", sender: "x",
            args: ["a", "b", "c"], vars: .empty)
        #expect(out == "[a b c] first=a third=c")
    }

    @Test("absent positional args resolve to empty")
    func missingPositional() {
        let out = CustomCommandRenderer.render(
            template: "x$2y", sender: "x", args: ["only"], vars: .empty)
        #expect(out == "xy")
    }

    @Test("$song and $lastsong pull from variables")
    func song() {
        let out = CustomCommandRenderer.render(
            template: "now $song, was $lastsong", sender: "x", args: [], vars: vars)
        #expect(out == "now Howl, was Moonrise")
    }

    @Test("arguments(from:) drops the trigger token")
    func arguments() {
        #expect(CustomCommandRenderer.arguments(from: "!hug @bob tightly") == ["@bob", "tightly"])
        #expect(CustomCommandRenderer.arguments(from: "!hug").isEmpty)
    }

    @Test("output is truncated to Twitch's limit")
    func truncation() {
        let long = String(repeating: "z", count: 600)
        let out = CustomCommandRenderer.render(
            template: long, sender: "x", args: [], vars: .empty)
        #expect(out.count <= AppConstants.Twitch.maxMessageLength)
    }
}

// MARK: - Normalization

@Suite("CustomCommand normalization")
struct CustomCommandNormalizationTests {

    @Test("trigger gains a single leading !, lowercased, trimmed")
    func normalize() {
        #expect(CustomCommand(trigger: "Hug").normalizedTrigger == "!hug")
        #expect(CustomCommand(trigger: "!!HUG").normalizedTrigger == "!hug")
        #expect(CustomCommand(trigger: "  raid  ").normalizedTrigger == "!raid")
        #expect(CustomCommand(trigger: "!").normalizedTrigger == "")
        #expect(CustomCommand(trigger: "").normalizedTrigger == "")
    }

    @Test("allTriggerTokens includes normalized aliases")
    func aliasTokens() {
        let cmd = CustomCommand(trigger: "hug", aliases: "embrace, !squeeze , ")
        #expect(cmd.allTriggerTokens == ["!hug", "!embrace", "!squeeze"])
    }
}

// MARK: - Command execution

@Suite("CustomBotCommand")
@MainActor
struct CustomBotCommandTests {

    @Test("renders the reply via callback")
    func execute() async {
        let definition = CustomCommand(trigger: "hug", response: "$user hugs $touser")
        let command = CustomBotCommand(definition: definition, variables: { .empty })
        let ctx = makeContext(username: "Luna")

        let reply = await withCheckedContinuation { continuation in
            command.execute(message: "!hug @Bob", context: ctx) { continuation.resume(returning: $0) }
        }
        #expect(reply == "Luna hugs Bob")
    }

    @Test("permission gate reflects the definition")
    func permission() {
        let modOnly = CustomBotCommand(
            definition: CustomCommand(trigger: "raid", permission: .moderator),
            variables: { .empty })
        #expect(!modOnly.isAllowed(context: makeContext()))
        #expect(modOnly.isAllowed(context: makeContext(isModerator: true)))
    }

    @Test("allTriggers and cooldowns come from the definition")
    func metadata() {
        let command = CustomBotCommand(
            definition: CustomCommand(
                trigger: "hug", aliases: "embrace",
                globalCooldown: 7, userCooldown: 12),
            variables: { .empty })
        #expect(command.allTriggers == ["!hug", "!embrace"])
        #expect(command.globalCooldown == 7)
        #expect(command.userCooldown == 12)
    }
}

// MARK: - Store

@Suite("CustomCommandStore")
@MainActor
struct CustomCommandStoreTests {

    private func makeStore() -> (CustomCommandStore, UserDefaults) {
        let suite = "test.customcommands.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (CustomCommandStore(defaults: defaults), defaults)
    }

    @Test("add / update / delete mutate the list")
    func crud() {
        let (store, _) = makeStore()
        var cmd = CustomCommand(trigger: "hug", response: "hi")
        store.add(cmd)
        #expect(store.commands.count == 1)

        cmd.response = "updated"
        store.update(cmd)
        #expect(store.commands.first?.response == "updated")

        store.delete(id: cmd.id)
        #expect(store.commands.isEmpty)
    }

    @Test("commands persist and reload from the same defaults")
    func persistence() {
        let (store, defaults) = makeStore()
        store.add(CustomCommand(trigger: "hug", response: "hi"))

        let reloaded = CustomCommandStore(defaults: defaults)
        #expect(reloaded.commands.count == 1)
        #expect(reloaded.commands.first?.normalizedTrigger == "!hug")
    }

    @Test("enabledCommands drops disabled and triggerless entries")
    func enabledFilter() {
        let (store, _) = makeStore()
        store.add(CustomCommand(trigger: "on", enabled: true))
        store.add(CustomCommand(trigger: "off", enabled: false))
        store.add(CustomCommand(trigger: "", enabled: true))
        #expect(store.enabledCommands.map(\.normalizedTrigger) == ["!on"])
    }

    @Test("triggerConflicts detects duplicate triggers and aliases")
    func conflicts() {
        let (store, _) = makeStore()
        let existing = CustomCommand(trigger: "hug", aliases: "embrace")
        store.add(existing)

        #expect(store.triggerConflicts("hug", excluding: nil))
        #expect(store.triggerConflicts("!embrace", excluding: nil))
        #expect(!store.triggerConflicts("wave", excluding: nil))
        // Editing the same command must not conflict with itself.
        #expect(!store.triggerConflicts("hug", excluding: existing.id))
    }
}
