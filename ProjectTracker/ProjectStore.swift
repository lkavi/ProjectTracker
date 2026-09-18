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
        let data: Data
        do {
            data = try encoder.encode(project)
        } catch {
            StorageErrors.shared.report("save the project", error: error)
            return
        }
        CloudContainer.write(data, to: fileURL(for: project.id))
        // Refresh with the just-saved copy so a widget pinned to this project
        // updates even when it isn't the active one.
        refreshWidgetSnapshots(with: project)
    }

    static func delete(_ project: Project) {
        CloudContainer.delete(at: fileURL(for: project.id))
        if activeProjectID == project.id { activeProjectID = nil }
    }

    /// New project from a template, with stage deadlines spread between the
    /// start date and the final deadline. A neutral starting point the user
    /// then edits by hand or tailors with an AI assistant.
    static func create(named name: String,
                       template: ProjectTemplate = .default,
                       start: Date = Date(),
                       end: Date = Calendar.current.date(byAdding: .day, value: 30 * 7, to: Date()) ?? Date()) -> Project {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let project = Project(
            instructions: aiInstructions,
            definition: ProjectDefinition(
                name: trimmed.isEmpty ? "Untitled project" : trimmed,
                topic: nil,
                stages: template.makeStages(start: start, end: end)
            )
        )
        save(project)
        return project
    }

    // MARK: - Prompt for an AI assistant (goes to the clipboard)

    /// A complete, paste-ready prompt: the rules, a place for the user to
    /// describe their situation, and the project file. If it is pasted with
    /// the description still empty, the assistant is told to ask first.
    static func aiPrompt(for project: Project) -> String {
        let json = exportData(project).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return """
        I use the Project Tracker app to track a staged project with deadlines. \
        Below are the rules, my situation, and my current project file (JSON). \
        Tailor the project file to my situation and return the complete updated \
        JSON and nothing else, so I can paste it straight back into the app.

        MY SITUATION
        (Describe the project in a sentence, then list your real stages, \
        milestones or submission steps with their deadlines and any weightings. \
        If this section is still empty, ask me for these details before writing \
        the JSON.)

        \(aiRules)

        PROJECT FILE
        \(json)
        """
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

    /// What an import would do, shown to the user before anything is saved.
    struct ImportSummary {
        let project: Project
        let replacesExisting: Bool
        let stageCount: Int
        let taskCount: Int
        let keptTicks: Int
        let firstDeadline: Date?
        let lastDeadline: Date?
    }

    static func importSummary(from raw: Data) throws -> ImportSummary {
        let project = try importProject(from: raw)
        let deadlines = project.definition.stages.compactMap(\.deadlineDate)
        return ImportSummary(
            project: project,
            replacesExisting: loadAll().contains { $0.id == project.id },
            stageCount: project.definition.stages.count,
            taskCount: project.definition.stages.reduce(0) { $0 + $1.tasks.count },
            keptTicks: project.progress.completedTaskIDs.count,
            firstDeadline: deadlines.min(),
            lastDeadline: deadlines.max())
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

    static var aiInstructions: String { aiHowTo + "\n\n" + aiRules }

    static let aiHowTo = """
    HOW TO TAILOR THIS TRACKER TO YOUR PROJECT
    ==========================================
    1. In the app, open the Project menu and choose "Copy Prompt for AI" \
    (or "Export File…" to get this file on its own).
    2. Paste the prompt into an AI assistant (ChatGPT, Claude, …). Describe \
    your project and list your real stages, deadlines and weightings where it \
    asks.
    3. Copy the JSON the assistant returns.
    4. Back in the app: Project menu → "Import from Clipboard" (or "Import \
    File…"), check the preview, and confirm. Ticked-off progress is kept.
    """

    static let aiRules = """
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
