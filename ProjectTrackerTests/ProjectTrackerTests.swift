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

// MARK: - Deadline list parser, template sharing, share inbox

@MainActor
struct DeadlineListParserTests {
    @Test func tabTableBecomesChronologicalStagesWithWeights() {
        let text = "Final report\t15 Apr 2027\t70%\nProposal\t17 Oct 2026\t10%\nLiterature review\t21 Nov 2026"
        let r = DeadlineListParser.parse(text)
        #expect(r.stages.map(\.title) == ["Proposal", "Literature review", "Final report"])
        #expect(r.stages.map(\.weight) == ["10%", nil, "70%"])
        #expect(r.stages.map(\.deadline) == ["2026-10-17", "2026-11-21", "2027-04-15"])
        #expect(r.stages.allSatisfy { !$0.tasks.isEmpty })
        #expect(r.skippedLines == 0)
    }

    @Test func bulletsUnderAStageBecomeItsTasks() {
        let text = """
        Methodology chapter – 5 December 2026
        - Choose methods
        - Complete the ethics form
        Implementation due 20 January 2027
        """
        let r = DeadlineListParser.parse(text)
        #expect(r.stages.count == 2)
        #expect(r.stages[0].title == "Methodology chapter")
        #expect(r.stages[0].tasks.map(\.title) == ["Choose methods", "Complete the ethics form"])
        #expect(r.stages[1].title == "Implementation")
        #expect(r.stages[1].tasks.map(\.title) == ["Finish Implementation"])
    }

    @Test func proseWithoutDatesIsSkipped() {
        let r = DeadlineListParser.parse("Welcome to the module.\nSubmit everything on Blackboard.\nViva 3 June 2027")
        #expect(r.stages.count == 1)
        #expect(r.stages.first?.title == "Viva")
        #expect(r.skippedLines == 2)
    }

    /// "fall on a Thursday" resolves to next Thursday in NSDataDetector; a
    /// deadline must name a day or month number.
    @Test func bareWeekdayIsNotADeadline() {
        let r = DeadlineListParser.parse("Deadlines were moved to fall on a Thursday.\nProposal 17 October 2026")
        #expect(r.stages.map(\.title) == ["Proposal"])
    }

    @Test func longSentenceWithADateIsProseNotAStage() {
        let sentence = "Please note that all of the following deadlines were confirmed by the programme board at its meeting on 1 June 2026 and apply to every student on the module this year."
        let r = DeadlineListParser.parse(sentence + "\nFinal report 15 April 2027")
        #expect(r.stages.map(\.title) == ["Final report"])
        #expect(r.skippedLines == 1)
    }

    /// A real course email: two tab-separated tables inside prose, a signature
    /// with phone numbers, links and a Dos/Don'ts list.
    @Test func wholeDeadlinesEmailGivesJustTheStages() {
        let email = """
        Hi Students,
        Please carefully note the following deadlines. These deadlines have been adjusted to fall on a Thursday and a working day in Sri Lanka, wherever required.
        Supervisor List:
        https://docs.google.com/spreadsheets/d/abc/edit?usp=sharing
        If there is no response after three working days, contact another supervisor.
        Formative Submission Deadlines
        Component\tDeadline
        Introduction Chapter\tThursday, 2 July 2026
        Methodology Chapter\tThursday, 16 July 2026
        Literature Review Chapter\tThursday, 17 September 2026
        Software Requirements Specification / SRS\tThursday, 15 October 2026
        Proof of Concept\tThursday, 17 December 2026
        Design and Prototype\tThursday, 21 January 2027
        Testing and Evaluation\tThursday, 4 March 2027
        First Version of Final Thesis Draft\tThursday, 18 March 2027
        Summative Submission Deadlines
        Component\tDeadline\tMarks
        PPRS – Document and Video Presentation\tThursday, 19 November 2026\t15%
        IPD – Document and Video Demonstration\tThursday, 11 February 2027\t15%
        Final Submission – Thesis Document, Video Demonstration and Code\tThursday, 1 April 2027\t70%
        Important Dos
        Start each chapter early and avoid writing everything close to the deadline.
        With regards,
        | T: +00-111-222-333/444(Dir)| F: +00-111-222-555 |
        """
        let r = DeadlineListParser.parse(email)
        #expect(r.stages.count == 11)
        #expect(r.stages.first?.title == "Introduction Chapter")
        #expect(r.stages.first?.deadline == "2026-07-02")
        #expect(r.stages.last?.deadline == "2027-04-01")
        #expect(r.stages.compactMap(\.weight) == ["15%", "15%", "70%"])
        // PPRS sits between SRS and Proof of Concept by date.
        #expect(r.stages[4].title == "PPRS – Document and Video Presentation")
        #expect(r.stages.allSatisfy(DeadlineListParser.hasOnlyPlaceholderTask))
    }
}

// MARK: - On-device planner: turning model output into stages

@MainActor
struct AIStagePlannerTests {
    private func draft(_ titles: [String]) -> [ProjectStage] {
        DeadlineListParser.parse(titles.enumerated()
            .map { "\($1) \($0 + 1) March 2027" }.joined(separator: "\n")).stages
    }

    @Test func tasksAreMergedByTitleAndDatesAreKept() {
        let stages = draft(["Proposal", "Final report"])
        let merged = AIStagePlanner.merge(draft: stages, taskLists: [
            .init(title: "Final report", tasks: ["Proofread the thesis", "Submit the code"]),
            .init(title: "Proposal", tasks: ["1. Write the aim", "- Agree scope with supervisor"]),
        ])
        #expect(merged.map(\.title) == ["Proposal", "Final report"])
        #expect(merged.map(\.deadline) == stages.map(\.deadline))
        #expect(merged[0].tasks.map(\.title) == ["Write the aim", "Agree scope with supervisor"])
        #expect(merged[1].tasks.map(\.title) == ["Proofread the thesis", "Submit the code"])
    }

    @Test func tasksTheUserPastedAreNeverReplaced() {
        let stages = DeadlineListParser.parse("Methodology 5 December 2026\n- Choose methods").stages
        let merged = AIStagePlanner.merge(draft: stages, taskLists: [
            .init(title: "Methodology", tasks: ["Something else", "Another thing"]),
        ])
        #expect(merged[0].tasks.map(\.title) == ["Choose methods"])
    }

    @Test func unmatchedStagesKeepTheirPlaceholder() {
        let stages = draft(["Proposal", "Final report"])
        let merged = AIStagePlanner.merge(draft: stages, taskLists: [
            .init(title: "Something unrelated", tasks: ["Do a thing", "Do another"]),
        ])
        #expect(merged.allSatisfy(DeadlineListParser.hasOnlyPlaceholderTask))
    }

    private let september27 = DateComponents(calendar: Calendar(identifier: .gregorian),
                                             year: 2026, month: 9, day: 27).date!

    @Test func extractedStagesAreValidatedSortedAndDeduplicated() {
        let stages = AIStagePlanner.stages(from: [
            .init(title: "Final report", date: "1 April 2027", weight: "70", tasks: ["Submit", "Submit", ""]),
            .init(title: "Proposal", date: "15th October 2026", weight: "", tasks: []),
            .init(title: "Proposal", date: "2026-10-15", weight: "", tasks: ["Duplicate"]),
            .init(title: "Viva", date: "sometime in May", weight: "15%", tasks: ["Prepare slides", "Viva"]),
            .init(title: "  ", date: "1 November 2026", weight: "", tasks: ["No title"]),
        ], today: september27)
        #expect(stages.map(\.title) == ["Proposal", "Final report", "Viva"])
        #expect(stages.map(\.deadline) == ["2026-10-15", "2027-04-01", nil])
        #expect(stages.map(\.weight) == [nil, "70%", "15%"])
        #expect(stages[0].tasks.map(\.title) == ["Finish Proposal"])
        #expect(stages[1].tasks.map(\.title) == ["Submit"])
        #expect(stages[2].tasks.map(\.title) == ["Prepare slides"])   // the stage title isn't a task
    }

    @Test func aDeadlineTableOnlyNeedsTasksWritten() {
        let stages = DeadlineListParser.parse("Proposal\t17 Oct 2026\nFinal report\t15 Apr 2027\t70%").stages
        #expect(AIStagePlanner.mode(for: stages) == .writeTasks)
    }

    @Test func proseIsReadByTheModelInstead() {
        let prose = """
        The final dissertation (80%) must be submitted through Turnitin on 30 April 2027 together with your code repository.
        """
        let stages = DeadlineListParser.parse(prose).stages
        #expect(stages.count == 1)
        #expect(!stages[0].title.contains("( )"))            // lifted weight leaves no empty brackets
        #expect(AIStagePlanner.mode(for: stages) == .extract)
        #expect(AIStagePlanner.mode(for: []) == .extract)
    }

    @Test func listRowsTheModelMissedAreAddedBack() {
        let parser = DeadlineListParser.parse("Proposal 17 October 2026\nViva 3 June 2027").stages
        let extracted = AIStagePlanner.stages(from: [
            .init(title: "Research proposal", date: "17 October", weight: "", tasks: ["Write it", "Send it"]),
        ], today: september27)
        let merged = AIStagePlanner.union(extracted, parserStages: parser)
        #expect(merged.map(\.title) == ["Research proposal", "Viva"])   // same date → not duplicated
        #expect(merged.map(\.deadline) == ["2026-10-17", "2027-06-03"])
    }

    /// "The week of 8 March" read on 27 September means next March, not the
    /// one already gone; a written year is kept as it is.
    @Test func yearIsWorkedOutFromTodayWhenTheDocumentOmitsIt() {
        #expect(AIStagePlanner.resolveDeadline(day: 8, month: 3, year: 0, today: september27) == "2027-03-08")
        #expect(AIStagePlanner.resolveDeadline(day: 15, month: 10, year: 0, today: september27) == "2026-10-15")
        #expect(AIStagePlanner.resolveDeadline(day: 27, month: 9, year: 0, today: september27) == "2026-09-27")
        #expect(AIStagePlanner.resolveDeadline(day: 2, month: 7, year: 2026, today: september27) == "2026-07-02")
        #expect(AIStagePlanner.resolveDeadline(day: 30, month: 4, year: 27, today: september27) == "2027-04-30")
        #expect(AIStagePlanner.resolveDeadline(day: 31, month: 2, year: 2027, today: september27) == nil)
        #expect(AIStagePlanner.resolveDeadline(day: 0, month: 5, year: 2027, today: september27) == nil)
        #expect(AIStagePlanner.resolveDeadline(day: 5, month: 5, year: 1999, today: september27) == nil)
    }

    @Test func dateTextTheModelCopiedIsParsedHere() {
        let t = september27
        #expect(AIStagePlanner.parseDeadline("15 October", today: t) == "2026-10-15")
        #expect(AIStagePlanner.parseDeadline("3rd December 2026", today: t) == "2026-12-03")
        #expect(AIStagePlanner.parseDeadline("the week of 8 March", today: t) == "2027-03-08")
        #expect(AIStagePlanner.parseDeadline("Thursday, 1 April 2027", today: t) == "2027-04-01")
        #expect(AIStagePlanner.parseDeadline("April 30, 2027", today: t) == "2027-04-30")
        #expect(AIStagePlanner.parseDeadline("2027-02-12", today: t) == "2027-02-12")
        #expect(AIStagePlanner.parseDeadline("3/12/2026", today: t) == "2026-12-03")
        #expect(AIStagePlanner.parseDeadline("", today: t) == nil)
        #expect(AIStagePlanner.parseDeadline("sometime in May", today: t) == nil)
    }

    @Test func longDocumentsAreCutAtALineBreak() {
        let line = String(repeating: "x", count: 99)
        let doc = Array(repeating: line, count: 200).joined(separator: "\n")
        let trimmed = AIStagePlanner.trimmedDocument(doc)
        #expect(trimmed.count <= AIStagePlanner.maxDocumentCharacters)
        #expect(trimmed.hasSuffix(line))
    }

    @Test func stagesWithTheirOwnTasksSkipTheModel() async throws {
        let stages = DeadlineListParser.parse("Methodology 5 December 2026\n- Choose methods").stages
        let planned = try await AIStagePlanner.plan(document: "irrelevant", draft: stages)
        #expect(planned == stages)
    }
}

@MainActor
struct SharingTests {
    @Test func templateCopyStripsProgressAndGetsANewIdentity() throws {
        var project = Project(definition: ProjectDefinition(name: "Thesis", stages: [
            ProjectStage(title: "A", deadline: "2030-01-01", tasks: [ProjectTask(title: "t")])]))
        project.setTask(project.definition.stages[0].tasks[0].id, done: true)
        let data = try #require(ProjectStore.templateData(project))
        let summary = try ProjectStore.importSummary(from: data)
        #expect(summary.project.id != project.id)
        #expect(summary.keptTicks == 0)
        #expect(summary.replacesExisting == false)
        #expect(summary.project.definition == project.definition)
        #expect(ProjectStore.templateFilename(project) == "Thesis template.project-tracker.json")
    }

    // The App Group container needs a signed host; unsigned CLI test runs skip this.
    @Test(.enabled(if: SharedInbox.isAvailable)) func sharedInboxRoundTrip() throws {
        let url = try #require(SharedInbox.save(Data("{}".utf8)))
        #expect(SharedInbox.pending().contains(url))
        SharedInbox.remove(url)
        #expect(!SharedInbox.pending().contains(url))
    }
}

struct StageUpdaterTests {
    private func stage(_ title: String, _ deadline: String?, weight: String? = nil, tasks: [String] = ["t"]) -> ProjectStage {
        ProjectStage(title: title, weight: weight, deadline: deadline, tasks: tasks.map { ProjectTask(title: $0) })
    }

    @Test func movedDeadlineKeepsIdAndTasks() {
        let existing = [stage("Project Proposal", "2026-10-15", tasks: ["Draft", "Submit"]),
                        stage("Interim Report", "2027-02-12")]
        let incoming = [stage("Project Proposal", "2026-10-22"), stage("Interim Report", "2027-02-12")]
        let result = StageUpdater.merge(existing: existing, incoming: incoming)
        #expect(result.stages.map(\.id) == existing.map(\.id))
        #expect(result.stages[0].deadline == "2026-10-22")
        #expect(result.stages[0].tasks.map(\.title) == ["Draft", "Submit"])
        #expect(result.summary.datesChanged == 1)
        #expect(result.summary.unchanged == 1)
        #expect(result.notes[existing[0].id]?.hasPrefix("Moved from") == true)
    }

    @Test func weightingChangeIsApplied() {
        let existing = [stage("Final Report", "2027-04-30", weight: "70%")]
        let result = StageUpdater.merge(existing: existing, incoming: [stage("Final Report", "2027-04-30", weight: "80%")])
        #expect(result.stages[0].weight == "80%")
        #expect(result.summary.weightsChanged == 1)
    }

    @Test func newStageSlotsInByDate() {
        let existing = [stage("Proposal", "2026-10-15"), stage("Final Report", "2027-04-30")]
        let incoming = [stage("Proposal", "2026-10-15"), stage("Ethics Form", "2026-12-03"), stage("Final Report", "2027-04-30")]
        let result = StageUpdater.merge(existing: existing, incoming: incoming)
        #expect(result.stages.map(\.title) == ["Proposal", "Ethics Form", "Final Report"])
        #expect(result.summary.added == 1)
    }

    @Test func missingStageIsKeptAndFlagged() {
        let existing = [stage("Proposal", "2026-10-15"), stage("Viva", "2027-05-20")]
        let result = StageUpdater.merge(existing: existing, incoming: [stage("Proposal", "2026-10-15")])
        #expect(result.stages.count == 2)
        #expect(result.summary.notInPaste == 1)
        #expect(result.notes[existing[1].id] == StageUpdater.notInPasteNote)
        #expect(result.summary.hasChanges == false)
    }

    @Test func abbreviatedTitleStillMatches() {
        let existing = [stage("Software Requirements Specification (SRS)", "2026-11-20")]
        let result = StageUpdater.merge(existing: existing, incoming: [stage("SRS", "2026-11-27")])
        #expect(result.stages.count == 1)
        #expect(result.stages[0].id == existing[0].id)
        #expect(result.stages[0].deadline == "2026-11-27")
    }

    @Test func numberedStagesDoNotCrossMatch() {
        #expect(StageUpdater.similarity("Study Block 1", "Study Block 2") == 0)
        let existing = [stage("Study Block 1", "2026-10-01"), stage("Study Block 2", "2026-11-01")]
        let incoming = [stage("Study Block 2", "2026-11-08")]
        let result = StageUpdater.merge(existing: existing, incoming: incoming)
        #expect(result.stages[1].deadline == "2026-11-08")
        #expect(result.stages[0].deadline == "2026-10-01")
    }

    @Test func onlyUserWrittenTasksAreAdded() {
        let existing = [stage("Proposal", "2026-10-15", tasks: ["Draft"])]
        let aiWritten = stage("Proposal", "2026-10-15", tasks: ["Draft", "Research topic"])
        #expect(StageUpdater.merge(existing: existing, incoming: [aiWritten]).stages[0].tasks.count == 1)
        let typed = StageUpdater.merge(existing: existing, incoming: [aiWritten], userWrittenTaskStageIDs: [aiWritten.id])
        #expect(typed.stages[0].tasks.map(\.title) == ["Draft", "Research topic"])
        #expect(typed.summary.tasksAdded == 1)
    }

    @Test func summarySentenceReadsNaturally() {
        var s = StageUpdater.Summary()
        s.datesChanged = 2; s.added = 1; s.unchanged = 9
        #expect(s.sentence == "2 dates moved, 1 new stage. 9 stages unchanged.")
        #expect(StageUpdater.Summary().sentence == "No changes found.")
    }
}
