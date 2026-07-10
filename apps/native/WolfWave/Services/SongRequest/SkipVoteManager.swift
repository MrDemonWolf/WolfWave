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
/// - **Chat tally**: each `!voteskip` is a vote. Unique voters are counted inside
///   a time window; once the minimum is reached the current song is skipped.
/// - **Twitch Polls**: a moderator's `!voteskip` opens a native Twitch poll and the
///   `channel.poll.end` result drives the skip.
///
/// State is polled (settings view) or observed via `.voteSkipStateChanged`, so this
/// type does not adopt `@Observable`. Implemented as an `actor` so mutation safety
/// is enforced by the compiler. Replaces the prior `final class + NSLock`.
actor SkipVoteManager {

    // MARK: - Types

    /// The result of recording a `!voteskip`. Returned as a value (not a string) so
    /// the logic stays unit-testable; `VoteSkipCommand` formats the chat reply.
    enum VoteOutcome: Equatable, Sendable {
        /// The feature master toggle is off, the command should stay silent.
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
        /// The vote reached the threshold, the song is being skipped.
        case passed(count: Int)
        /// Polls mode: a Twitch poll was created.
        case pollStarted
        /// Polls mode: a Twitch poll is already running.
        case pollInProgress
        /// Polls mode: a non-moderator tried to start a poll.
        case pollNotAllowed
    }

    /// A lifecycle signal emitted to the optional `onVoteEvent` hook so a consumer
    /// (e.g. `AppDelegate`) can post a macOS notification. The manager stays "dumb":
    /// it knows nothing about notifications or user preferences. It only reports
    /// that the event happened.
    enum VoteEvent: Sendable {
        /// A chat-tally session just opened. `needed` is the vote threshold.
        case started(needed: Int)
        /// A native Twitch poll just opened.
        case pollStarted
        /// A vote (chat tally or poll) reached the threshold, song is being skipped.
        case passed
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

    /// Lifecycle hook for vote events (start / poll-start / pass). Wired by
    /// `AppDelegate` to post macOS notifications. The manager does no gating here.
    private var onVoteEvent: (@Sendable (VoteEvent) -> Void)?

    /// Installs the closures used to skip, send chat messages, create polls, and
    /// report vote events. Called once at startup from
    /// `AppDelegate.setupSkipVoteManager()` so the actor's mutable closure
    /// properties are only assigned from inside the actor.
    func configure(
        performSkip: (@Sendable () async -> Void)?,
        sendChatMessage: (@Sendable (String) -> Void)?,
        createPoll: (@Sendable (_ title: String, _ durationSeconds: Int) async -> Bool)?,
        onVoteEvent: (@Sendable (VoteEvent) -> Void)? = nil
    ) {
        self.performSkip = performSkip
        self.sendChatMessage = sendChatMessage
        self.createPoll = createPoll
        self.onVoteEvent = onVoteEvent
    }

    // MARK: - Init

    /// Optional override for the chat-tally window duration. When set, it takes
    /// precedence over the `voteSkipWindowSeconds` preference. Tests inject a
    /// sub-100ms window so window-expiry assertions don't wait whole seconds.
    private let windowOverride: Duration?

    /// Optional override for the poll-end fallback timeout. When set, it takes
    /// precedence over `pollDuration` plus the grace period. Tests inject a
    /// sub-100ms timeout so missed-poll-end assertions don't wait whole minutes.
    private let pollTimeoutOverride: Duration?

    /// Creates a skip-vote manager.
    ///
    /// - Parameters:
    ///   - windowDuration: Overrides the chat-tally window length read from
    ///     preferences. Defaults to `nil` (use the preference).
    ///   - pollTimeoutDuration: Overrides the poll-end fallback timeout
    ///     (normally the poll duration plus a grace period). Defaults to `nil`.
    init(windowDuration: Duration? = nil, pollTimeoutDuration: Duration? = nil) {
        self.windowOverride = windowDuration
        self.pollTimeoutOverride = pollTimeoutDuration
    }

    // MARK: - State

    private var voters: Set<String> = []
    private var sessionStart: Date?
    private var windowTask: Task<Void, Never>?
    private var lastSessionEnd: Date?
    private var pollActive = false
    private var pollTimeoutTask: Task<Void, Never>?

    /// Monotonic id bumped each time a new chat-tally session opens. The window
    /// timer captures the id at spawn time and checks it before expiring, so a
    /// stale timer (whose sleep ran past a fast pass + immediate re-open with a
    /// zero cooldown) can't clear the session that replaced it.
    private var sessionGeneration = 0

    /// Monotonic id bumped each time a new Twitch poll opens. The poll-end
    /// fallback timer captures the id at spawn time and checks it before firing,
    /// so a stale timer can't clear the poll that replaced it. Mirrors
    /// `sessionGeneration` for the chat-tally window timer.
    private var pollGeneration = 0

    /// Extra seconds granted past `pollDuration` before the poll-end fallback
    /// timer assumes the `channel.poll.end` event was missed.
    private static let pollEndGraceSeconds = 15

    // MARK: - Configuration

    private nonisolated var defaults: Foundation.UserDefaults { .standard }

    /// Whether the vote-skip feature is enabled.
    nonisolated var isEnabled: Bool {
        defaults.bool(forKey: AppConstants.UserDefaults.voteSkipEnabled)
    }

    /// Minimum unique voters required to skip. Clamped to at least 1.
    nonisolated var minVotes: Int {
        Preferences.int(AppConstants.UserDefaults.voteSkipMinVotes, default: 3)
    }

    /// How long a chat-tally session stays open, in seconds.
    nonisolated var windowSeconds: Int {
        Preferences.int(AppConstants.UserDefaults.voteSkipWindowSeconds, default: 60)
    }

    /// Cooldown between sessions, in seconds. May legitimately be `0`.
    nonisolated var sessionCooldown: TimeInterval {
        Preferences.double(AppConstants.UserDefaults.voteSkipSessionCooldown, default: 30)
    }

    /// Whether only subscribers may vote.
    nonisolated var isSubscriberOnly: Bool {
        defaults.bool(forKey: AppConstants.UserDefaults.voteSkipSubscriberOnly)
    }

    /// Whether vote-skip uses native Twitch Polls instead of a chat tally.
    nonisolated var usePolls: Bool {
        defaults.bool(forKey: AppConstants.UserDefaults.voteSkipUsePolls)
    }

    /// Twitch poll duration in seconds. Clamped to Twitch's 15-1800 range.
    nonisolated var pollDuration: Int {
        let value = Preferences.int(AppConstants.UserDefaults.voteSkipPollDuration, default: 60)
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

    /// Reports whether a vote-skip Twitch poll is in flight (created, but its
    /// `channel.poll.end` result not yet received or timed out).
    func isPollInProgress() -> Bool {
        pollActive
    }

    /// Handles a finished Twitch poll (from the `channel.poll.end` EventSub event).
    ///
    /// - Parameters:
    ///   - skipVotes: Vote count for the "Skip" choice.
    ///   - keepVotes: Vote count for the "Keep playing" choice.
    func handlePollEnded(skipVotes: Int, keepVotes: Int) async {
        pollTimeoutTask?.cancel()
        pollTimeoutTask = nil
        pollActive = false
        let needed = minVotes
        if skipVotes > keepVotes && skipVotes >= needed {
            sendChatMessage?("✅ The vote passed, skipping! (\(skipVotes) skip / \(keepVotes) keep)")
            await performSkip?()
            onVoteEvent?(.passed)
        } else {
            sendChatMessage?("📊 Vote over, the song stays. (\(skipVotes) skip / \(keepVotes) keep)")
        }
    }

    /// Ends any open chat-tally session because the current song changed.
    ///
    /// Votes cast against the outgoing song must not carry over to the new
    /// one, so the session is discarded. Unlike window expiry, the
    /// inter-session cooldown does NOT start: the vote never ran its course,
    /// so chat can open a fresh vote on the new song right away. A stale
    /// window timer is defused the same way `windowExpired` handles it
    /// (cancelled here, and its `sessionStart != nil` / generation guards
    /// no-op it if the sleep already ran). Twitch polls are left alone: a
    /// native poll runs on Twitch's side and still resolves via
    /// `channel.poll.end` or the timeout fallback.
    func trackDidChange() {
        guard sessionStart != nil else { return }
        windowTask?.cancel()
        windowTask = nil
        voters.removeAll()
        sessionStart = nil
        postState()
        Log.debug(
            "SkipVoteManager: track changed, chat-tally vote session cleared",
            category: "SongRequest"
        )
    }

    /// Clears all session state (e.g. on Twitch disconnect).
    func reset() {
        windowTask?.cancel()
        windowTask = nil
        pollTimeoutTask?.cancel()
        pollTimeoutTask = nil
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

            // No session running, open one (subject to the inter-session cooldown).
            guard sessionStart != nil else {
                if let last = lastSessionEnd {
                    let elapsed = now.timeIntervalSince(last)
                    if elapsed < sessionCooldown {
                        return .outcome(.onCooldown(remaining: Int(ceil(sessionCooldown - elapsed))))
                    }
                }
                voters = [context.userID]
                sessionStart = now
                sessionGeneration += 1
                if voters.count >= needed {
                    let count = voters.count
                    finishSession()
                    return .pass(count: count)
                }
                startWindowTask()
                return .outcome(.started(count: voters.count, needed: needed))
            }

            // Session running, add the voter unless they already voted.
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
            case .started(_, let needed):
                postState()
                onVoteEvent?(.started(needed: needed))
            case .counted:
                postState()
            default:
                break
            }
            return outcome
        case .pass(let count):
            postState()
            await performSkip?()
            onVoteEvent?(.passed)
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
            pollGeneration += 1
            startPollTimeoutTask()
            onVoteEvent?(.pollStarted)
            return .pollStarted
        }

        // Poll creation failed (commonly: the channel is not a Twitch Affiliate).
        // Fall back to a chat tally so the vote still works.
        pollActive = false
        sendChatMessage?("📊 Twitch polls need Affiliate status, counting chat votes instead.")
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
        // Tests inject a sub-second `windowOverride`; production falls back to the
        // `voteSkipWindowSeconds` preference.
        let duration = windowOverride ?? .seconds(windowSeconds)
        let generation = sessionGeneration
        windowTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            await self?.windowExpired(generation: generation)
        }
    }

    /// Called when a session's window elapses without reaching the threshold.
    /// Ignores the call if a different session has since opened (`generation`
    /// mismatch). A fast pass + zero-cooldown re-open can outrun this timer.
    private func windowExpired(generation: Int) {
        guard sessionStart != nil, generation == sessionGeneration else { return }
        let count = voters.count
        voters.removeAll()
        sessionStart = nil
        windowTask = nil
        lastSessionEnd = Date()
        postState()
        sendChatMessage?("⏳ Vote-skip failed, only \(count) of \(minVotes) needed. The song stays!")
    }

    /// Spawns the fallback timer that clears a latched poll when the
    /// `channel.poll.end` event never arrives. EventSub does not replay events
    /// missed during a disconnect, so without this a WebSocket drop mid-poll
    /// would leave `pollActive` stuck at `true` and vote-skip permanently
    /// replying "poll in progress". Waits the poll duration plus a grace period;
    /// `handlePollEnded` and `reset()` cancel it on the happy paths.
    private func startPollTimeoutTask() {
        // Tests inject a sub-second `pollTimeoutOverride`; production waits out
        // the Twitch poll plus a grace period for the poll.end event to land.
        let duration = pollTimeoutOverride ?? .seconds(pollDuration + Self.pollEndGraceSeconds)
        let generation = pollGeneration
        pollTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            await self?.pollTimedOut(generation: generation)
        }
    }

    /// Called when the poll-end fallback timer fires. A no-op unless the same
    /// poll generation is still marked active (`handlePollEnded` never ran).
    private func pollTimedOut(generation: Int) {
        guard pollActive, generation == pollGeneration else { return }
        pollActive = false
        pollTimeoutTask = nil
        Log.warn(
            "SkipVoteManager: Twitch poll result never arrived; clearing stuck poll state",
            category: "SongRequest"
        )
    }

    /// Posts `.voteSkipStateChanged` with the current session progress (if any).
    private func postState() {
        let state: (count: Int, needed: Int)? = sessionStart != nil
            ? (voters.count, minVotes)
            : nil
        Task { @MainActor in
            NotificationCenter.default.postVoteSkipState(state)
        }
    }
}
