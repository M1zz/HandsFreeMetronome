import XCTest

/// End-to-end on the simulator. Every run uses Voice Control mode
/// (`-usesVoiceControl YES`) so the app's own microphone stays off — no
/// permission alerts, no speech recognizer — and hides TipKit popovers, which
/// would otherwise sit on top of the controls being tapped.
final class HandsFreeMetronomeUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-usesVoiceControl", "YES", "-uitest-notips"] + extra
        app.launch()
        return app
    }

    /// A newcomer: introduction → start and stop the click → the help overlay
    /// → the full command list → back.
    func testIntroductionThenCoreFlow() {
        let app = launch(["-uitest-onboarding"])

        XCTAssertTrue(app.staticTexts["A metronome you talk to"].waitForExistence(timeout: 10))
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Commands are English words"].waitForExistence(timeout: 5))
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Made for Voice Control"].waitForExistence(timeout: 5))
        app.buttons["Get started"].tap()

        let start = app.buttons["Start metronome"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        let stop = app.buttons["Stop metronome"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))

        app.buttons["Help"].tap()
        let allCommands = app.buttons["All commands"]
        XCTAssertTrue(allCommands.waitForExistence(timeout: 5))
        allCommands.tap()
        XCTAssertTrue(app.navigationBars["Voice Commands"].waitForExistence(timeout: 5))
        app.navigationBars["Voice Commands"].buttons["Done"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
    }

    /// The introduction can be skipped from the first page.
    func testIntroductionCanBeSkipped() {
        let app = launch(["-uitest-onboarding"])
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 10))
        app.buttons["Skip"].tap()
        XCTAssertTrue(app.buttons["Start metronome"].waitForExistence(timeout: 5))
    }

    /// Apple's accessibility audit on the main screen (contrast, labels, hit
    /// targets, Dynamic Type clipping…).
    func testMainScreenPassesAccessibilityAudit() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["Start metronome"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit { issue in
            // The main screen deliberately caps text at .accessibility2
            // (ContentView `.dynamicTypeSize(...)`) so the performance view —
            // beat, tempo and Start on one screen on a music stand — holds
            // together. The audit probes beyond that cap and reports text that
            // stops growing there; everything up to the cap scales and wraps.
            // Every other check (contrast, labels, hit areas, traits…) applies.
            if issue.auditType == .dynamicType { return true }
            // Name the offender in the log so a failure says where to look.
            print("AUDIT: \(issue.compactDescription) — \(issue.element?.debugDescription ?? "no element")")
            return false
        }
    }
}
