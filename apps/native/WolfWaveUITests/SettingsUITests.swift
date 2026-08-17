//
//  SettingsUITests.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-08-17.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import XCTest

/// Opens Settings and visits every pane.
///
/// This is the cheapest possible guard against the failure mode this app has
/// actually shipped: a pane that traps inside SwiftUI on render, taking the
/// whole settings window down. A persisted value outside a picker's tag set did
/// exactly that to Song Requests, and no unit test can see it because the crash
/// happens in SwiftUI's layout, not in our code. Rendering each pane for real is
/// the assertion.
@MainActor
final class SettingsUITests: WolfWaveUITestCase {

    /// Start past the wizard: this suite's subject is the settings window.
    override var launchOptions: LaunchOptions {
        LaunchOptions(onboarded: true, suppressWhatsNew: true)
    }

    /// Sidebar section titles, in sidebar order. Mirrors
    /// `SettingsView.SettingsSection`'s raw values. `Debug` is deliberately
    /// absent: it is compiled into Debug builds only, and asserting it here
    /// would make the suite configuration-dependent.
    private static let sections = [
        "General",
        "Song Requests",
        "Stream Widgets",
        "History & Stats",
        "Twitch",
        "Discord",
        "Software Update",
        "Advanced",
        "About"
    ]

    private static let settingsWindowTitle = UITestWindow.settings

    /// Opens Settings the way a user does, through the App menu's Cmd+,.
    ///
    /// The app is Dock-visible by default, which is what puts a main menu on
    /// screen for the shortcut to reach. A suite that first set the app
    /// menu-only would have to open Settings through the status item instead.
    @discardableResult
    private func openSettings() -> XCUIElement {
        app.activate()
        app.typeKey(",", modifierFlags: .command)
        let window = app.windows[Self.settingsWindowTitle]
        expect(window, "the Settings window after Cmd+,")
        return window
    }

    func testSettingsWindowOpens() {
        let window = openSettings()
        XCTAssertTrue(window.exists)
        expect(
            app.staticTexts["settings.sidebar.General"],
            "the General row in the settings sidebar"
        )
    }

    func testEveryPaneRenders() {
        openSettings()

        for section in Self.sections {
            let row = app.staticTexts["settings.sidebar.\(section)"]
            expect(row, "the \(section) sidebar row")
            row.click()

            // The window surviving the click is the assertion. A pane that traps
            // during layout takes the process with it, so the next query fails
            // against a dead app rather than returning a wrong answer.
            XCTAssertTrue(
                app.windows[Self.settingsWindowTitle].exists,
                "The Settings window went away while rendering \(section)"
            )
            XCTAssertEqual(app.state, .runningForeground, "The app died rendering \(section)")
        }
    }

    /// Walks the panes twice. Several panes start observers or timers on appear,
    /// and a teardown that under-releases only shows up on the second visit.
    func testPanesSurviveRepeatedVisits() {
        openSettings()

        for _ in 0..<2 {
            for section in Self.sections {
                let row = app.staticTexts["settings.sidebar.\(section)"]
                expect(row, "the \(section) sidebar row")
                row.click()
            }
        }

        XCTAssertEqual(app.state, .runningForeground, "The app died revisiting the panes")
        XCTAssertTrue(app.windows[Self.settingsWindowTitle].exists)
    }
}
