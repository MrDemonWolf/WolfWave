//
//  SongRequestSetupHealthTests.swift
//  WolfWaveTests
//
//  Created by Nathanial Henniges on 2026-06-08.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import Testing
@testable import WolfWave

/// Covers the pure pieces of the "playlist nuked" detector: the probe classifier,
/// the fallback policy, and the one-time setup-gate migration. No network or
/// Keychain access, so it stays fast and deterministic.
@MainActor
@Suite("Song request setup health")
struct SongRequestSetupHealthTests {

    // MARK: - resolveHealth policy

    @Test("an unreachable API changes nothing")
    func unreachableNoOp() {
        // The key safety property: a network blip must never clear a real banner
        // or flip a toggle, so resolveHealth returns nil (no change).
        #expect(SongRequestService.resolveHealth(probe: .unreachable, storedShareURL: "https://x") == nil)
        #expect(SongRequestService.resolveHealth(probe: .unreachable, storedShareURL: "") == nil)
    }

    @Test("a missing playlist re-engages the setup gate")
    func missingReEngages() throws {
        let outcome = try #require(SongRequestService.resolveHealth(probe: .missing, storedShareURL: ""))
        #expect(outcome.status == .playlistMissing)
        #expect(outcome.reEngageGate)
        #expect(outcome.disableLink == false)
    }

    @Test("not-public with a stored link disables only !playlist")
    func notPublicWithLink() throws {
        let outcome = try #require(
            SongRequestService.resolveHealth(probe: .notPublic, storedShareURL: "https://music.apple.com/x"))
        #expect(outcome.status == .linkUnshared)
        #expect(outcome.disableLink)
        #expect(outcome.reEngageGate == false)
    }

    @Test("not-public without a link is healthy (private playlist is fine)")
    func notPublicNoLink() throws {
        let outcome = try #require(SongRequestService.resolveHealth(probe: .notPublic, storedShareURL: "   "))
        #expect(outcome.status == .ok)
        #expect(outcome.disableLink == false)
    }

    @Test("ok refreshes a changed share url")
    func okRefreshesURL() throws {
        let outcome = try #require(
            SongRequestService.resolveHealth(probe: .ok(shareURL: "https://new"), storedShareURL: "https://old"))
        #expect(outcome.status == .ok)
        #expect(outcome.updatedShareURL == "https://new")
    }

    @Test("ok with the same url writes nothing back")
    func okSameURL() throws {
        let outcome = try #require(
            SongRequestService.resolveHealth(probe: .ok(shareURL: "https://same"), storedShareURL: "https://same"))
        #expect(outcome.updatedShareURL == nil)
    }

    @Test("ok with no stored link does not adopt a url")
    func okNoStoredLink() throws {
        let outcome = try #require(
            SongRequestService.resolveHealth(probe: .ok(shareURL: "https://x"), storedShareURL: ""))
        #expect(outcome.status == .ok)
        #expect(outcome.updatedShareURL == nil)
    }

    // MARK: - classifyProbe

    @Test("classify: no playlist id is missing")
    func classifyMissing() {
        #expect(
            AppleMusicLibraryService.classifyProbe(foundPlaylistID: nil, shareURL: .resolved(nil))
                == .missing)
    }

    @Test("classify: an id with a definitive no-url answer is not public")
    func classifyNotPublic() {
        #expect(
            AppleMusicLibraryService.classifyProbe(foundPlaylistID: "p.1", shareURL: .resolved(nil))
                == .notPublic)
    }

    @Test("classify: an id with a url is ok")
    func classifyOK() {
        #expect(
            AppleMusicLibraryService.classifyProbe(foundPlaylistID: "p.1", shareURL: .resolved("https://x"))
                == .ok(shareURL: "https://x"))
    }

    @Test("classify: a failed share resolution is unreachable, never not-public")
    func classifyShareResolutionFailure() {
        // A timeout / 429 / 5xx during share-URL resolution must not read as
        // "the streamer un-shared the playlist".
        #expect(
            AppleMusicLibraryService.classifyProbe(foundPlaylistID: "p.1", shareURL: .failed)
                == .unreachable)
    }

    @Test("classify: a missing playlist wins over a failed share resolution")
    func classifyMissingWinsOverFailure() {
        #expect(
            AppleMusicLibraryService.classifyProbe(foundPlaylistID: nil, shareURL: .failed)
                == .missing)
    }

    @Test("classify: a transport error ends as no banner change end to end")
    func transportErrorNoBannerChange() {
        // Full chain: failed share resolution -> .unreachable -> resolveHealth
        // returns nil, so the stored link and the banner stay untouched.
        let probe = AppleMusicLibraryService.classifyProbe(foundPlaylistID: "p.1", shareURL: .failed)
        #expect(SongRequestService.resolveHealth(probe: probe, storedShareURL: "https://music.apple.com/x") == nil)
    }

    // MARK: - migrateSetupState

    @Test("migration grandfathers an already-enabled setup")
    func migrateEnabled() throws {
        let name = "test.sr.migrate.enabled"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: AppConstants.UserDefaults.songRequestEnabled)

        SongRequestService.migrateSetupState(defaults: defaults)

        #expect(defaults.bool(forKey: AppConstants.UserDefaults.songRequestSetupComplete))
    }

    @Test("migration grandfathers a configured song-list link")
    func migrateLink() throws {
        let name = "test.sr.migrate.link"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("https://music.apple.com/x", forKey: AppConstants.UserDefaults.songRequestSongListURL)

        SongRequestService.migrateSetupState(defaults: defaults)

        #expect(defaults.bool(forKey: AppConstants.UserDefaults.songRequestSetupComplete))
    }

    @Test("migration leaves a fresh install gated")
    func migrateFresh() throws {
        let name = "test.sr.migrate.fresh"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        SongRequestService.migrateSetupState(defaults: defaults)

        #expect(defaults.bool(forKey: AppConstants.UserDefaults.songRequestSetupComplete) == false)
    }

    @Test("migration is a no-op once the flag has been written")
    func migrateIdempotent() throws {
        let name = "test.sr.migrate.idem"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: AppConstants.UserDefaults.songRequestSetupComplete)
        defaults.set(true, forKey: AppConstants.UserDefaults.songRequestEnabled)

        SongRequestService.migrateSetupState(defaults: defaults)

        // An explicit prior write wins; migration must not flip it back on.
        #expect(defaults.bool(forKey: AppConstants.UserDefaults.songRequestSetupComplete) == false)
    }
}
