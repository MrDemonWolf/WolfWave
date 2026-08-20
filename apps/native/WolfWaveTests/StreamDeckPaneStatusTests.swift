//
//  StreamDeckPaneStatusTests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-19.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import SwiftUI
import Testing

@testable import WolfWave

/// Pins the Stream Deck header chip's precedence rule.
///
/// The pane has two switches and the chip has one slot, so the ordering is the
/// whole behavior: the shared server outranks the command toggle, because
/// commands on top of a stopped server produce a key that silently does nothing.
/// Touches no process-wide state, so it needs no shared-state isolation.
@Suite("Stream Deck Pane Status")
struct StreamDeckPaneStatusTests {

    @Test("Server off outranks the command switch")
    func serverOffWinsOverCommandsOn() {
        let status = StreamDeckPaneStatus.resolve(controlEnabled: true, serverEnabled: false)

        #expect(status.text == "Server off")
        #expect(status.color == DSColor.neutral)
        #expect(status.symbol == StatusChip.StateGlyph.off)
    }

    @Test("Server off reports the server, not the commands, when both are off")
    func serverOffWinsOverCommandsOff() {
        let status = StreamDeckPaneStatus.resolve(controlEnabled: false, serverEnabled: false)

        #expect(status.text == "Server off")
        #expect(status.color == DSColor.neutral)
    }

    @Test("Commands off is reported only once the server is up")
    func commandsOff() {
        let status = StreamDeckPaneStatus.resolve(controlEnabled: false, serverEnabled: true)

        #expect(status.text == "Commands off")
        #expect(status.color == DSColor.warning)
        #expect(status.symbol == StatusChip.StateGlyph.starting)
    }

    @Test("Both on reads Ready")
    func ready() {
        let status = StreamDeckPaneStatus.resolve(controlEnabled: true, serverEnabled: true)

        #expect(status.text == "Ready")
        #expect(status.color == DSColor.success)
        #expect(status.symbol == StatusChip.StateGlyph.on)
    }

    @Test("Every state carries a distinct glyph so the chip reads without color")
    func glyphsAreDistinct() {
        let symbols = [
            StreamDeckPaneStatus.resolve(controlEnabled: true, serverEnabled: false).symbol,
            StreamDeckPaneStatus.resolve(controlEnabled: false, serverEnabled: true).symbol,
            StreamDeckPaneStatus.resolve(controlEnabled: true, serverEnabled: true).symbol
        ]

        #expect(Set(symbols).count == symbols.count)
    }
}
