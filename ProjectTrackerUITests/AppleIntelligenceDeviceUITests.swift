import XCTest

/// Checks the Apple Intelligence setup on a real device (the Simulator's
/// model can't run it). Uses scratch data, never the device's own projects.
/// Run on an unlocked iPhone with Apple Intelligence turned on:
///
///   TEST_RUNNER_AI_DEVICE_TEST=1 xcodebuild test … -destination 'platform=iOS,id=<udid>' \
///     -only-testing:ProjectTrackerUITests/AppleIntelligenceDeviceUITests
final class AppleIntelligenceDeviceUITests: XCTestCase {
    func testPastedEmailGetsStagesAndTasks() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["AI_DEVICE_TEST"] == "1",
                          "On-device check only; set TEST_RUNNER_AI_DEVICE_TEST=1 to run it.")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-reset", "--ui-testing-ai"]
        app.launch()

        let card = app.buttons["paste-deadlines-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(card.label.contains("Set up in seconds"), "Apple Intelligence should be available: \(card.label)")
        card.tap()

        let name = app.textFields["paste-project-name-field"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Dissertation\n")
        let field = app.textViews["deadline-list-field"]
        field.tap()
        field.typeText("""
        Hi all, please note the deadlines for this year.
        Proposal - 17 October 2026
        Ethics form - 5 December 2026
        Interim report - 12 February 2027 - 20%
        Final dissertation - 30 April 2027 - 80%
        Best of luck, Module team
        """)

        let started = Date()
        app.buttons["review-stages-button"].tap()
        let create = app.buttons["save-stages-button"]
        XCTAssertTrue(create.waitForExistence(timeout: 120), "the review list should appear")
        let seconds = Date().timeIntervalSince(started)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Review after Apple Intelligence (\(Int(seconds)) s)"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Each review row reads "3 tasks · Oct 17, 2026"; the parser alone gives "1 task".
        let rows = app.staticTexts.allElementsBoundByIndex.map(\.label).filter { $0.contains(" · ") && $0.contains("task") }
        print("AI device check: \(Int(seconds)) s, rows: \(rows)")
        XCTAssertEqual(rows.count, 4, "\(rows)")
        XCTAssertTrue(rows.allSatisfy { !$0.hasPrefix("1 task") }, "Apple Intelligence should write several tasks per stage: \(rows)")
    }
}
