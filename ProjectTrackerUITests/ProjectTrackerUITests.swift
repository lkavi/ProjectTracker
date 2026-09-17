import XCTest

/// End-to-end flows against a fresh, isolated data set. The app is launched
/// with `--ui-testing` (all data in a scratch folder, iCloud skipped) and
/// `--ui-testing-reset` (scratch folder and preferences wiped at launch), so
/// every test starts from the first-run empty state.
final class ProjectTrackerUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-reset"]
        app.launch()
    }

    // MARK: - Both platforms

    func testLaunchShowsEmptyState() {
        XCTAssertTrue(app.staticTexts["No projects yet"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["new-project-button"].exists)
    }

    #if os(iOS)
    // MARK: - iPhone / iPad flows

    private var progressSummary: XCUIElement { app.staticTexts["progress-summary"] }
    private var nextUpTitle: XCUIElement { app.staticTexts["next-up-title"] }

    private let firstStageTasks = [
        "Define your topic, problem statement, and objectives",
        "Agree scope and success criteria with your supervisor",
        "Write and submit the proposal",
    ]

    /// The first on-screen element with exactly this accessibility label.
    private func element(labeled label: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
    }

    /// Creates a project from the empty state and dismisses the guide sheet.
    private func createProject(named name: String) {
        XCTAssertTrue(app.staticTexts["No projects yet"].waitForExistence(timeout: 10))
        app.buttons["new-project-button"].tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let field = alert.textFields.firstMatch
        field.tap()
        field.typeText(name)
        alert.buttons["Create"].tap()

        let later = app.buttons["Maybe Later"]
        XCTAssertTrue(later.waitForExistence(timeout: 5), "the personalize guide appears after creating a project")
        later.tap()
        XCTAssertTrue(progressSummary.waitForExistence(timeout: 5))
    }

    /// Ticks every task of the template's first stage in the Next Up card.
    private func completeFirstStage() {
        for title in firstStageTasks {
            let toggle = element(labeled: title)
            XCTAssertTrue(toggle.waitForExistence(timeout: 5), "task \"\(title)\" should be visible")
            toggle.tap()
        }
    }

    func testNewProjectStartsFromTemplateAndTracksStageCompletion() {
        createProject(named: "Thesis")
        XCTAssertEqual(progressSummary.label, "0 of 6 stages passed")
        XCTAssertTrue(nextUpTitle.label.contains("STAGE 1 OF 6"))

        completeFirstStage()

        XCTAssertEqual(progressSummary.label, "1 of 6 stages passed")
        XCTAssertTrue(nextUpTitle.label.contains("STAGE 2 OF 6"))
    }

    func testProgressSurvivesRelaunch() {
        createProject(named: "Thesis")
        completeFirstStage()
        XCTAssertEqual(progressSummary.label, "1 of 6 stages passed")

        app.terminate()
        app.launchArguments = ["--ui-testing"]   // same scratch data, no reset
        app.launch()

        XCTAssertTrue(progressSummary.waitForExistence(timeout: 10))
        XCTAssertEqual(progressSummary.label, "1 of 6 stages passed")
        XCTAssertTrue(app.navigationBars["Thesis"].exists)
    }

    func testResetProgressRequiresTypedConfirmation() {
        createProject(named: "Thesis")
        completeFirstStage()
        XCTAssertEqual(progressSummary.label, "1 of 6 stages passed")

        app.buttons["more-menu"].tap()
        let reset = element(labeled: "Reset Progress")
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reset.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertFalse(alert.buttons["Reset"].isEnabled, "Reset stays disabled until CONFIRM is typed")
        let field = alert.textFields.firstMatch
        field.tap()
        field.typeText("CONFIRM")
        XCTAssertTrue(alert.buttons["Reset"].isEnabled)
        alert.buttons["Reset"].tap()

        XCTAssertEqual(progressSummary.label, "0 of 6 stages passed")
    }

    func testSettingsSheetShowsTargetAndReminders() {
        createProject(named: "Thesis")
        app.buttons["settings-button"].tap()

        XCTAssertTrue(app.staticTexts["Personal target deadline"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Proposal & Scope"].exists, "every stage gets a reminder row")

        app.buttons["Done"].tap()
        XCTAssertTrue(progressSummary.waitForExistence(timeout: 5))
    }

    func testLibraryAddsReference() {
        let tab = app.tabBars.buttons["Library"]
        (tab.exists ? tab : element(labeled: "Library")).tap()
        XCTAssertTrue(app.staticTexts["No references yet"].waitForExistence(timeout: 5))
        app.buttons["Add First Reference"].tap()

        let field = app.textFields["reference-title-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Attention Is All You Need\n")   // Return dismisses the keyboard
        app.buttons["add-reference-button"].tap()

        XCTAssertTrue(app.staticTexts["1 item"].waitForExistence(timeout: 5))
        let saved = app.textFields
            .matching(NSPredicate(format: "value == %@", "Attention Is All You Need"))
            .firstMatch
        XCTAssertTrue(saved.exists)
    }
    #endif
}
