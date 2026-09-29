import Foundation

/// Applies a pasted deadline list (or an updated course email) to a project
/// that already has stages, instead of replacing them.
///
/// Pasted stages are matched to existing ones by title. A match keeps the
/// existing stage — its id, title, tasks and ticked progress — and only takes
/// the new deadline and weighting. Pasted stages with no match are added.
/// Existing stages missing from the paste are kept, and flagged so the user
/// can remove them in the review screen if they're really gone.
enum StageUpdater {

    /// Review-list note for an existing stage the pasted text didn't mention.
    static let notInPasteNote = "Not in the pasted text"

    struct Result: Equatable {
        var stages: [ProjectStage]
        var summary: Summary
        /// A short note per changed stage, shown in the review list.
        var notes: [UUID: String]
    }

    struct Summary: Equatable {
        var datesChanged = 0
        var weightsChanged = 0
        var added = 0
        var tasksAdded = 0
        var unchanged = 0
        var notInPaste = 0

        var hasChanges: Bool { datesChanged + weightsChanged + added + tasksAdded > 0 }

        /// e.g. "2 dates moved, 1 new stage. 9 stages unchanged."
        var sentence: String {
            var changes: [String] = []
            if datesChanged > 0 { changes.append("\(datesChanged) date\(datesChanged == 1 ? "" : "s") moved") }
            if weightsChanged > 0 { changes.append("\(weightsChanged) weighting\(weightsChanged == 1 ? "" : "s") changed") }
            if added > 0 { changes.append("\(added) new stage\(added == 1 ? "" : "s")") }
            if tasksAdded > 0 { changes.append("\(tasksAdded) new task\(tasksAdded == 1 ? "" : "s")") }
            var parts: [String] = []
            parts.append(changes.isEmpty ? "No changes found." : changes.joined(separator: ", ").capitalizedFirst + ".")
            if unchanged > 0 { parts.append("\(unchanged) stage\(unchanged == 1 ? "" : "s") unchanged.") }
            if notInPaste > 0 {
                parts.append("\(notInPaste) stage\(notInPaste == 1 ? " isn't" : "s aren't") in the pasted text and will be kept.")
            }
            return parts.joined(separator: " ")
        }
    }

    /// - Parameters:
    ///   - existing: the project's current stages.
    ///   - incoming: stages read from the pasted text (parser or Apple Intelligence).
    ///   - userWrittenTaskStageIDs: incoming stages whose tasks the user typed
    ///     (bullets in the paste). Only those tasks are added to a matched
    ///     stage; placeholder or AI-written tasks never touch an existing stage.
    static func merge(existing: [ProjectStage], incoming: [ProjectStage],
                      userWrittenTaskStageIDs: Set<UUID> = []) -> Result {
        let pairs = match(existing: existing, incoming: incoming)
        var summary = Summary()
        var notes: [UUID: String] = [:]
        var merged = existing

        for (e, i) in pairs {
            var stage = merged[e]
            let new = incoming[i]
            var changed: [String] = []

            if let deadline = new.deadline, deadline != stage.deadline {
                changed.append(stage.deadlineDate.map { "Moved from \(format($0))" } ?? "Deadline added")
                stage.deadline = deadline
                summary.datesChanged += 1
            }
            if let weight = new.weight, weight != stage.weight {
                changed.append(stage.weight.map { "Weighting \($0) → \(weight)" } ?? "Weighting \(weight)")
                stage.weight = weight
                summary.weightsChanged += 1
            }
            if userWrittenTaskStageIDs.contains(new.id) {
                let known = Set(stage.tasks.map { normalized($0.title) })
                let extra = new.tasks.filter { !known.contains(normalized($0.title)) }
                if !extra.isEmpty {
                    stage.tasks += extra.map { ProjectTask(title: $0.title) }
                    summary.tasksAdded += extra.count
                    changed.append("\(extra.count) new task\(extra.count == 1 ? "" : "s")")
                }
            }

            if changed.isEmpty { summary.unchanged += 1 } else { notes[stage.id] = changed.joined(separator: " · ") }
            merged[e] = stage
        }

        let matchedExisting = Set(pairs.map(\.0))
        for (index, stage) in existing.enumerated() where !matchedExisting.contains(index) {
            summary.notInPaste += 1
            notes[stage.id] = notInPasteNote
        }

        let matchedIncoming = Set(pairs.map(\.1))
        let added = incoming.enumerated().filter { !matchedIncoming.contains($0.offset) }.map(\.element)
        for stage in added { notes[stage.id] = "New stage" }
        summary.added = added.count

        return Result(stages: ordered(merged, adding: added), summary: summary, notes: notes)
    }

    /// Pasted stages that don't match any existing one (the ones that would be added).
    static func unmatched(existing: [ProjectStage], incoming: [ProjectStage]) -> [ProjectStage] {
        let matched = Set(match(existing: existing, incoming: incoming).map(\.1))
        return incoming.enumerated().filter { !matched.contains($0.offset) }.map(\.element)
    }

    // MARK: - Matching

    /// Best one-to-one pairs (existing index, incoming index), strongest first.
    static func match(existing: [ProjectStage], incoming: [ProjectStage]) -> [(Int, Int)] {
        var candidates: [(score: Double, e: Int, i: Int)] = []
        for (e, a) in existing.enumerated() {
            for (i, b) in incoming.enumerated() {
                var score = similarity(a.title, b.title)
                guard score >= 0.5 else { continue }
                // Prefer the pairing whose dates are close (a moved deadline).
                if let da = a.deadlineDate, let db = b.deadlineDate,
                   abs(da.timeIntervalSince(db)) <= 45 * 86_400 { score += 0.05 }
                candidates.append((score, e, i))
            }
        }
        var usedE = Set<Int>(), usedI = Set<Int>()
        var pairs: [(Int, Int)] = []
        for c in candidates.sorted(by: { $0.score > $1.score })
        where !usedE.contains(c.e) && !usedI.contains(c.i) {
            usedE.insert(c.e); usedI.insert(c.i)
            pairs.append((c.e, c.i))
        }
        return pairs
    }

    /// 1 for the same title; lower for "SRS" vs "Software Requirements
    /// Specification / SRS" or reworded titles; 0 when numbered stages differ
    /// ("Study Block 1" vs "Study Block 2").
    static func similarity(_ a: String, _ b: String) -> Double {
        let na = normalized(a), nb = normalized(b)
        guard !na.isEmpty, !nb.isEmpty else { return 0 }
        if na == nb { return 1 }

        let ta = tokens(na), tb = tokens(nb)
        let numbersA = ta.filter { $0.allSatisfy(\.isNumber) }
        let numbersB = tb.filter { $0.allSatisfy(\.isNumber) }
        if !numbersA.isEmpty, !numbersB.isEmpty, numbersA != numbersB { return 0 }

        let compactA = na.replacingOccurrences(of: " ", with: "")
        let compactB = nb.replacingOccurrences(of: " ", with: "")
        if min(compactA.count, compactB.count) >= 4,
           compactA.contains(compactB) || compactB.contains(compactA) { return 0.9 }

        let wordsA = ta.subtracting(stopWords), wordsB = tb.subtracting(stopWords)
        guard !wordsA.isEmpty, !wordsB.isEmpty else { return 0 }
        let (small, big) = wordsA.count <= wordsB.count ? (wordsA, wordsB) : (wordsB, wordsA)
        if small.isSubset(of: big) {
            return 0.6 + 0.3 * Double(small.count) / Double(big.count)
        }
        let jaccard = Double(wordsA.intersection(wordsB).count) / Double(wordsA.union(wordsB).count)
        return jaccard >= 0.5 ? 0.5 + 0.3 * jaccard : 0
    }

    // MARK: - Helpers

    private static let stopWords: Set<String> = ["the", "and", "a", "an", "of", "for", "to", "in", "on", "with"]

    static func normalized(_ s: String) -> String {
        s.lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ").joined(separator: " ")
    }

    private static func tokens(_ normalized: String) -> Set<String> {
        Set(normalized.split(separator: " ").map(String.init))
    }

    /// Existing stages keep their order; new ones slot in before the first
    /// later deadline. If the list was in date order before, it stays so after
    /// dates move (undated stages travel with the stage above them).
    private static func ordered(_ existing: [ProjectStage], adding added: [ProjectStage]) -> [ProjectStage] {
        var result = existing
        for stage in added {
            if let date = stage.deadlineDate,
               let at = result.firstIndex(where: { ($0.deadlineDate ?? .distantPast) > date }) {
                result.insert(stage, at: at)
            } else {
                result.append(stage)
            }
        }
        guard isChronological(existing) else { return result }
        var key = Date.distantPast
        let keyed = result.enumerated().map { offset, stage -> (Date, Int, ProjectStage) in
            if let d = stage.deadlineDate { key = d }
            return (key, offset, stage)
        }
        return keyed.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }.map(\.2)
    }

    private static func isChronological(_ stages: [ProjectStage]) -> Bool {
        let dates = stages.compactMap(\.deadlineDate)
        return zip(dates, dates.dropFirst()).allSatisfy { $0 <= $1 }
    }

    private static func format(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
