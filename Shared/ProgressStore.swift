import Foundation
import WidgetKit

// MARK: - Widget snapshot
//
// The app owns all project data (iCloud Drive JSON files). The widget can't
// cheaply read/merge those, so on every relevant change the app writes this
// compact snapshot of the active project's next stage into the App Group.

struct WidgetSnapshot: Codable, Equatable {
    struct TaskItem: Codable, Equatable {
        var title: String
        var done: Bool
    }

    var projectName: String
    var stageTitle: String
    var stageNumber: Int        // 1-based position in the pipeline
    var stageCount: Int
    var weight: String?
    var deadline: Date?
    var isDone: Bool
    var tasks: [TaskItem]
    var notes: String

    static let sample = WidgetSnapshot(
        projectName: "Research Project",
        stageTitle: "Literature Review Chapter",
        stageNumber: 3, stageCount: 11,
        weight: nil,
        deadline: Calendar.current.date(byAdding: .day, value: 12, to: Date()),
        isDone: false,
        tasks: [
            TaskItem(title: "Reach 10–15 targeted, relevant papers", done: true),
            TaskItem(title: "Build a literature review matrix", done: false),
            TaskItem(title: "Derive and write your research gap", done: false),
            TaskItem(title: "Send draft to your supervisor", done: false),
        ],
        notes: "Found 12 papers so far. Building the matrix this week."
    )
}

// MARK: - Store

/// A project the widget can be pinned to — id + display name, shown in the
/// widget's "Select Project" picker.
struct ProjectRef: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
}

/// Small cross-process settings store: the buffer-days preference (synced via
/// iCloud KV) and the widget snapshots (App Group). Project structure and
/// progress live in ProjectStore's iCloud Drive files, not here.
enum ProgressStore {
    /// Registered App Group shared by the app and the widget. Kept from the
    /// app's original identifier (see CloudContainer.containerID). A fork must
    /// register its own group and change this plus both .entitlements files.
    static let appGroupID    = "group.lkavi.fyppipeline"
    static let bufferDaysKey = "fyp-buffer-days-v1"
    static let snapshotKey    = "fyp-widget-snapshot-v1"   // active project (fallback)
    static let snapshotsKey   = "fyp-widget-snapshots-v1"  // [projectID: snapshot], all projects
    static let projectRefsKey = "fyp-widget-projects-v1"   // [ProjectRef] for the picker

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    // MARK: Buffer days ("finish N days early" target)

    static func saveBufferDays(_ days: Int) {
        defaults?.set(days, forKey: bufferDaysKey)
        NSUbiquitousKeyValueStore.default.set(Int64(days), forKey: bufferDaysKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func loadBufferDays() -> Int {
        if NSUbiquitousKeyValueStore.default.object(forKey: bufferDaysKey) != nil {
            let days = Int(NSUbiquitousKeyValueStore.default.longLong(forKey: bufferDaysKey))
            defaults?.set(days, forKey: bufferDaysKey)
            return days
        }
        guard let val = defaults?.object(forKey: bufferDaysKey) as? Int else { return 3 }
        NSUbiquitousKeyValueStore.default.set(Int64(val), forKey: bufferDaysKey)
        return val
    }

    // MARK: Widget snapshots

    /// Stores a snapshot for every project (so a widget pinned to any project
    /// stays current), the active project's snapshot as the fallback, and the
    /// project list the widget's picker offers.
    static func saveSnapshots(all: [UUID: WidgetSnapshot], activeID: UUID?, refs: [ProjectRef]) {
        var byString: [String: WidgetSnapshot] = [:]
        for (id, snap) in all { byString[id.uuidString] = snap }
        if let data = try? JSONEncoder().encode(byString) {
            defaults?.set(data, forKey: snapshotsKey)
        }
        if let activeID, let active = all[activeID], let data = try? JSONEncoder().encode(active) {
            defaults?.set(data, forKey: snapshotKey)
        } else {
            defaults?.removeObject(forKey: snapshotKey)
        }
        if let data = try? JSONEncoder().encode(refs) {
            defaults?.set(data, forKey: projectRefsKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Snapshot for a specific pinned project, or the active project when
    /// `projectID` is nil (widget set to "Active Project") or the pinned
    /// project no longer exists.
    static func loadSnapshot(projectID: UUID? = nil) -> WidgetSnapshot? {
        if let projectID,
           let data = defaults?.data(forKey: snapshotsKey),
           let dict = try? JSONDecoder().decode([String: WidgetSnapshot].self, from: data),
           let snap = dict[projectID.uuidString] {
            return snap
        }
        guard let data = defaults?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Projects available to the widget's picker.
    static func loadProjectRefs() -> [ProjectRef] {
        guard let data = defaults?.data(forKey: projectRefsKey),
              let refs = try? JSONDecoder().decode([ProjectRef].self, from: data) else { return [] }
        return refs
    }

    // MARK: Legacy data (read once by ProjectStore's migration)

    static let legacyProgressKey = "fyp-progress-v1"
    static let legacyNotesKey    = "fyp-stage-notes-v1"

    /// Old checkbox progress: [stageIndex: [taskIndex: checked]].
    static func legacyProgress() -> [Int: [Int: Bool]] {
        let data = NSUbiquitousKeyValueStore.default.data(forKey: legacyProgressKey)
            ?? defaults?.data(forKey: legacyProgressKey)
        guard let data,
              let decoded = try? JSONDecoder().decode([String: [String: Bool]].self, from: data)
        else { return [:] }
        var result: [Int: [Int: Bool]] = [:]
        for (stageKey, tasks) in decoded {
            guard let stageId = Int(stageKey) else { continue }
            var inner: [Int: Bool] = [:]
            for (taskKey, value) in tasks {
                if let taskIndex = Int(taskKey) { inner[taskIndex] = value }
            }
            result[stageId] = inner
        }
        return result
    }

    /// Old per-stage notes: [stageIndex: text].
    static func legacyNotes() -> [Int: String] {
        let data = NSUbiquitousKeyValueStore.default.data(forKey: legacyNotesKey)
            ?? defaults?.data(forKey: legacyNotesKey)
        guard let data,
              let raw = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        var result: [Int: String] = [:]
        for (k, v) in raw { if let id = Int(k) { result[id] = v } }
        return result
    }
}
