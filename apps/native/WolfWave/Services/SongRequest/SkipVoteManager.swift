//
//  SkipVoteManager.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-22.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation

/// Coordinates chat vote-to-skip sessions.
///
/// Two modes, selected by the `voteSkipUsePolls` preference:
/// - **Chat tally** — each `!voteskip` is a vote. Unique voters are counted inside
///   a time window; once the minimum is reached the current song is skipped.
/// - **Twitch Polls** — a moderator's `!voteskip` opens a native Twitch poll and the
///   `channel.poll.end` result drives the skip.
///
/// State is polled (settings view) or observed via `.voteSkipStateChanged`, so this
/// type does not adopt `@Observable`. Implemented as an `actor` so mutation safety
/// is enforced by the compiler — replaces the prior `final class + NSLock`.
actor SkipVoteManager {

    // MARK: - Types

    /// The result of recording a `!voteskip`. Returned as a value (not a string) so
    /// the logic stays unit-testable; `VoteSkipCommand` formats the chat reply.
    enum VoteOutcome: Equatable, Sendable {
        /// The feature master toggle is off — the command should stay silent.
        case disabled
        /// Subscriber-only voting is on and the voter is not a subscriber.
        case subscriberOnly
        /// A previous session ended too recently. `remaining` is whole seconds left.
        case onCooldown(remaining: Int)
        /// This vote opened a new session.
        case started(count: Int, needed: Int)
        /// This vote was added to the running session.
        case counted(count: Int, needed: Int)
        /// The voter had already voted in this session.
        case alreadyVoted(count: Int, needed: Int)
        /// The vote reached the threshold — the song is being skipped.
        case passed(count: Int)
        /// Polls mode: a Twitch poll was created.
        case pollStarted
        /// Polls mode: a Twitch poll is already running.
        case pollInProgress
        /// Polls mode: a non-moderator tried to start a poll.
        case pollNotAllowed
    }

    // MARK: - Wiring

    /// Skips the current song. Wired by `AppDelegate` to `SongRequestService.voteSkip()`.
    private var performSkip: (@Sendable () async -> Void)?

    /// Sends a message to Twitch chat (for window-expiry and poll-result notices,
    /// which have no triggering message to reply to). Wired by `AppDelegate`.
    private var sendChatMessage: (@Sendable (String) -> Void)?

    /// Creates a Twitch poll. Returns `true` on success. Wired by `AppDelegate` to
    /// `TwitchChatService.createSkipPoll(...)`. Unset until Polls mode is used.
    private var createPoll: (@Sendable (_ title: String, _ durationSeconds: Int) async -> Bool)?

    /// Installs the closures used to skip, send chat messages, and create polls.
    /// Called once at startup from `AppDelegate.setupSkipVoteManager()` so the
    /// actor's mutable closure properties are only assigned from inside the actor.
    func configure(
        performSkip: (@Sendable () async -> Void)?,
        sendChatMessage: (@Sendable (String) -> Void)?,
        createPoll: (@Sendable (_ title: String, _ durationSeconds: Int) async -> Bool)?
    ) {
        self.performSkip = performSkip
        self.sendChatMessage = sendChatMessage
        self.createPoll = createPoll
    }

    // MARK: - State

    private var voters: Set<String> = []
    private var sessionStart: Date?
    private var windowTask: Task<Void, Never>?
    private var lastSessionEnd: Date?
    private var pollActive = false

    // MARK: - Configuration

    private nonisolated var defaults: Foundation.UserDefaults { .standard }

    /// Whether the vote-skip feature is enabled.
    nonisolated var isEnabled: Bool {
        defaults.bool(forKey: AppConstants.UserDefaults.voteSkipEnabled)
    }

    /// Minimum unique voters required to skip. Clamped to at least 1.
    nonisolated var minVotes: Int {
        let stored = defaults.integer(forKey: AppConstants.UserDefaults.voteSkipMinVotes)
        return stored > 0 ? stored : 3
    }

    /// How long a chat-tally session stays open, in seconds.
    nonisolated var windowSeconds: Int {
        let stored = defaults.integer(forKey: AppConstants.UserDefaults.voteSkipWindowSeconds)
        return stored > 0 ? stored : 60
    }

    /// Cooldown between sessions, in seconds. May legitimately be `0`.
    nonisolated var sessionCooldown: TimeInterval {
        (defaults.object(forKey: AppConstants.UserDefaults.voteSkipSessionCooldown) as? TimeInterval) ?? 30
    }

    /// Whether only subscribers may vote.
    nonisolated var isSubscriberOnly: Bool {
        defaults.bool(forKey: AppConstants.UserDefaults.voteSkipSubscriberOnly)
    }

    /// Whether vote-skip uses native Twitch Polls instead of a chat tally.
    nonisolated var usePolls: Bool {
        defaults.bool(forKey: AppConstants.UserDefaults.voteSkipUsePolls)
    }

    /// Twitch poll duration in seconds. Clamped to Twitch's 15–1800 range.
    nonisolated var pollDuration: Int {
        let stored = defaults.integer(forKey: AppConstants.UserDefaults.voteSkipPollDuration)
        let value = stored > 0 ? stored : 60
        return min(max(value, 15), 1800)
    }

    // MARK: - Public API

    /// Records a `!voteskip` from `context` and returns the outcome.
    func recordVote(context: BotCommandContext) async -> VoteOutcome {
        guard isEnabled else { return .disabled }
        if usePolls {
            return await handlePollVote(context: context)
        }
        return await recordChatVote(context: context)
    }

    /// Reports the active session's progress, or `nil` when no session is running.
    /// Used by the settings view and an optional menu-bar indicator.
    func currentVoteState() -> (count: Int, needed: Int)? {
        guard sessionStart != nil else { return nil }
        return (voters.count, minVotes)
    }

    /// Handles a finished Twitch poll (from the `channel.poll.end` EventSub event).
    ///
    /// - Parameters:
    ///   - skipVotes: Vote count for the "Skip" choice.
    ///   - keepVotes: Vote count for the "Keep playing" choice.
    func handlePollEnded(skipVotes: Int, keepVotes: Int) async {
        pollActive = false
        let needed = minVotes
        if skipVotes > keepVotes && skipVotes >= needed {
            sendChatMessage?("✅ The vote passed — skipping! (\(skipVotes) skip / \(keepVotes) keep)")
            await performSkip?()
        } else {
            sendChatMessage?("📊 Vote over — the song stays. (\(skipVotes) skip / \(keepVotes) keep)")
        }
    }

    /// Clears all session state (e.g. on Twitch disconnect).
    func reset() {
        windowTask?.cancel()
        windowTask = nil
        voters.removeAll()
        sessionStart = nil
        lastSessionEnd = nil
        pollActive = false
    }

    // MARK: - Chat-tally Voting

    private func recordChatVote(context: BotCommandContext) async -> VoteOutcome {
        if isSubscriberOnly && !context.isSubscriber && !context.isPrivileged {
            return .subscriberOnly
        }

        let needed = minVotes

        enum Decision {
            case outcome(VoteOutcome)
            case pass(count: Int)
        }

        let decision: Decision = {
            let now = Date()

            // No session running — open one (subject to the inter-session cooldown).
            guard sessionStart != nil else {
                if let last = lastSessionEnd {
                    let elapsed = now.timeIntervalSince(last)
                    if elapsed < sessionCooldown {
                        return .outcome(.onCooldown(remaining: Int(ceil(sessionCooldown - elapsed))))
                    }
                }
                voters = [context.userID]
                sessionStart = now
                if voters.count >= needed {
                    let count = voters.count
                    finishSession()
                    return .pass(count: count)
                }
                startWindowTask()
                return .outcome(.started(count: voters.count, needed: needed))
            }

            // Session running — add the voter unless they already voted.
            if voters.contains(context.userID) {
                return .outcome(.alreadyVoted(count: voters.count, needed: needed))
            }
            voters.insert(context.userID)
            if voters.count >= needed {
                let count = voters.count
                finishSession()
                return .pass(count: count)
            }
            return .outcome(.counted(count: voters.count, needed: needed))
        }()

        switch decision {
        case .outcome(let outcome):
            switch outcome {
            case .started, .counted:
                postState()
            default:
                break
            }
            return outcome
        case .pass(let count):
            postState()
            await performSkip?()
            return .passed(count: count)
        }
    }

    // MARK: - Polls Voting

    private func handlePollVote(context: BotCommandContext) async -> VoteOutcome {
        guard context.isPrivileged else { return .pollNotAllowed }

        if pollActive { return .pollInProgress }
        pollActive = true

        let success = await createPoll?("Skip the current song?", pollDuration) ?? false
        if success {
            return .pollStarted
        }

        // Poll creation failed (commonly: the channel is not a Twitch Affiliate).
        // Fall back to a chat tally so the vote still works.
        pollActive = false
        sendChatMessage?("📊 Twitch polls need Affiliate status — counting chat votes instead.")
        return await recordChatVote(context: context)
    }

    // MARK: - Session Helpers

    /// Tears down the active session and starts the inter-session cooldown.
    private func finishSession() {
        windowTask?.cancel()
        windowTask = nil
        voters.removeAll()
        sessionStart = nil
        lastSessionEnd = Date()
    }

    /// Spawns the window timer that fails the session if the threshold is never met.
    private func startWindowTask() {
        let seconds = windowSeconds
        windowTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.windowExpired()
        }
    }

    /// Called when a session's window elapses without reaching the threshold.
    private func windowExpired() {
        guard sessionStart != nil else { return }
        let count = voters.count
        voters.removeAll()
        sessionStart = nil
        windowTask = nil
        lastSessionEnd = Date()
        postState()
        sendChatMessage?("⏳ Vote-skip failed — only \(count) of \(minVotes) needed. The song stays!")
    }

    /// Posts `.voteSkipStateChanged` with the current session progress (if any).
    private func postState() {
        let state: (count: Int, needed: Int)? = sessionStart != nil
            ? (voters.count, minVotes)
            : nil
        var info: [String: Any] = [:]
        if let state {
            info["count"] = state.count
            info["needed"] = state.needed
        }
        let infoCopy = info
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .voteSkipStateChanged,
                object: nil,
                userInfo: infoCopy.isEmpty ? nil : infoCopy
            )
        }
    }
}
