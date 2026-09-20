import XCTest

/// Not part of the regular suite. Walks the app slowly on a physical device so
/// Xcode's automatic screen recording can be exported as the App Review video.
///
/// Run only when asked for:
///   TEST_RUNNER_DEMO_RECORDING=1 xcodebuild test … -only-testing:ProjectTrackerUITests/DemoRecordingUITests
///
/// The test ends with a deliberate failure so the recording is kept in the
/// result bundle regardless of the test plan's delete-on-success setting.
final class DemoRecordingUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DEMO_RECORDING"] == "1",
                          "Demo recording only; set TEST_RUNNER_DEMO_RECORDING=1 to run it.")
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-reset"]
    }

    private func pause(_ seconds: TimeInterval = 1.2) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func element(labeled label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Taps the element if it shows up; the demo keeps going otherwise.
    @discardableResult
    private func tapIfPresent(_ element: XCUIElement, timeout: TimeInterval = 4, then wait: TimeInterval = 1.2) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        element.tap()
        pause(wait)
        return true
    }

    private func dismissKeyboard() {
        let done = app.toolbars.buttons["Done"]
        if done.exists { done.tap(); pause(0.6); return }
        app.swipeDown()
        pause(0.6)
    }

    func testDemoWalkthrough() throws {
        app.launch()
        pause(2.5)

        // 1. Create a project from a template
        tapIfPresent(app.buttons["new-project-button"])
        let name = app.textFields["project-name-field"]
        if name.waitForExistence(timeout: 5) {
            name.tap(); pause(0.5)
            name.typeText("MSc Dissertation"); pause()
            dismissKeyboard()
        }
        tapIfPresent(element(labeled: "Master's dissertation"))
        tapIfPresent(app.buttons["create-project-button"], then: 2)

        // 2. The setup guide: copy the AI prompt, then continue by hand
        tapIfPresent(app.buttons["copy-prompt-button"], timeout: 8, then: 2)
        tapIfPresent(app.buttons["guide-not-now-button"], then: 2)

        // 3. Tick two tasks in "Next up"
        tapIfPresent(element(labeled: "Agree the research question with your supervisor"), then: 1)
        tapIfPresent(element(labeled: "Write the proposal and timeline"), then: 1.5)

        // 4. Look through the stages and leave a note on the first one
        app.swipeUp(); pause(1.5)
        let notes = app.textViews.firstMatch
        if notes.waitForExistence(timeout: 4) {
            notes.tap(); pause(0.5)
            notes.typeText("Supervisor meeting booked for Thursday. Bring the draft timeline."); pause(1.5)
            dismissKeyboard()
        }
        app.swipeDown(); pause(1.5)

        // 5. Library: add a reference
        let libraryTab = app.tabBars.buttons["Library"]
        tapIfPresent(libraryTab.exists ? libraryTab : element(labeled: "Library"), then: 1.5)
        tapIfPresent(app.buttons["Add First Reference"], then: 1)
        let title = app.textFields["reference-title-field"]
        if title.waitForExistence(timeout: 5) {
            title.tap(); pause(0.4)
            title.typeText("Long Short-Term Memory (Hochreiter & Schmidhuber, 1997)\n"); pause(0.8)
        }
        tapIfPresent(app.buttons["add-reference-button"], then: 2)
        let stagesTab = app.tabBars.buttons["Stages"]
        tapIfPresent(stagesTab.exists ? stagesTab : element(labeled: "Stages"), then: 1.5)

        // 6. Settings: target buffer and a daily reminder (system permission prompt)
        tapIfPresent(app.buttons["settings-button"], then: 1.5)
        if tapIfPresent(element(labeled: "3 days early"), timeout: 3, then: 1) {
            tapIfPresent(element(labeled: "1 week early"), timeout: 3, then: 1.2)
        }
        if tapIfPresent(app.switches.firstMatch, timeout: 3, then: 1) {
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            tapIfPresent(springboard.buttons["Allow"], timeout: 6, then: 1.5)
        }
        tapIfPresent(app.buttons["Done"], then: 1.5)

        // 7. Paste a deadline list and review the draft stages
        tapIfPresent(app.buttons["project-menu"], then: 1)
        tapIfPresent(element(labeled: "Paste Deadline List…"), then: 1.5)
        let list = app.textViews["deadline-list-field"]
        if list.waitForExistence(timeout: 5) {
            list.tap(); pause(0.4)
            list.typeText("Literature review – 17 October 2026 – 15%\nMethodology – 21 November 2026\n- Choose methods\n- Ethics form\nFinal report – 15 April 2027 – 70%")
            pause(2)
        }
        tapIfPresent(app.buttons["review-stages-button"], then: 2.5)
        tapIfPresent(app.buttons["save-stages-button"], then: 2.5)

        // 8. Import preview from the clipboard (the prompt copied in step 2)
        tapIfPresent(app.buttons["project-menu"], then: 1)
        tapIfPresent(element(labeled: "Import from Clipboard"), then: 2.5)
        tapIfPresent(app.buttons["Cancel"], timeout: 6, then: 2)

        pause(2)
        XCTFail("Deliberate: keeps the screen recording attachment for export.")
    }
}
