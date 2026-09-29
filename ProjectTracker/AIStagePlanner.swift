import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Turns a pasted document (a deadline table, a handbook page or a whole
/// email) into stages with real tasks, using Apple's on-device model. Nothing
/// leaves the device.
///
/// The model is kept on a short leash: when `DeadlineListParser` finds dated
/// stages, their titles, dates and weightings are kept exactly and the model
/// only writes tasks for the stages that have none. Only when the parser
/// finds nothing does the model read the stages out of the document itself.
/// The result always goes through the stage review screen before saving.
enum AIStagePlanner {

    enum PlanError: LocalizedError, Equatable {
        case unavailable
        case documentTooLong
        case nothingFound
        case failed

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Apple Intelligence isn't available right now, so the stages were read from your text as it is."
            case .documentTooLong:
                return "That document is too long for Apple Intelligence to read in one go. Paste just the deadlines part and try again."
            case .nothingFound:
                return "No stages with deadlines were found in that text."
            case .failed:
                return "Apple Intelligence couldn't finish, so the stages were read from your text as it is."
            }
        }
    }

    /// True when Apple Intelligence is on and its model is ready on this
    /// device. Always false under UI tests, which need deterministic results.
    static var isAvailable: Bool {
        guard !UITestSupport.isActive else { return false }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    /// A short hint when the device could run the model but it's switched off
    /// or still downloading; nil when there's nothing the user can do.
    static var unavailableHint: String? {
        guard !UITestSupport.isActive else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available, .unavailable(.deviceNotEligible):
                return nil
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Turn on Apple Intelligence in Settings to have tasks written for you."
            case .unavailable(.modelNotReady):
                return "Apple Intelligence is still getting ready on this device. Tasks can be written for you once it's done."
            default:
                return nil
            }
        }
        #endif
        return nil
    }

    /// The on-device model has a small context window; longer documents are
    /// cut (at a line break) before being sent.
    static let maxDocumentCharacters = 8000

    /// How the model is used for a given parser draft.
    enum Mode: Equatable {
        /// The parser found a real deadline list: keep its stages, dates and
        /// weightings exactly and only write tasks.
        case writeTasks
        /// The text is prose (an email or handbook paragraph): the model reads
        /// the stages out of it, and any list-like rows the parser found are
        /// added back so nothing reliable is lost.
        case extract
    }

    /// A parser stage that looks like a row of a deadline list rather than a
    /// sentence that happened to contain a date.
    static func isListLike(_ stage: ProjectStage) -> Bool {
        let title = stage.title.trimmingCharacters(in: .whitespaces)
        let words = title.split(whereSeparator: \.isWhitespace).count
        return words <= 10 && !title.hasSuffix(".")
    }

    static func mode(for draft: [ProjectStage]) -> Mode {
        let listLike = draft.filter(isListLike).count
        return listLike > 0 && listLike * 10 >= draft.count * 7 ? .writeTasks : .extract
    }

    /// Stages for the pasted `document`. `draft` is what the parser found.
    /// `onProgress` reports how many stages are finished while the model writes.
    static func plan(document: String, draft: [ProjectStage],
                     today: Date = Date(),
                     onProgress: (Int) -> Void = { _ in }) async throws -> [ProjectStage] {
        try await run(mode: mode(for: draft), document: document, draft: draft,
                      today: today, onProgress: onProgress)
    }

    /// Writes tasks for exactly these stages (their titles, dates and
    /// weightings are kept), skipping the list-or-prose decision. Used when
    /// updating a project: only the newly added stages need tasks.
    static func writeTasks(for stages: [ProjectStage], document: String,
                           onProgress: (Int) -> Void = { _ in }) async throws -> [ProjectStage] {
        try await run(mode: .writeTasks, document: document, draft: stages,
                      today: Date(), onProgress: onProgress)
    }

    private static func run(mode: Mode, document: String, draft: [ProjectStage],
                            today: Date, onProgress: (Int) -> Void) async throws -> [ProjectStage] {
        if mode == .writeTasks && !draft.contains(where: DeadlineListParser.hasOnlyPlaceholderTask) {
            return draft   // every stage already has the user's own tasks
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else { throw PlanError.unavailable }
            let doc = trimmedDocument(document)
            do {
                switch mode {
                case .extract:
                    let extracted = try await PlannerModel.extractStages(
                        prompt: extractionPrompt(document: doc), onProgress: onProgress)
                    let result = union(stages(from: extracted, today: today), parserStages: draft.filter(isListLike))
                    guard !result.isEmpty else { throw PlanError.nothingFound }
                    return result
                case .writeTasks:
                    let lists = try await PlannerModel.writeTasks(
                        prompt: taskPrompt(for: draft, document: doc), onProgress: onProgress)
                    return merge(draft: draft, taskLists: lists)
                }
            } catch let error as PlanError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw PlannerModel.isContextOverflow(error) ? PlanError.documentTooLong : PlanError.failed
            }
        }
        #endif
        throw PlanError.unavailable
    }

    // MARK: - Prompts

    static let instructions = """
    You turn a student's project brief (an email, a handbook page or a module \
    document) into checklist tasks for each stage of their project. Base a \
    stage's tasks on what the document says that stage must include or \
    submit. When the document says nothing specific about a stage, write the \
    usual steps for that kind of stage in a university project. Never invent \
    deadlines or weightings. Each task is a short imperative phrase of 3 to 10 \
    words about that stage only. Give every stage its own tasks; never repeat \
    a task in another stage. Do not number tasks or repeat the stage title.
    """

    static func taskPrompt(for draft: [ProjectStage], document: String) -> String {
        let list = draft.enumerated().map { i, stage in
            var line = "\(i + 1). \(stage.title)"
            if let deadline = stage.deadline { line += " (due \(deadline))" }
            if let weight = stage.weight { line += " [\(weight)]" }
            return line
        }.joined(separator: "\n")
        return """
        These stages were found in the document:
        \(list)

        Document:
        \"\"\"
        \(document)
        \"\"\"

        For each stage above, in the same order, write 3 or 4 tasks for what the \
        student must do or submit to complete that stage.
        """
    }

    static func extractionPrompt(document: String) -> String {
        """
        Dates may be written in words (for example "the fifteenth of October" \
        is day 15, month 10) or as a week ("the week of 8 March" is day 8, \
        month 3). Give the year only when the document writes it.

        Document:
        \"\"\"
        \(document)
        \"\"\"

        List every submission, milestone or deadline in this document that has a \
        date, including ungraded ones such as a proposal, a viva or an approval, \
        as a stage, earliest first, with 3 or 4 tasks each. Anything with its own \
        date is its own stage, not a task of another stage; a stage whose date \
        is tied to a meeting uses that meeting's date.
        """
    }

    // MARK: - Turning model output into stages (pure, unit-tested)

    struct TaskList: Equatable {
        var title: String
        var tasks: [String]
    }

    /// A stage as the model read it. The date is the text the model copied
    /// ("15 October", "3 December 2026"); it's parsed and its year worked out
    /// here, not by the model, because small models get date maths wrong.
    struct ExtractedStage: Equatable {
        var title: String
        var date: String
        var weight: String
        var tasks: [String]
    }

    /// Gives each placeholder-only stage in `draft` the tasks written for it.
    /// Titles, dates, weightings, and any tasks the user pasted are untouched.
    /// Lists are matched by title first, then by position when counts agree.
    static func merge(draft: [ProjectStage], taskLists: [TaskList]) -> [ProjectStage] {
        var used = Set<Int>()
        return draft.enumerated().map { index, stage in
            guard DeadlineListParser.hasOnlyPlaceholderTask(stage) else { return stage }
            let match: Int? = {
                if index < taskLists.count, !used.contains(index),
                   sameTitle(taskLists[index].title, stage.title) { return index }
                if let i = taskLists.indices.first(where: {
                    !used.contains($0) && sameTitle(taskLists[$0].title, stage.title)
                }) { return i }
                if taskLists.count == draft.count, !used.contains(index) { return index }
                return nil
            }()
            guard let match else { return stage }
            let tasks = cleanTasks(taskLists[match].tasks, stageTitle: stage.title)
            guard !tasks.isEmpty else { return stage }
            used.insert(match)
            var updated = stage
            updated.tasks = tasks.map { ProjectTask(title: $0) }
            return updated
        }
    }

    /// Stages the model read out of a document with no parseable dates:
    /// validated dates and weightings, cleaned tasks, duplicates dropped,
    /// earliest first with undated stages last.
    static func stages(from extracted: [ExtractedStage], today: Date = Date()) -> [ProjectStage] {
        var seen = Set<String>()
        var result: [ProjectStage] = []
        for item in extracted {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let deadline = parseDeadline(item.date, today: today)
            guard seen.insert(title.lowercased() + "|" + (deadline ?? "")).inserted else { continue }
            var tasks = cleanTasks(item.tasks, stageTitle: title)
            if tasks.isEmpty { tasks = [DeadlineListParser.placeholderTaskTitle(for: title)] }
            result.append(ProjectStage(title: title, weight: normalizedWeight(item.weight),
                                       deadline: deadline, tasks: tasks.map { ProjectTask(title: $0) }))
        }
        return result.enumerated()
            .sorted { a, b in
                let da = a.element.deadlineDate ?? .distantFuture
                let db = b.element.deadlineDate ?? .distantFuture
                return da == db ? a.offset < b.offset : da < db
            }
            .map(\.element)
    }

    /// Adds list-like parser stages the model didn't return (matched by date or
    /// title), so a deadline the parser read reliably is never dropped.
    static func union(_ extracted: [ProjectStage], parserStages: [ProjectStage]) -> [ProjectStage] {
        let missing = parserStages.filter { p in
            !extracted.contains { e in
                (p.deadline != nil && e.deadline == p.deadline) || sameTitle(e.title, p.title)
            }
        }
        guard !missing.isEmpty else { return extracted }
        return (extracted + missing).enumerated()
            .sorted { a, b in
                let da = a.element.deadlineDate ?? .distantFuture
                let db = b.element.deadlineDate ?? .distantFuture
                return da == db ? a.offset < b.offset : da < db
            }
            .map(\.element)
    }

    /// Collapses blank-line runs and cuts overly long documents at a line break.
    static func trimmedDocument(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "\r\n", with: "\n")
        s = s.replacingOccurrences(of: #"\n[ \t]*\n(?:[ \t]*\n)+"#, with: "\n\n", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count > maxDocumentCharacters else { return s }
        let cut = s.prefix(maxDocumentCharacters)
        if let lastBreak = cut.lastIndex(of: "\n") { return String(cut[..<lastBreak]) }
        return String(cut)
    }

    // MARK: - Helpers

    private static let posixDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let leadingMarker = try! NSRegularExpression(
        pattern: #"^\s*(?:[-–—•*◦·]|\d{1,2}[.)]|[a-z][.)])\s*"#)

    static func cleanTasks(_ raw: [String], stageTitle: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for task in raw {
            var t = task.trimmingCharacters(in: .whitespacesAndNewlines)
            let range = NSRange(t.startIndex..., in: t)
            t = leadingMarker.stringByReplacingMatches(in: t, options: [], range: range, withTemplate: "")
            t = t.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, t.count <= 140,
                  t.caseInsensitiveCompare(stageTitle) != .orderedSame,
                  seen.insert(t.lowercased()).inserted else { continue }
            out.append(t)
            if out.count == 5 { break }
        }
        return out
    }

    /// Reads the date text the model copied ("15 October", "3rd December 2026",
    /// "the week of 8 March", "2027-04-30") into "yyyy-MM-dd". English month
    /// names only; anything unreadable gives nil (the stage is kept, undated).
    static func parseDeadline(_ text: String, today: Date) -> String? {
        var s = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if let iso = posixDayFormatter.date(from: s) {
            let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: iso)
            return resolveDeadline(day: c.day ?? 0, month: c.month ?? 0, year: c.year ?? 0, today: today)
        }
        s = s.replacingOccurrences(of: #"(\d{1,2})(st|nd|rd|th)\b"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\b(the|week|of|on|by|due|before|thursday|friday|monday|tuesday|wednesday|saturday|sunday)\b"#,
                                   with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: ",", with: " ")
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.isLenient = false
        let cal = Calendar(identifier: .gregorian)
        for (format, hasYear) in [("d MMMM yyyy", true), ("d MMM yyyy", true), ("MMMM d yyyy", true),
                                  ("MMM d yyyy", true), ("d/M/yyyy", true),
                                  ("d MMMM", false), ("d MMM", false), ("MMMM d", false), ("MMM d", false)] {
            f.dateFormat = format
            guard let parsed = f.date(from: s) else { continue }
            let c = cal.dateComponents([.year, .month, .day], from: parsed)
            return resolveDeadline(day: c.day ?? 0, month: c.month ?? 0,
                                   year: hasYear ? (c.year ?? 0) : 0, today: today)
        }
        return nil
    }

    /// "yyyy-MM-dd" for a day and month, using the written year when there is
    /// one and otherwise the next time that date comes round (on or after
    /// today). Impossible dates such as 31 February give nil.
    static func resolveDeadline(day: Int, month: Int, year: Int, today: Date) -> String? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        let cal = Calendar(identifier: .gregorian)
        let startOfToday = cal.startOfDay(for: today)
        let thisYear = cal.component(.year, from: startOfToday)

        func date(in y: Int) -> Date? {
            guard let d = cal.date(from: DateComponents(year: y, month: month, day: day)),
                  cal.component(.month, from: d) == month, cal.component(.day, from: d) == day
            else { return nil }
            return d
        }

        let resolved: Date?
        if year > 0 {
            let y = year < 100 ? 2000 + year : year           // "Apr 27"
            guard abs(y - thisYear) <= 10 else { return nil }
            resolved = date(in: y)
        } else if let d = date(in: thisYear), d >= startOfToday {
            resolved = d
        } else {
            resolved = date(in: thisYear + 1)
        }
        return resolved.map { posixDayFormatter.string(from: $0) }
    }

    static func normalizedWeight(_ raw: String) -> String? {
        guard let match = raw.range(of: #"\d{1,3}(?:\.\d+)?"#, options: .regularExpression),
              let value = Double(raw[match]), value > 0, value <= 100 else { return nil }
        return "\(raw[match])%"
    }

    private static func sameTitle(_ a: String, _ b: String) -> Bool {
        let na = a.lowercased().filter { $0.isLetter || $0.isNumber }
        let nb = b.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !na.isEmpty, !nb.isEmpty else { return false }
        if na == nb { return true }
        guard min(na.count, nb.count) >= 4 else { return false }
        return na.contains(nb) || nb.contains(na)
    }
}

// MARK: - The on-device model

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
nonisolated struct PlannerTaskPlan {
    @Guide(description: "One entry for each stage listed in the prompt, in the same order.")
    var stages: [PlannerStageTasks]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
nonisolated struct PlannerStageTasks {
    @Guide(description: "The stage title, copied exactly from the list in the prompt.")
    var title: String
    @Guide(description: "Short, specific checklist items (imperative, under 12 words each) for this stage, based on what the document says it must include.",
           .count(3...4))
    var tasks: [String]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
nonisolated struct PlannerExtractedPlan {
    @Guide(description: "Every dated submission, milestone or deadline in the document, earliest first.")
    var stages: [PlannerExtractedStage]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
nonisolated struct PlannerExtractedStage {
    @Guide(description: "Short stage name, for example 'Literature Review Chapter'.")
    var title: String
    @Guide(description: "The deadline as day, month name and year, for example '15 October' or '3 December 2026'. Write dates given in words as numbers. Include the year only if the document writes it. Empty if there is no date.")
    var date: String
    @Guide(description: "The weighting such as '15%' when the stage is marked or summative, otherwise an empty string.")
    var weight: String
    @Guide(description: "Short, specific checklist items (imperative, under 12 words each).", .count(3...4))
    var tasks: [String]
}

@available(iOS 26.0, macOS 26.0, *)
private enum PlannerModel {
    /// Greedy sampling: the same document gives the same stages every time.
    private static var options: GenerationOptions { GenerationOptions(samplingMode: .greedy) }

    /// The document didn't fit the model's context window. iOS/macOS 27
    /// report this as `LanguageModelError`; 26 used `GenerationError`.
    static func isContextOverflow(_ error: Error) -> Bool {
        if #available(iOS 27.0, macOS 27.0, *), let error = error as? LanguageModelError {
            if case .contextSizeExceeded = error { return true }
            return false
        }
        if let error = error as? LanguageModelSession.GenerationError,
           case .exceededContextWindowSize = error { return true }
        return false
    }

    /// Streams the reply so the UI can show "5 of 11" while it's written: a
    /// stage counts as done once the model has moved on to the next one.
    static func writeTasks(prompt: String,
                           onProgress: (Int) -> Void) async throws -> [AIStagePlanner.TaskList] {
        let session = LanguageModelSession(instructions: AIStagePlanner.instructions)
        let stream = session.streamResponse(to: prompt, generating: PlannerTaskPlan.self,
                                            includeSchemaInPrompt: true, options: options)
        var latest: PlannerTaskPlan.PartiallyGenerated?
        for try await snapshot in stream {
            try Task.checkCancellation()
            latest = snapshot.content
            onProgress(max(0, (snapshot.content.stages?.count ?? 0) - 1))
        }
        return (latest?.stages ?? []).map { .init(title: $0.title ?? "", tasks: $0.tasks ?? []) }
    }

    static func extractStages(prompt: String,
                              onProgress: (Int) -> Void) async throws -> [AIStagePlanner.ExtractedStage] {
        let session = LanguageModelSession(instructions: AIStagePlanner.instructions)
        let stream = session.streamResponse(to: prompt, generating: PlannerExtractedPlan.self,
                                            includeSchemaInPrompt: true, options: options)
        var latest: PlannerExtractedPlan.PartiallyGenerated?
        for try await snapshot in stream {
            try Task.checkCancellation()
            latest = snapshot.content
            onProgress(max(0, (snapshot.content.stages?.count ?? 0) - 1))
        }
        return (latest?.stages ?? []).map {
            .init(title: $0.title ?? "", date: $0.date ?? "",
                  weight: $0.weight ?? "", tasks: $0.tasks ?? [])
        }
    }
}
#endif
