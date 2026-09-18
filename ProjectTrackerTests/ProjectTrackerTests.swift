import Foundation
import Testing
@testable import ProjectTracker

// MARK: - Status rules

@MainActor
struct StageStatusTests {
    private let cal = Calendar.current
    private func day(_ offset: Int, from today: Date) -> Date {
        cal.date(byAdding: .day, value: offset, to: today)!
    }

    @Test func doneIsAlwaysPassed() {
        let today = Date()
        #expect(StageStatus.compute(done: true, deadline: day(-10, from: today), daysEarly: 3, today: today) == .passed)
        #expect(StageStatus.compute(done: true, deadline: nil, daysEarly: 3, today: today) == .passed)
    }

    @Test func noDeadlineIsQueued() {
        #expect(StageStatus.compute(done: false, deadline: nil, daysEarly: 3) == .queued)
    }

    @Test func pastDeadlineIsBlocked() {
        let today = Date()
        #expect(StageStatus.compute(done: false, deadline: day(-1, from: today), daysEarly: 3, today: today) == .blocked)
    }

    @Test func deadlineTodayOrInsideBufferIsRunning() {
        let today = Date()
        #expect(StageStatus.compute(done: false, deadline: today, daysEarly: 3, today: today) == .running)
        #expect(StageStatus.compute(done: false, deadline: day(2, from: today), daysEarly: 3, today: today) == .running)
    }

    @Test func farDeadlineIsQueued() {
        let today = Date()
        #expect(StageStatus.compute(done: false, deadline: day(10, from: today), daysEarly: 3, today: today) == .queued)
    }

    @Test func dueTextWording() {
        let today = Date()
        #expect(dueText(for: nil, from: today) == "No deadline")
        #expect(dueText(for: today, from: today) == "Due today")
        #expect(dueText(for: day(1, from: today), from: today) == "Due tomorrow")
        #expect(dueText(for: day(5, from: today), from: today) == "Due in 5 days")
        #expect(dueText(for: day(-1, from: today), from: today) == "Overdue by 1 day")
        #expect(dueText(for: day(-2, from: today), from: today) == "Overdue by 2 days")
    }

    @Test func statusLabelsAreHumanWords() {
        #expect(StageStatus.passed.label == "Done")
        #expect(StageStatus.running.label == "In progress")
        #expect(StageStatus.blocked.label == "Overdue")
        #expect(StageStatus.queued.label == "Upcoming")
    }
}

// MARK: - Templates and the AI prompt

@MainActor
struct TemplateAndPromptTests {
    @Test func everyTemplateIsWellFormed() {
        for template in ProjectTemplate.all {
            #expect(!template.stages.isEmpty, "\(template.name) has stages")
            #expect(template.stages.allSatisfy { !$0.tasks.isEmpty }, "\(template.name): every stage has a task")
            #expect(template.stages.last?.position == 1.0, "\(template.name) ends on the final deadline")
            let positions = template.stages.map(\.position)
            #expect(positions == positions.sorted(), "\(template.name) stages are in date order")
        }
        #expect(Set(ProjectTemplate.all.map(\.id)).count == ProjectTemplate.all.count)
    }

    @Test func templateDeadlinesSpanStartToEnd() throws {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 100, to: start)!
        let stages = ProjectTemplate.default.makeStages(start: start, end: end)
        let deadlines = try stages.map { try #require($0.deadlineDate) }
        #expect(deadlines == deadlines.sorted())
        #expect(deadlines.first! >= start)
        #expect(cal.isDate(deadlines.last!, inSameDayAs: end))
        #expect(Set(stages.map(\.id)).count == stages.count)
        #expect(stages.allSatisfy { !$0.tasks.isEmpty })
    }

    @Test func promptContainsRulesSituationAndProjectFile() {
        let project = Project(definition: ProjectDefinition(name: "Thesis", stages: [
            ProjectStage(title: "A", tasks: [ProjectTask(title: "t")])]))
        let prompt = ProjectStore.aiPrompt(for: project)
        #expect(prompt.contains("MY SITUATION"))
        #expect(prompt.contains("RULES FOR THE AI ASSISTANT"))
        #expect(prompt.contains("PROJECT FILE"))
        #expect(prompt.contains("\"name\" : \"Thesis\""))
        #expect(prompt.contains("\"_instructions\""))
    }

    @Test func promptRoundTripsThroughTheImporter() throws {
        // A user who pastes the whole prompt back (instead of just the JSON)
        // must still get a valid import: the extractor finds the JSON block.
        let project = Project(definition: ProjectDefinition(name: "Thesis", stages: [
            ProjectStage(title: "A", deadline: "2030-01-01", tasks: [ProjectTask(title: "t")])]))
        let summary = try ProjectStore.importSummary(from: Data(ProjectStore.aiPrompt(for: project).utf8))
        #expect(summary.project.id == project.id)
        #expect(summary.stageCount == 1)
        #expect(summary.taskCount == 1)
        #expect(summary.keptTicks == 0)
        #expect(summary.replacesExisting == false)
        #expect(summary.firstDeadline != nil && summary.firstDeadline == summary.lastDeadline)
    }
}

// MARK: - Lenient decoding of AI-edited JSON

@MainActor
struct ProjectDecodingTests {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    @Test func bareStringTasksAndMissingIDsAreAccepted() throws {
        let json = """
        {"definition": {"name": "Thesis", "stages": [
            {"title": "Proposal", "deadline": "2030-01-15",
             "tasks": ["Write it", {"title": "Submit it"}]}
        ]}}
        """
        let project = try decoder.decode(Project.self, from: Data(json.utf8))
        #expect(project.definition.name == "Thesis")
        #expect(project.definition.stages.count == 1)
        #expect(project.definition.stages[0].tasks.map(\.title) == ["Write it", "Submit it"])
        #expect(project.schemaVersion == 1)
        #expect(project.progress.completedTaskIDs.isEmpty)
    }

    @Test func duplicateIDsAreGivenFreshOnes() throws {
        let dup = "11111111-1111-4111-8111-111111111111"
        let json = """
        {"definition": {"name": "P", "stages": [
            {"id": "\(dup)", "title": "A", "tasks": [{"id": "\(dup)", "title": "t1"}]},
            {"id": "\(dup)", "title": "B", "tasks": [{"id": "\(dup)", "title": "t2"}]}
        ]}}
        """
        let project = try decoder.decode(Project.self, from: Data(json.utf8))
        var ids = Set(project.definition.stages.map(\.id))
        ids.formUnion(project.allTaskIDs)
        #expect(ids.count == 4)
        #expect(project.definition.stages[0].id == UUID(uuidString: dup))
    }

    @Test func isoTimestampDeadlineUsesDatePart() {
        let stage = ProjectStage(title: "x", deadline: "2030-03-04T10:00:00Z", tasks: [])
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: stage.deadlineDate!)
        #expect(comps.year == 2030 && comps.month == 3 && comps.day == 4)
        #expect(ProjectStage(title: "y", deadline: "soon", tasks: []).deadlineDate == nil)
    }

    @Test func invalidProgressIDsAreDropped() throws {
        let valid = UUID().uuidString
        let json = """
        {"definition": {"name": "P", "stages": [{"title": "A", "tasks": ["t"]}]},
         "progress": {"completedTaskIDs": ["not-a-uuid", "\(valid)"]}}
        """
        let project = try decoder.decode(Project.self, from: Data(json.utf8))
        #expect(project.progress.completedTaskIDs == [UUID(uuidString: valid)!])
    }

    @Test func encodingIsStableAndKeepsInstructionsKey() throws {
        var project = Project(
            instructions: "read me",
            definition: ProjectDefinition(name: "P", stages: [
                ProjectStage(title: "A", tasks: [ProjectTask(title: "t1"), ProjectTask(title: "t2")])
            ]))
        for task in project.definition.stages[0].tasks { project.setTask(task.id, done: true) }
        // ISO-8601 encoding keeps whole seconds only, so use a whole-second date
        // for an exact round trip.
        project.createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let text = String(decoding: try encoder.encode(project), as: UTF8.self)
        #expect(text.contains("\"_instructions\":\"read me\""))
        let ids = project.progress.completedTaskIDs.map(\.uuidString).sorted()
        #expect(text.contains("\"completedTaskIDs\":[\"\(ids[0])\",\"\(ids[1])\"]"))
        let roundTrip = try decoder.decode(Project.self, from: Data(text.utf8))
        #expect(roundTrip == project)
    }
}

// MARK: - Progress helpers

@MainActor
struct ProgressHelperTests {
    private func makeProject() -> Project {
        Project(definition: ProjectDefinition(name: "P", stages: [
            ProjectStage(title: "A", deadline: nil, tasks: [ProjectTask(title: "a1"), ProjectTask(title: "a2")]),
            ProjectStage(title: "B", deadline: nil, tasks: [ProjectTask(title: "b1")]),
        ]))
    }

    @Test func stageWithNoTasksIsNeverDone() {
        let project = makeProject()
        #expect(project.isStageDone(ProjectStage(title: "empty", tasks: [])) == false)
    }

    @Test func stageIsDoneOnlyWhenEveryTaskIsTicked() {
        var project = makeProject()
        let stage = project.definition.stages[0]
        project.setTask(stage.tasks[0].id, done: true)
        #expect(project.isStageDone(stage) == false)
        project.setTask(stage.tasks[1].id, done: true)
        #expect(project.isStageDone(stage))
        #expect(project.passedStageCount == 1)
        project.setTask(stage.tasks[1].id, done: false)
        #expect(project.passedStageCount == 0)
    }

    @Test func nextStageIsFirstUnfinishedThenFallsBackToLast() {
        var project = makeProject()
        #expect(project.nextStage?.title == "A")
        for task in project.definition.stages[0].tasks { project.setTask(task.id, done: true) }
        #expect(project.nextStage?.title == "B")
        project.setTask(project.definition.stages[1].tasks[0].id, done: true)
        #expect(project.nextStage?.title == "B")
    }

    @Test func urgentStagesAreUnfinishedAndDueSoon() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        let today = Date()
        func plus(_ days: Int) -> String {
            f.string(from: Calendar.current.date(byAdding: .day, value: days, to: today)!)
        }
        var project = Project(definition: ProjectDefinition(name: "P", stages: [
            ProjectStage(title: "soon", deadline: plus(2), tasks: [ProjectTask(title: "t")]),
            ProjectStage(title: "later", deadline: plus(20), tasks: [ProjectTask(title: "t")]),
            ProjectStage(title: "overdue-but-done", deadline: plus(-5), tasks: [ProjectTask(title: "t")]),
            ProjectStage(title: "undated", deadline: nil, tasks: [ProjectTask(title: "t")]),
        ]))
        project.setTask(project.definition.stages[2].tasks[0].id, done: true)
        #expect(project.urgentStages(withinDays: 3, today: today).map(\.title) == ["soon"])
    }
}

// MARK: - Import pipeline (fence stripping, validation, progress preservation)

@MainActor
struct ImportTests {
    private func validJSON(name: String = "Thesis", taskID: UUID = UUID(), extraProgress: [String] = []) -> String {
        let progress = ([taskID.uuidString] + extraProgress).map { "\"\($0)\"" }.joined(separator: ",")
        return """
        {"id": "\(UUID().uuidString)",
         "definition": {"name": "\(name)", "stages": [
            {"title": "Proposal", "deadline": "2030-01-15",
             "tasks": [{"id": "\(taskID.uuidString)", "title": "Write it"}]}]},
         "progress": {"completedTaskIDs": [\(progress)]}}
        """
    }

    @Test func stripsMarkdownFencesAndCommentary() throws {
        let raw = "Here is your tailored file:\n```json\n\(validJSON())\n```\nLet me know if you need changes!"
        let project = try ProjectStore.importProject(from: Data(raw.utf8))
        #expect(project.definition.name == "Thesis")
    }

    @Test func keepsOnlyProgressForTasksThatExist() throws {
        let keep = UUID()
        let project = try ProjectStore.importProject(
            from: Data(validJSON(taskID: keep, extraProgress: [UUID().uuidString]).utf8))
        #expect(project.progress.completedTaskIDs == [keep])
    }

    @Test func rejectsNonJSON() {
        #expect(throws: ProjectStore.ImportError.self) {
            try ProjectStore.importProject(from: Data("hello there".utf8))
        }
    }

    @Test func rejectsProjectWithoutStages() {
        let raw = #"{"definition": {"name": "Empty", "stages": []}}"#
        #expect(throws: ProjectStore.ImportError.self) {
            try ProjectStore.importProject(from: Data(raw.utf8))
        }
    }

    @Test func rejectsStageWithoutTasks() {
        let raw = #"{"definition": {"name": "P", "stages": [{"title": "Lonely", "tasks": []}]}}"#
        #expect(throws: ProjectStore.ImportError.self) {
            try ProjectStore.importProject(from: Data(raw.utf8))
        }
    }

    @Test func exportFilenameIsFilesystemSafe() {
        let project = Project(definition: ProjectDefinition(name: "AI/ML: Thesis\\Draft", stages: []))
        #expect(ProjectStore.exportFilename(project) == "AI-ML- Thesis-Draft.project-tracker.json")
    }
}
