import Foundation
import SwiftUI

// MARK: - Status

enum StageStatus: String {
    case passed, running, blocked, queued

    /// Single source of truth for status colors — used by both the app
    /// window and the widget, so they can't visually drift apart.
    var color: Color {
        switch self {
        case .passed:  return .green
        case .running: return .yellow
        case .blocked: return .red
        case .queued:  return .blue
        }
    }

    /// Shared status rule for a stage. `deadline == nil` means the stage has
    /// no date pressure — it's simply queued until done.
    static func compute(done: Bool, deadline: Date?, daysEarly: Int, today: Date = Date()) -> StageStatus {
        if done { return .passed }
        guard let deadline else { return .queued }
        let startOfToday = Calendar.current.startOfDay(for: today)
        if deadline < startOfToday { return .blocked }
        let target = Calendar.current.date(byAdding: .day, value: -daysEarly, to: deadline) ?? deadline
        if target <= startOfToday { return .running }
        return .queued
    }
}

/// "due in 12d" / "due today" / "overdue 3d" / "no deadline".
func dueText(for deadline: Date?, from today: Date = Date()) -> String {
    guard let deadline else { return "no deadline" }
    let cal = Calendar.current
    let diff = cal.dateComponents([.day],
                                  from: cal.startOfDay(for: today),
                                  to: cal.startOfDay(for: deadline)).day ?? 0
    if diff < 0 { return "overdue \(abs(diff))d" }
    if diff == 0 { return "due today" }
    return "due in \(diff)d"
}

// MARK: - Project model
//
// One project = one JSON file with two sections that are deliberately kept
// separate: "definition" (the structure — what an AI agent tailors for the
// student) and "progress" (which tasks are ticked). The only link between
// them is stable UUIDs, so renaming a project, stage, or task never loses
// progress. Stage count and per-stage task count are fully variable.

struct ProjectTask: Identifiable, Equatable, Codable {
    var id: UUID
    var title: String

    init(id: UUID = UUID(), title: String) {
        self.id = id
        self.title = title
    }

    // Lenient decoding: accepts {"id": "...", "title": "..."} or a bare
    // string (an AI agent that forgets ids still imports cleanly).
    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer().decode(String.self) {
            self.id = UUID()
            self.title = single
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        self.title = (try? c.decode(String.self, forKey: .title)) ?? "Untitled task"
    }
}

struct ProjectStage: Identifiable, Equatable, Codable {
    var id: UUID
    var title: String
    var weight: String?     // "15%" for graded/summative steps, nil = formative
    var deadline: String?   // "yyyy-MM-dd" or nil — a string keeps the JSON AI-friendly
    var tasks: [ProjectTask]

    init(id: UUID = UUID(), title: String, weight: String? = nil,
         deadline: String? = nil, tasks: [ProjectTask]) {
        self.id = id
        self.title = title
        self.weight = weight
        self.deadline = deadline
        self.tasks = tasks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        self.title = (try? c.decode(String.self, forKey: .title)) ?? "Untitled stage"
        self.weight = try? c.decodeIfPresent(String.self, forKey: .weight)
        self.deadline = try? c.decodeIfPresent(String.self, forKey: .deadline)
        self.tasks = (try? c.decode([ProjectTask].self, forKey: .tasks)) ?? []
    }

    /// Parsed deadline; tolerates full ISO timestamps by using the date part.
    var deadlineDate: Date? {
        guard let deadline, deadline.count >= 10 else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: String(deadline.prefix(10)))
    }

    func targetDate(daysEarly: Int) -> Date? {
        guard let d = deadlineDate else { return nil }
        return Calendar.current.date(byAdding: .day, value: -daysEarly, to: d) ?? d
    }

    func status(done: Bool, daysEarly: Int, today: Date = Date()) -> StageStatus {
        StageStatus.compute(done: done, deadline: deadlineDate, daysEarly: daysEarly, today: today)
    }

    func dueText(from today: Date = Date()) -> String {
        Shared_dueText(deadlineDate, today)
    }

    /// Whole days until the deadline; nil when the stage has no deadline.
    func daysUntilDeadline(from today: Date = Date()) -> Int? {
        guard let d = deadlineDate else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day],
                                  from: cal.startOfDay(for: today),
                                  to: cal.startOfDay(for: d)).day
    }
}

// Small indirection so the method above can call the free function that
// shares its name with the method.
private func Shared_dueText(_ deadline: Date?, _ today: Date) -> String {
    dueText(for: deadline, from: today)
}

struct ProjectDefinition: Codable, Equatable {
    var name: String
    var topic: String?
    var stages: [ProjectStage]

    init(name: String, topic: String? = nil, stages: [ProjectStage]) {
        self.name = name
        self.topic = topic
        self.stages = stages
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = (try? c.decode(String.self, forKey: .name)) ?? "Untitled project"
        self.topic = try? c.decodeIfPresent(String.self, forKey: .topic)
        self.stages = try c.decode([ProjectStage].self, forKey: .stages)
    }
}

struct ProjectProgress: Codable, Equatable {
    var completedTaskIDs: Set<UUID> = []

    init(completedTaskIDs: Set<UUID> = []) {
        self.completedTaskIDs = completedTaskIDs
    }

    init(from decoder: Decoder) throws {
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? c?.decode([String].self, forKey: .completedTaskIDs)) ?? []
        self.completedTaskIDs = Set(raw.compactMap(UUID.init(uuidString:)))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // Sorted for stable diffs across saves.
        try c.encode(completedTaskIDs.map(\.uuidString).sorted(), forKey: .completedTaskIDs)
    }

    private enum CodingKeys: String, CodingKey { case completedTaskIDs }
}

struct Project: Identifiable, Equatable, Codable {
    var schemaVersion: Int = 1
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var instructions: String?           // "_instructions" — read by the AI agent, ignored by the app
    var definition: ProjectDefinition
    var progress: ProjectProgress = ProjectProgress()

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, createdAt, definition, progress
        case instructions = "_instructions"
    }

    init(id: UUID = UUID(), instructions: String? = nil,
         definition: ProjectDefinition, progress: ProjectProgress = ProjectProgress()) {
        self.id = id
        self.instructions = instructions
        self.definition = definition
        self.progress = progress
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = (try? c.decode(Int.self, forKey: .schemaVersion)) ?? 1
        self.id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        self.createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        self.instructions = try? c.decodeIfPresent(String.self, forKey: .instructions)
        self.definition = try c.decode(ProjectDefinition.self, forKey: .definition)
        self.progress = (try? c.decode(ProjectProgress.self, forKey: .progress)) ?? ProjectProgress()
        dedupeIDs()
    }

    /// An AI agent may accidentally duplicate ids when copying stages/tasks.
    /// Progress can only ever follow the first occurrence, so give any
    /// repeated id a fresh one instead of failing the import.
    private mutating func dedupeIDs() {
        var seen: Set<UUID> = []
        for s in definition.stages.indices {
            if !seen.insert(definition.stages[s].id).inserted {
                definition.stages[s].id = UUID()
            }
            for t in definition.stages[s].tasks.indices {
                if !seen.insert(definition.stages[s].tasks[t].id).inserted {
                    definition.stages[s].tasks[t].id = UUID()
                }
            }
        }
    }

    // MARK: Progress helpers

    var allTaskIDs: Set<UUID> {
        Set(definition.stages.flatMap { $0.tasks.map(\.id) })
    }

    func isTaskDone(_ taskID: UUID) -> Bool {
        progress.completedTaskIDs.contains(taskID)
    }

    mutating func setTask(_ taskID: UUID, done: Bool) {
        if done { progress.completedTaskIDs.insert(taskID) }
        else { progress.completedTaskIDs.remove(taskID) }
    }

    func isStageDone(_ stage: ProjectStage) -> Bool {
        !stage.tasks.isEmpty
            && stage.tasks.allSatisfy { progress.completedTaskIDs.contains($0.id) }
    }

    var passedStageCount: Int {
        definition.stages.filter { isStageDone($0) }.count
    }

    /// First not-yet-done stage; falls back to the last stage when all done.
    var nextStage: ProjectStage? {
        definition.stages.first { !isStageDone($0) } ?? definition.stages.last
    }

    func urgentStages(withinDays: Int = 3, today: Date = Date()) -> [ProjectStage] {
        definition.stages.filter { stage in
            guard !isStageDone(stage),
                  let days = stage.daysUntilDeadline(from: today) else { return false }
            return days <= withinDays
        }
    }
}

// MARK: - Legacy model (kept as the built-in template source + for migration)
//
// The original hardcoded FYP pipeline. New projects are created by copying
// this structure into a Project with fresh UUIDs; existing users' progress
// is migrated onto it once with deterministic UUIDs.

struct Stage: Identifiable, Codable, Equatable {
    let id: Int
    let title: String
    let weight: String?      // "15%", "70%", or nil for formative stages
    let real: String         // "yyyy-MM-dd" — the department's real deadline
    let buffer: String       // legacy personal target (superseded by buffer-days setting)
    let tasks: [String]
}

let STAGES: [Stage] = [
    Stage(id: 0, title: "Introduction Chapter", weight: nil,
          real: "2026-07-02", buffer: "2026-07-02",
          tasks: [
            "Get topic + supervisor sign-off locked",
            "Write problem statement + aim & objectives",
            "Draft scope, significance, and expected contribution",
            "Submit (flag it to your supervisor if it's going in late)"
          ]),
    Stage(id: 1, title: "Methodology Chapter", weight: nil,
          real: "2026-07-16", buffer: "2026-07-16",
          tasks: [
            "Lock your research design and high-level approach",
            "Define how you'll evaluate success",
            "Draft the chapter",
            "Submit even if partial, flagged as late if needed"
          ]),
    Stage(id: 2, title: "Literature Review Chapter", weight: nil,
          real: "2026-09-17", buffer: "2026-09-14",
          tasks: [
            "Reach 10–15 targeted, relevant papers",
            "Build a literature review matrix",
            "Derive and write your research gap from the pattern",
            "Send draft to your supervisor before the real deadline"
          ]),
    Stage(id: 3, title: "SRS", weight: nil,
          real: "2026-10-15", buffer: "2026-10-12",
          tasks: [
            "Define functional + non-functional requirements",
            "Justify your feature set with logic + literature evidence",
            "Identify and compare ~5 candidate datasets",
            "Draft a high-level architecture / system diagram"
          ]),
    Stage(id: 4, title: "PPRS — Document + Video", weight: "15%",
          real: "2026-11-19", buffer: "2026-11-16",
          tasks: [
            "Compile PPRS doc: problem, gap, solution, methodology, plan",
            "Script and record the video presentation",
            "Rehearse, get feedback, leave buffer to re-record",
            "Proofread and submit"
          ]),
    Stage(id: 5, title: "Proof of Concept", weight: nil,
          real: "2026-12-17", buffer: "2026-12-14",
          tasks: [
            "Build a minimal working piece of your pipeline/model",
            "Run it against a small sample to test the core idea",
            "Write up the result honestly, including weak spots",
            "Check in with your supervisor before the buffer date"
          ]),
    Stage(id: 6, title: "Design and Prototype", weight: nil,
          real: "2027-01-21", buffer: "2027-01-18",
          tasks: [
            "Finalise the full architecture",
            "Implement the fuller version of your pipeline/model",
            "Test internally on a larger data subset",
            "Document key design decisions and trade-offs"
          ]),
    Stage(id: 7, title: "IPD — Document + Demo", weight: "15%",
          real: "2027-02-11", buffer: "2027-02-08",
          tasks: [
            "Prepare a working demo — not just slides",
            "Write the IPD report to match exactly what the demo shows",
            "Record the video demonstration",
            "Rehearse with buffer time for a re-record"
          ]),
    Stage(id: 8, title: "Testing and Evaluation", weight: nil,
          real: "2027-03-04", buffer: "2027-03-01",
          tasks: [
            "Run the full evaluation with proper metrics",
            "Compare against a baseline or simple ablation",
            "Write limitations honestly",
            "Sanity-check results are reproducible"
          ]),
    Stage(id: 9, title: "First Version — Final Thesis Draft", weight: nil,
          real: "2027-03-18", buffer: "2027-03-15",
          tasks: [
            "Assemble all chapters into one full draft",
            "Consistency pass across chapters",
            "Full supervisor review round",
            "Revise per feedback before the real deadline"
          ]),
    Stage(id: 10, title: "Final Submission", weight: "70%",
          real: "2027-04-01", buffer: "2027-03-29",
          tasks: [
            "Final polish: formatting, referencing, proofreading",
            "Record the final video demonstration",
            "Package source code, test every link and file",
            "Backup everything in two places, then submit"
          ])
]
