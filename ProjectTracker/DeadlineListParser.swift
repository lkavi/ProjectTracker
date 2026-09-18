import Foundation

/// Turns a pasted deadline list into draft stages without any AI: a
/// handbook table, "Stage – date – weight" lines, or bullets. Every line that
/// contains a date becomes a stage; bullet or indented lines beneath it
/// become its tasks; anything else is skipped and counted.
enum DeadlineListParser {
    struct Result: Equatable {
        var stages: [ProjectStage]
        var skippedLines: Int
    }

    static func parse(_ text: String) -> Result {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var stages: [ProjectStage] = []
        var skipped = 0

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let indented = rawLine.hasPrefix("\t") || rawLine.hasPrefix("  ")

            // "due 20 January 2027" makes the detector return today's date, so
            // filler words are removed before detection. Titles are cleaned later.
            let detectLine = line.replacingOccurrences(of: #"(?i)\b(due|deadline)\b"#, with: " ",
                                                       options: .regularExpression)
            let range = NSRange(detectLine.startIndex..., in: detectLine)
            let match = detector?.matches(in: detectLine, options: [], range: range).first { $0.date != nil }

            if let match, let date = match.date, !(indented && !stages.isEmpty && isBullet(line)) {
                var rest = (detectLine as NSString).replacingCharacters(in: match.range, with: " ")
                var weight: String?
                if let w = firstWeight(in: rest) {
                    weight = w.text
                    rest = (rest as NSString).replacingCharacters(in: w.range, with: " ")
                }
                var title = cleanTitle(rest)
                if title.isEmpty { title = "Stage \(stages.count + 1)" }
                stages.append(ProjectStage(title: title, weight: weight,
                                           deadline: formatter.string(from: date), tasks: []))
            } else if (isBullet(line) || indented), var current = stages.popLast() {
                let task = cleanTitle(stripBullet(line))
                if !task.isEmpty { current.tasks.append(ProjectTask(title: task)) }
                stages.append(current)
            } else {
                skipped += 1
            }
        }

        // Chronological, stable for equal dates.
        stages = stages.enumerated()
            .sorted { a, b in
                let da = a.element.deadlineDate ?? .distantFuture
                let db = b.element.deadlineDate ?? .distantFuture
                return da == db ? a.offset < b.offset : da < db
            }
            .map(\.element)

        // The importer and editor require at least one task per stage.
        for i in stages.indices where stages[i].tasks.isEmpty {
            stages[i].tasks = [ProjectTask(title: "Finish \(stages[i].title)")]
        }
        return Result(stages: stages, skippedLines: skipped)
    }

    // MARK: - Pieces

    private static let weightRegex = try! NSRegularExpression(pattern: #"(\d{1,3})\s?%"#)
    private static let bulletRegex = try! NSRegularExpression(pattern: #"^\s*(?:[-–—•*◦·]|\d{1,2}[.)]|[a-z][.)])\s+"#)
    private static let edgeWords = ["due", "deadline", "by", "on", "submit", "submission date", "date"]

    private static func firstWeight(in text: String) -> (text: String, range: NSRange)? {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = weightRegex.firstMatch(in: text, options: [], range: range),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return ("\(text[r])%", m.range)
    }

    static func isBullet(_ line: String) -> Bool {
        bulletRegex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)) != nil
    }

    private static func stripBullet(_ line: String) -> String {
        let range = NSRange(line.startIndex..., in: line)
        return bulletRegex.stringByReplacingMatches(in: line, options: [], range: range, withTemplate: "")
    }

    /// Removes leftover separators and filler words such as "due" or
    /// "deadline" from the edges, then collapses whitespace.
    static func cleanTitle(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "\t", with: " ")
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let edge = CharacterSet(charactersIn: "-–—|:;,•*·()[]").union(.whitespaces)
        var changed = true
        while changed {
            changed = false
            let trimmed = s.trimmingCharacters(in: edge)
            if trimmed != s { s = trimmed; changed = true }
            for word in edgeWords {
                if s.lowercased().hasSuffix(" " + word) {
                    s = String(s.dropLast(word.count)); changed = true
                }
                if s.lowercased().hasPrefix(word + " ") {
                    s = String(s.dropFirst(word.count)); changed = true
                }
            }
        }
        return s
    }
}
