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
        "Stream Deck",
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
            select(section)

            // The window surviving the click is the assertion. A pane that traps
            // during layout takes the process with it, so the next query fails
            // against a dead app rather than returning a wrong answer.
            XCTAssertTrue(
                app.windows[Self.settingsWindowTitle].exists,
                "The Settings window went away while rendering \(section)"
            )
            assertStillRunning(rendering: section)
        }
    }

    /// Attaches a screenshot of every pane to the test result.
    ///
    /// Deliberately assertion-free. Layout is the half `testEveryPaneRenders`
    /// cannot see: a pane whose cards disagree on width renders perfectly
    /// happily and passes every assertion in this file, which is how the Stream
    /// Deck pane shipped with a narrow "Setting it up" card. Short of a snapshot
    /// suite this repo does not have, the fix for that class of bug is a person
    /// looking, so this test exists to leave something behind to look at, in CI
    /// and locally:
    ///
    ///     make test-ui
    ///     xcrun xcresulttool export attachments \
    ///       --path DerivedData/Tests/Logs/Test/<newest>.xcresult \
    ///       --output-path /tmp/panes
    ///
    /// The exported files are named by UUID; `manifest.json` beside them maps
    /// each one back to its pane.
    ///
    /// Writing the PNGs straight to a path instead would not work: the runner is
    /// sandboxed into its own container, so anywhere a reader would think to
    /// look is `Operation not permitted`. Attachments are the way out.
    func testCapturesEveryPane() {
        let window = openSettings()

        for section in Self.sections {
            select(section)
            let shot = XCTAttachment(screenshot: window.screenshot())
            shot.name = "Settings - \(section)"
            // Without this, XCTest deletes the attachment on a passing test,
            // and this test always passes.
            shot.lifetime = .keepAlways
            add(shot)
        }
    }

    /// Walks the panes twice. Several panes start observers or timers on appear,
    /// and a teardown that under-releases only shows up on the second visit.
    func testPanesSurviveRepeatedVisits() {
        openSettings()

        for _ in 0..<2 {
            for section in Self.sections {
                select(section)
            }
        }

        assertStillRunning(rendering: "the panes on a second pass")
        XCTAssertTrue(app.windows[Self.settingsWindowTitle].exists)
    }

    // MARK: - Helpers

    /// Clicks one sidebar row, activating first.
    ///
    /// The activation is not decoration. An inactive macOS app reports its whole
    /// window tree as disabled: the row is still *found*, so the query succeeds,
    /// and the click then fails with "Not hittable" or "Unable to find hit
    /// point". That reads as a layout bug and is not one, it just means
    /// something else took focus, which anything from a notification to a second
    /// copy of WolfWave Dev can do at any point in a multi-minute run.
    private func select(
        _ section: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        app.activate()
        let row = app.staticTexts["settings.sidebar.\(section)"]
        XCTAssertTrue(
            row.waitForExistence(timeout: Self.timeout),
            "Timed out waiting for the \(section) sidebar row",
            file: file,
            line: line
        )
        row.click()

        // The click is asynchronous. Waiting on the row proves only that the row
        // exists, so without this every caller races the pane it just asked for:
        // `testEveryPaneRenders` could assert against the outgoing pane, and
        // `testCapturesEveryPane` could screenshot it. The detail pane carries an
        // identifier naming whichever section is on screen, so waiting for the
        // one we asked for is the navigation-finished signal.
        //
        // Queried across every element type on purpose: SwiftUI decides what
        // kind of accessibility element the pane becomes, and it is not a
        // `group`, so `app.groups[...]` finds nothing and times out.
        let pane = app.descendants(matching: .any)["settings.pane.\(section)"]
        XCTAssertTrue(
            pane.waitForExistence(timeout: Self.timeout),
            "Timed out waiting for the \(section) pane to come on screen",
            file: file,
            line: line
        )
    }

    /// Asserts the app is still alive.
    ///
    /// Deliberately *not* `state == .runningForeground`. What these tests are
    /// checking is that rendering a pane did not take the process down, and
    /// losing focus is not that: any other app activating (a notification, a
    /// second copy of WolfWave Dev left over from Xcode) drops the app to
    /// `.runningBackground` and would fail a foreground assertion for a reason
    /// that has nothing to do with the pane.
    private func assertStillRunning(
        rendering section: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNotEqual(
            app.state, .notRunning,
            "The app died rendering \(section)",
            file: file,
            line: line
        )
    }
}
