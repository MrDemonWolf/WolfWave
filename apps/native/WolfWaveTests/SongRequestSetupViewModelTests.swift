//
//  SongRequestSetupViewModelTests.swift
//  WolfWaveTests
//
//  Created by Nathanial Henniges on 2026-06-08.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Foundation
import Testing
@testable import WolfWave

/// Covers step navigation, the per-step "can I advance" gate, and that finishing
/// setup records the gate flag, clears the health status, and enables the feature.
@MainActor
@Suite("SongRequestSetupViewModel")
struct SongRequestSetupViewModelTests {

    @Test("opens at the requested step")
    func startAt() {
        #expect(SongRequestSetupViewModel().currentStep == .intro)
        #expect(SongRequestSetupViewModel(startAt: .shareLink).currentStep == .shareLink)
    }

    @Test("navigation clamps at both ends")
    func navClamps() {
        let viewModel = SongRequestSetupViewModel(startAt: .intro)
        viewModel.goToPreviousStep()
        #expect(viewModel.currentStep == .intro)
        #expect(viewModel.isFirstStep)

        for _ in 0..<10 { viewModel.goToNextStep() }
        #expect(viewModel.currentStep == .done)
        #expect(viewModel.isLastStep)
    }

    @Test("intro waits on a Twitch connection")
    func introGate() {
        let viewModel = SongRequestSetupViewModel(startAt: .intro)
        viewModel.isTwitchConnected = false
        #expect(viewModel.canAdvance == false)
        viewModel.isTwitchConnected = true
        #expect(viewModel.canAdvance)
    }

    @Test("apple music step waits on authorization")
    func musicGate() {
        let viewModel = SongRequestSetupViewModel(startAt: .appleMusic)
        #expect(viewModel.canAdvance == false)
        viewModel.musicAuthorized = true
        #expect(viewModel.canAdvance)
    }

    @Test("playlist step waits on the playlist being ready")
    func playlistGate() {
        let viewModel = SongRequestSetupViewModel(startAt: .playlist)
        #expect(viewModel.canAdvance == false)
        viewModel.playlistReady = true
        #expect(viewModel.canAdvance)
    }

    @Test("the optional share step never blocks")
    func shareNeverBlocks() {
        #expect(SongRequestSetupViewModel(startAt: .shareLink).canAdvance)
    }

    @Test("complete records the gate, ok status, and enables the feature")
    func completeWrites() throws {
        let name = "test.sr.setup.complete"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        SongRequestSetupViewModel().complete(defaults: defaults)

        #expect(defaults.bool(forKey: AppConstants.UserDefaults.songRequestSetupComplete))
        #expect(defaults.bool(forKey: AppConstants.UserDefaults.songRequestEnabled))
        #expect(
            defaults.string(forKey: AppConstants.UserDefaults.songRequestPlaylistStatus)
                == PlaylistSetupStatus.ok.rawValue)
    }
}
