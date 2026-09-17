import Foundation

/// Persists projects as individual JSON files in iCloud Drive
/// (<container>/Documents/FYPPipeline/projects/<uuid>.json — the folder name is
/// CloudContainer.dataFolderName) so they sync across devices.
///
/// Each file holds the project "definition" (structure — tailorable by an AI
/// agent) and "progress" (ticked task ids) side by side, linked by UUIDs.
@MainActor
enum ProjectStore {
    static var projectsDir: URL {
        CloudContainer.baseURL.appendingPathComponent("projects", isDirectory: true)
    }

    private static func fileURL(for id: UUID) -> URL {
        projectsDir.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: - Active project

    private static let activeKey = "fyp-active-project-v1"

    static var activeProjectID: UUID? {
        get { UserDefaults.standard.string(forKey: activeKey).flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: activeKey) }
    }

    // MARK: - CRUD

    static func loadAll() -> [Project] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: nil)) ?? []
        var projects: [Project] = []
        for url in urls where url.pathExtension == "json" {
            guard let data = CloudContainer.read(at: url),
                  let project = try? decoder.decode(Project.self, from: data)
            else { continue }
            projects.append(project)
        }
        return projects.sorted { $0.createdAt < $1.createdAt }
    }

    static func save(_ project: Project) {
        guard let data = try? encoder.encode(project) else { return }
        CloudContainer.write(data, to: fileURL(for: project.id))
        // Refresh with the just-saved copy so a widget pinned to this project
        // updates even when it isn't the active one.
        refreshWidgetSnapshots(with: project)
    }

    static func delete(_ project: Project) {
        CloudContainer.delete(at: fileURL(for: project.id))
        if activeProjectID == project.id { activeProjectID = nil }
    }

    /// New project from the built-in generic template, with fresh UUIDs and
    /// deadlines spread into the future from today. Meant as a neutral
    /// starting point the user then tailors with an AI agent.
    static func create(named name: String) -> Project {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let project = Project(
            instructions: aiInstructions,
            definition: ProjectDefinition(
                name: trimmed.isEmpty ? "Untitled project" : trimmed,
                topic: nil,
                stages: genericTemplateStages()
            )
        )
        save(project)
        return project
    }

    /// Six generic project stages with deadlines placed weeks ahead of
    /// today, so a brand-new project always opens with sensible future dates
    /// instead of hardcoded ones.
    private static func genericTemplateStages() -> [ProjectStage] {
        let today = Date()
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        func deadline(weeksAhead weeks: Int) -> String {
            let date = Calendar.current.date(byAdding: .day, value: weeks * 7, to: today) ?? today
            return f.string(from: date)
        }
        func stage(_ title: String, _ weeks: Int, _ tasks: [String]) -> ProjectStage {
            ProjectStage(title: title, weight: nil, deadline: deadline(weeksAhead: weeks),
                         tasks: tasks.map { ProjectTask(title: $0) })
        }
        return [
            stage("Proposal & Scope", 3, [
                "Define your topic, problem statement, and objectives",
                "Agree scope and success criteria with your supervisor",
                "Write and submit the proposal",
            ]),
            stage("Literature Review", 8, [
                "Collect and read the key papers in your area",
                "Summarise findings in a review matrix",
                "Identify and articulate your research gap",
            ]),
            stage("Methodology & Design", 13, [
                "Choose your approach, methods, and tools",
                "Define how you will evaluate results",
                "Draft the methodology / design document",
            ]),
            stage("Implementation / Data Collection", 19, [
                "Build the core of your project or gather your data",
                "Keep notes on key decisions and issues",
                "Check in with your supervisor on progress",
            ]),
            stage("Evaluation & Analysis", 25, [
                "Run your evaluation with proper metrics",
                "Compare against a baseline where possible",
                "Write up results honestly, including limitations",
            ]),
            stage("Final Submission", 30, [
                "Assemble everything into the full document",
                "Proofread, format, and check references",
                "Back up in two places, then submit",
            ]),
        ]
    }

    // MARK: - Export (give this file to an AI agent)

    static func exportData(_ project: Project) -> Data? {
        var copy = project
        if copy.instructions == nil { copy.instructions = aiInstructions }
        return try? encoder.encode(copy)
    }

    static func exportFilename(_ project: Project) -> String {
        let safe = project.definition.name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:"))
            .joined(separator: "-")
        return "\(safe).project-tracker.json"
    }

    // MARK: - Import (tailored JSON coming back from the AI agent)

    enum ImportError: Error {
        case notJSON(String)
        case invalid(String)

        var message: String {
            switch self {
            case .notJSON(let detail):
                return "The file isn't valid JSON. \(detail)"
            case .invalid(let detail):
                return detail
            }
        }
    }

    /// Lenient, id-preserving import. Strips markdown fences / commentary the
    /// AI may have wrapped around the JSON, tolerates missing ids, validates
    /// the structure, and — when a project with the same id already exists —
    /// replaces its definition while merging progress by task id, so nothing
    /// the student already ticked off is lost.
    static func importProject(from raw: Data) throws -> Project {
        let data = extractJSON(raw)
        var imported: Project
        do {
            imported = try decoder.decode(Project.self, from: data)
        } catch {
            throw ImportError.notJSON(
                "Make sure you saved the AI's complete JSON output (it must contain a \"definition\" section).")
        }

        guard !imported.definition.stages.isEmpty else {
            throw ImportError.invalid("The project has no stages — \"definition.stages\" is empty.")
        }
        if let empty = imported.definition.stages.first(where: { $0.tasks.isEmpty }) {
            throw ImportError.invalid("Stage \"\(empty.title)\" has no tasks. Every stage needs at least one task.")
        }

        let validIDs = imported.allTaskIDs
        if var existing = loadAll().first(where: { $0.id == imported.id }) {
            existing.definition = imported.definition
            existing.instructions = imported.instructions ?? existing.instructions
            existing.progress.completedTaskIDs = existing.progress.completedTaskIDs
                .union(imported.progress.completedTaskIDs)
                .intersection(validIDs)
            return existing
        }
        imported.progress.completedTaskIDs =
            imported.progress.completedTaskIDs.intersection(validIDs)
        return imported
    }

    /// Pulls the first {...} block out of whatever surrounds it (```json
    /// fences, "Here is your file:" preambles, trailing commentary).
    private static func extractJSON(_ data: Data) -> Data {
        guard var s = String(data: data, encoding: .utf8) else { return data }
        if let first = s.firstIndex(of: "{"), let last = s.lastIndex(of: "}"), first < last {
            s = String(s[first...last])
        }
        return Data(s.utf8)
    }

    // MARK: - Widget snapshots

    /// Rebuilds the widget snapshot for every project and refreshes the picker
    /// list, so a widget pinned to any project — not just the active one —
    /// stays current. Call after any change that affects what a widget shows
    /// (progress, structure, project add/rename/delete, active switch, notes).
    ///
    /// The `with:` project, when given, is used in place of its freshly-loaded
    /// copy so an in-memory edit is reflected without a redundant disk read.
    static func refreshWidgetSnapshots(with edited: Project? = nil) {
        var projects = loadAll()
        if let edited, let idx = projects.firstIndex(where: { $0.id == edited.id }) {
            projects[idx] = edited
        } else if let edited {
            projects.append(edited)
        }
        var snapshots: [UUID: WidgetSnapshot] = [:]
        var refs: [ProjectRef] = []
        for project in projects {
            refs.append(ProjectRef(id: project.id, name: project.definition.name))
            if let snap = buildSnapshot(for: project) { snapshots[project.id] = snap }
        }
        ProgressStore.saveSnapshots(all: snapshots, activeID: activeProjectID, refs: refs)
    }

    private static func buildSnapshot(for project: Project) -> WidgetSnapshot? {
        guard let stage = project.nextStage,
              let index = project.definition.stages.firstIndex(where: { $0.id == stage.id })
        else { return nil }
        let notes = ArtifactsStore.load(stageKey: stage.id.uuidString).notes
        return WidgetSnapshot(
            projectName: project.definition.name,
            stageTitle: stage.title,
            stageNumber: index + 1,
            stageCount: project.definition.stages.count,
            weight: stage.weight,
            deadline: stage.deadlineDate,
            isDone: project.isStageDone(stage),
            tasks: stage.tasks.map {
                WidgetSnapshot.TaskItem(title: $0.title, done: project.isTaskDone($0.id))
            },
            notes: notes
        )
    }

    // MARK: - Local → iCloud merge (files written before the container resolved)

    static func mergeLocalIntoCloud() {
        guard CloudContainer.isAvailable else { return }
        let localDir = CloudContainer.localFallback.appendingPathComponent("projects", isDirectory: true)
        guard localDir.path != projectsDir.path,
              let contents = try? FileManager.default.contentsOfDirectory(
                  at: localDir, includingPropertiesForKeys: nil) else { return }
        var fullyMerged = true
        for file in contents where file.pathExtension == "json" {
            let dest = projectsDir.appendingPathComponent(file.lastPathComponent)
            if CloudContainer.downloadStatus(dest) == nil {
                _ = CloudContainer.copyIn(from: file, to: dest)
            } else {
                // Cloud already has this project (last writer wins there).
                fullyMerged = fullyMerged && CloudContainer.downloadStatus(dest) != .notDownloaded
            }
        }
        if fullyMerged {
            try? FileManager.default.removeItem(at: localDir)
        }
    }

    // MARK: - One-time migration from the legacy single-pipeline format

    private static let migrationKey = "fyp-migrated-to-projects-v1"

    /// Converts pre-projects data (iCloud-KV checkbox progress, content.json
    /// personalization, per-stage notes/PDFs) into a "Final Year Project"
    /// project file. Uses deterministic UUIDs derived from stage/task indices
    /// so every device migrating independently produces the same file and the
    /// copies converge in iCloud instead of duplicating.
    static func migrateLegacyIfNeeded(allowWithoutCloud: Bool = false) {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        // When signed into iCloud, wait for the container (and the legacy
        // content.json download) so personalized tasks aren't lost. A delayed
        // retry passes allowWithoutCloud=true so users whose iCloud Drive is
        // off still get migrated from local + KV data.
        if !allowWithoutCloud, FileManager.default.ubiquityIdentityToken != nil {
            guard CloudContainer.isAvailable else { return }
            let contentURL = CloudContainer.baseURL.appendingPathComponent("content.json")
            if CloudContainer.downloadStatus(contentURL) == .notDownloaded {
                CloudContainer.ensureDownloaded(contentURL)
                return   // runs again on the next .iCloudFilesChanged
            }
        }

        let legacyProgress = ProgressStore.legacyProgress()
        let legacyConfig = legacyPersonalization()
        let legacyNotes = ProgressStore.legacyNotes()
        let hasLegacyData = !legacyProgress.isEmpty || legacyConfig != nil || !legacyNotes.isEmpty
        guard hasLegacyData else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        var completed: Set<UUID> = []
        let stages: [ProjectStage] = STAGES.enumerated().map { i, s in
            let taskTitles = legacyTasks(for: s, config: legacyConfig)
            let tasks = taskTitles.enumerated().map { j, title in
                ProjectTask(id: deterministicUUID(1000 + i * 100 + j + 1), title: title)
            }
            for (j, task) in tasks.enumerated() where legacyProgress[i]?[j] == true {
                completed.insert(task.id)
            }
            return ProjectStage(id: deterministicUUID(1000 + i * 100),
                                title: s.title, weight: s.weight, deadline: s.real, tasks: tasks)
        }

        var topic: String?
        if let t = legacyConfig?.topic, !t.isEmpty, t != "REPLACE_ME" { topic = t }

        var project = Project(
            id: deterministicUUID(1),
            instructions: aiInstructions,
            definition: ProjectDefinition(name: "Final Year Project", topic: topic, stages: stages)
        )
        project.progress.completedTaskIDs = completed

        // If the other device already migrated and its file synced down,
        // merge progress instead of overwriting.
        if let synced = loadAll().first(where: { $0.id == project.id }) {
            project.progress.completedTaskIDs.formUnion(synced.progress.completedTaskIDs)
            project.definition = synced.definition
        }
        save(project)

        // Move each stage's notes + PDFs from the index-keyed legacy paths
        // to the new UUID-keyed ones (old data is left in place for safety).
        for (i, stage) in stages.enumerated() {
            ArtifactsStore.migrateLegacy(stageIndex: i, stageKey: stage.id.uuidString,
                                         kvNotes: legacyNotes[i])
        }

        activeProjectID = project.id
        UserDefaults.standard.set(true, forKey: migrationKey)
        print("[ProjectTracker] ✅ Migrated legacy pipeline into project \(project.id)")
    }

    /// Fixed-pattern UUIDs so independent migrations on two devices agree.
    private static func deterministicUUID(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "F19B0000-0000-4000-8000-%012d", n))!
    }

    // Minimal reader for the old content.json personalization file.
    private struct LegacyPersonalizedStage: Codable { let id: Int; var tasks: [String] }
    private struct LegacyConfig: Codable {
        var topic: String
        var stages: [LegacyPersonalizedStage]
    }

    private static func legacyPersonalization() -> LegacyConfig? {
        let url = CloudContainer.baseURL.appendingPathComponent("content.json")
        guard let data = CloudContainer.read(at: url) else { return nil }
        return try? JSONDecoder().decode(LegacyConfig.self, from: data)
    }

    private static func legacyTasks(for stage: Stage, config: LegacyConfig?) -> [String] {
        guard let config,
              let match = config.stages.first(where: { $0.id == stage.id }),
              match.tasks.count == stage.tasks.count
        else { return stage.tasks }
        return match.tasks
    }

    // MARK: - JSON coding

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: - Instructions embedded in every project file

    static let aiInstructions = """
    HOW TO TAILOR THIS TRACKER TO YOUR PROJECT
    ==========================================
    1. In the app, open the Projects menu and choose "Export for AI…" to get \
    this file.
    2. Give the file to an AI assistant (Claude, ChatGPT, …) together with a \
    description of YOUR situation: your real milestones or submission steps \
    and their deadlines, how each is weighted (if graded), and what your \
    project is about.
    3. Ask: "Tailor this project tracker file to my project."
    4. Back in the app: Projects menu → "Import Project JSON…" and pick the \
    file the AI returned. Your ticked-off progress is preserved automatically.

    RULES FOR THE AI ASSISTANT
    ==========================
    - Edit ONLY the "definition" section. Never change "progress", "id", \
    "createdAt", or "schemaVersion".
    - "definition.name": a short project name. "definition.topic": a one-line \
    topic description (or null).
    - "definition.stages" is the ordered list of submission steps. Add, \
    remove, rename, and reorder stages freely so they match the project's \
    actual milestones or submission structure — the count is NOT fixed.
    - Each stage has: "title"; "weight" like "15%" for graded/summative steps \
    or null for formative ones; "deadline" as "yyyy-MM-dd" or null if unknown; \
    and "tasks" — between 1 and 8 short, specific, imperative checklist items \
    tailored to this specific project. Task count per stage is NOT fixed.
    - IDs are how the app keeps your progress across edits: KEEP the \
    existing "id" of every stage and task you retain (even when renaming it). \
    Give each NEW stage or task a freshly generated random UUID (version 4).
    - Output the complete JSON file and nothing else — no commentary, no \
    markdown fences.
    """
}
