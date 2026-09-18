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

    /// Creates a project from the empty state (default template, default
    /// dates) and dismisses the setup guide.
    private func createProject(named name: String, dismissGuide: Bool = true) {
        XCTAssertTrue(app.staticTexts["No projects yet"].waitForExistence(timeout: 10))
        app.buttons["new-project-button"].tap()

        let field = app.textFields["project-name-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        app.buttons["create-project-button"].tap()

        let notNow = app.buttons["guide-not-now-button"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 8), "the setup guide appears after creating a project")
        if dismissGuide {
            notNow.tap()
            XCTAssertTrue(progressSummary.waitForExistence(timeout: 5))
        }
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
        XCTAssertEqual(progressSummary.label, "0 of 7 stages done")
        XCTAssertTrue(nextUpTitle.label.contains("Stage 1 of 7"))

        completeFirstStage()

        XCTAssertEqual(progressSummary.label, "1 of 7 stages done")
        XCTAssertTrue(nextUpTitle.label.contains("Stage 2 of 7"))
    }

    func testProgressSurvivesRelaunch() {
        createProject(named: "Thesis")
        completeFirstStage()
        XCTAssertEqual(progressSummary.label, "1 of 7 stages done")

        app.terminate()
        app.launchArguments = ["--ui-testing"]   // same scratch data, no reset
        app.launch()

        XCTAssertTrue(progressSummary.waitForExistence(timeout: 10))
        XCTAssertEqual(progressSummary.label, "1 of 7 stages done")
        XCTAssertTrue(app.navigationBars["Thesis"].exists)
    }

    func testResetProgressRequiresTypedConfirmation() {
        createProject(named: "Thesis")
        completeFirstStage()
        XCTAssertEqual(progressSummary.label, "1 of 7 stages done")

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

        XCTAssertEqual(progressSummary.label, "0 of 7 stages done")
    }

    func testSettingsSheetShowsTargetAndReminders() {
        createProject(named: "Thesis")
        app.buttons["settings-button"].tap()

        XCTAssertTrue(app.staticTexts["Personal target deadline"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Proposal & Scope"].exists, "every stage gets a reminder row")

        app.buttons["Done"].tap()
        XCTAssertTrue(progressSummary.waitForExistence(timeout: 5))
    }

    func testCopyPromptThenImportFromClipboardShowsPreview() {
        createProject(named: "Thesis", dismissGuide: false)
        app.buttons["copy-prompt-button"].tap()
        XCTAssertTrue(app.buttons["Prompt Copied"].waitForExistence(timeout: 5))

        // The clipboard now holds the whole prompt; the importer digs the JSON
        // out of it, so a preview for the same project must appear.
        app.buttons["Import from Clipboard"].tap()
        let confirm = app.buttons["confirm-import-button"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 8))
        XCTAssertEqual(confirm.label, "Replace", "same project id means the import replaces it")
        XCTAssertTrue(app.staticTexts["Thesis"].exists)
        app.buttons["Cancel"].tap()
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

        XCTAssertTrue(app.staticTexts["1 reference"].waitForExistence(timeout: 5))
        let saved = app.textFields
            .matching(NSPredicate(format: "value == %@", "Attention Is All You Need"))
            .firstMatch
        XCTAssertTrue(saved.exists)
    }
    #endif
}
