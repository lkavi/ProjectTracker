import XCTest

/// macOS counterpart of DemoRecordingUITests: a slow walkthrough whose screen
/// recording is exported for App Review. Runs only with DEMO_RECORDING=1
/// (pass TEST_RUNNER_DEMO_RECORDING=1 to xcodebuild). Ends with a deliberate
/// failure so the recording is kept in the result bundle.
final class DemoRecordingMacUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        #if os(iOS)
        throw XCTSkip("macOS only")
        #else
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DEMO_RECORDING"] == "1",
                          "Demo recording only; set TEST_RUNNER_DEMO_RECORDING=1 to run it.")
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-reset", "-NSRequiresAquaSystemAppearance", "YES"]
        #endif
    }

    private func pause(_ seconds: TimeInterval = 1.2) { Thread.sleep(forTimeInterval: seconds) }

    private func element(labeled label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR title == %@", label, label)).firstMatch
    }

    private func byID(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @discardableResult
    private func clickIfPresent(_ element: XCUIElement, timeout: TimeInterval = 4, then wait: TimeInterval = 1.2) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        element.click()
        pause(wait)
        return true
    }

    func testDemoWalkthrough() throws {
        #if os(macOS)
        app.launch()
        pause(2.5)

        // 1. New project from a template
        clickIfPresent(byID("new-project-button"))
        let name = app.textFields["project-name-field"]
        if name.waitForExistence(timeout: 5) {
            name.click(); pause(0.4)
            name.typeText("MSc Dissertation"); pause()
        }
        clickIfPresent(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Master's dissertation")).firstMatch, timeout: 3)
        clickIfPresent(byID("create-project-button"), then: 2)

        // 2. Guide: copy the AI prompt, then continue by hand
        clickIfPresent(byID("copy-prompt-button"), timeout: 8, then: 2)
        clickIfPresent(byID("guide-not-now-button"), then: 2)

        // 3. Tick two tasks in Next up
        clickIfPresent(app.checkBoxes["Agree the research question with your supervisor"].firstMatch, then: 1)
        clickIfPresent(app.checkBoxes["Write the proposal and timeline"].firstMatch, then: 1.5)

        // 4. Leave a note on the first stage
        let notes = app.textViews.firstMatch
        if notes.waitForExistence(timeout: 4) {
            notes.click(); pause(0.4)
            notes.typeText("Supervisor meeting booked for Thursday. Bring the draft timeline."); pause(1.5)
        }

        // 5. Library: add a reference
        clickIfPresent(element(labeled: "Library"), then: 1.5)
        if !clickIfPresent(app.buttons["Add First Reference"], timeout: 3, then: 1) {
            clickIfPresent(byID("add-reference-menu-button"), timeout: 3, then: 1)
        }
        let title = app.textFields["reference-title-field"]
        if title.waitForExistence(timeout: 5) {
            title.click(); pause(0.4)
            title.typeText("Long Short-Term Memory (Hochreiter & Schmidhuber, 1997)"); pause(0.8)
        }
        clickIfPresent(byID("add-reference-button"), then: 2)
        clickIfPresent(element(labeled: "Stages"), then: 1.5)

        // 6. Settings: target buffer and a reminder
        clickIfPresent(byID("settings-button"), then: 1.5)
        if clickIfPresent(app.popUpButtons.firstMatch, timeout: 3, then: 1) {
            clickIfPresent(app.menuItems["1 week early"], timeout: 3, then: 1.2)
        }
        let toggle = app.switches.firstMatch.exists ? app.switches.firstMatch : app.checkBoxes.firstMatch
        clickIfPresent(toggle, timeout: 3, then: 1.5)
        clickIfPresent(app.buttons["Done"].firstMatch, then: 1.5)

        // 7. Paste a deadline list and review the draft stages
        clickIfPresent(byID("project-menu"), then: 1)
        clickIfPresent(app.menuItems["Paste Deadline List…"], then: 1.5)
        let list = app.textViews["deadline-list-field"]
        if list.waitForExistence(timeout: 5) {
            list.click(); pause(0.4)
            list.typeText("Literature review – 17 October 2026 – 15%\nMethodology – 21 November 2026\n- Choose methods\n- Ethics form\nFinal report – 15 April 2027 – 70%")
            pause(2)
        }
        clickIfPresent(byID("review-stages-button"), then: 2.5)
        clickIfPresent(byID("save-stages-button"), then: 2.5)

        // 8. Import preview from the clipboard (the prompt copied in step 2)
        clickIfPresent(byID("project-menu"), then: 1)
        clickIfPresent(app.menuItems["Import from Clipboard"], then: 2.5)
        clickIfPresent(app.buttons["Cancel"].firstMatch, timeout: 6, then: 2)

        pause(2)
        XCTFail("Deliberate: keeps the screen recording attachment for export.")
        #endif
    }
}
