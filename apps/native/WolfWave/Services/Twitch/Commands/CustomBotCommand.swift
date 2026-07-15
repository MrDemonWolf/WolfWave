//
//  CustomBotCommand.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-07-14.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Runtime adapter that turns a stored ``CustomCommand`` definition into a
/// dispatchable ``AsyncBotCommand``.
///
/// It is async because the reply may interpolate live state (`$song`) fetched
/// through the same providers the built-in `!song` command uses. Permission is
/// enforced by the dispatcher via ``isAllowed(context:)`` before the cooldown is
/// recorded, so a denied viewer can't burn the shared cooldown.
final class CustomBotCommand: AsyncBotCommand {

    // MARK: - Properties

    let definition: CustomCommand

    /// Fetches live substitution values (current/last song) at send time.
    private let variables: @Sendable () async -> CustomCommandVariables

    init(
        definition: CustomCommand,
        variables: @escaping @Sendable () async -> CustomCommandVariables
    ) {
        self.definition = definition
        self.variables = variables
    }

    // MARK: - BotCommand

    var triggers: [String] { [definition.normalizedTrigger] }

    var description: String { "Custom command \(definition.normalizedTrigger)" }

    var globalCooldown: TimeInterval { definition.globalCooldown }

    var userCooldown: TimeInterval { definition.userCooldown }

    /// Primary trigger plus the definition's aliases. Overrides the protocol
    /// default (which reads aliases from a `UserDefaults` key) because a custom
    /// command carries its aliases inline.
    var allTriggers: [String] { definition.allTriggerTokens }

    /// Enforced by the dispatcher before the command runs.
    func isAllowed(context: BotCommandContext) -> Bool {
        definition.permission.allows(context)
    }

    // MARK: - AsyncBotCommand

    func execute(message: String, context: BotCommandContext, reply: @escaping (String) -> Void) {
        let template = definition.response
        let sender = context.username
        let args = CustomCommandRenderer.arguments(from: message)
        let variables = self.variables
        Task {
            let vars = await variables()
            let text = CustomCommandRenderer.render(
                template: template,
                sender: sender,
                args: args,
                vars: vars
            )
            guard !text.isEmpty else { return }
            reply(text)
        }
    }
}
