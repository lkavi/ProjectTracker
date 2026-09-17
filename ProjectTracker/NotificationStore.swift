import Foundation
import UserNotifications

struct StageNotificationPref: Codable, Equatable, Identifiable {
    var id: UUID            // stage id
    var isEnabled: Bool = false
    var hour: Int = 9
    var minute: Int = 0
    // Calendar weekday integers: 1=Sun, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri, 7=Sat
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]   // Mon–Fri default
}

/// Daily reminder preferences, keyed by stage UUID so they survive renames
/// and re-imports. Prefs for every stage ever seen are kept in one dictionary;
/// the settings view shows (and scheduling uses) the active project's stages.
enum NotificationStore {
    private static let key = "fyp-notifications-v2"

    // MARK: - Load / save

    /// Prefs for the given stages — saved values where they exist, defaults otherwise.
    static func load(for stages: [ProjectStage]) -> [StageNotificationPref] {
        let saved = loadMap()
        return stages.map { saved[$0.id] ?? StageNotificationPref(id: $0.id) }
    }

    static func save(_ prefs: [StageNotificationPref], stages: [ProjectStage]) {
        var map = loadMap()
        for p in prefs { map[p.id] = p }
        if let data = try? JSONEncoder().encode(Array(map.values)) {
            UserDefaults.standard.set(data, forKey: key)
        }
        rescheduleAll(prefs, stages: stages)
    }

    private static func loadMap() -> [UUID: StageNotificationPref] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([StageNotificationPref].self, from: data)
        else { return [:] }
        var map: [UUID: StageNotificationPref] = [:]
        for p in saved { map[p.id] = p }
        return map
    }

    // MARK: - Scheduling

    static func rescheduleAll(_ prefs: [StageNotificationPref], stages: [ProjectStage]) {
        let center = UNUserNotificationCenter.current()
        // This app owns every pending request it schedules — clear and re-add.
        center.removeAllPendingNotificationRequests()

        for pref in prefs where pref.isEnabled {
            guard let stage = stages.first(where: { $0.id == pref.id }) else { continue }

            for weekday in pref.weekdays {
                let content = UNMutableNotificationContent()
                content.title = "Project reminder"
                content.body = "Time to work on: \(stage.title)"
                // A repeating request keeps the text it was created with, so use
                // the fixed deadline date rather than a relative "due in Nd".
                content.subtitle = stage.deadlineDate
                    .map { "Deadline \(deadlineFormatter.string(from: $0))" } ?? "No deadline"
                content.sound = .default

                var comps = DateComponents()
                comps.hour = pref.hour
                comps.minute = pref.minute
                comps.weekday = weekday

                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                let request = UNNotificationRequest(
                    identifier: notifID(stageID: pref.id, weekday: weekday),
                    content: content,
                    trigger: trigger
                )
                center.add(request)
            }
        }
    }

    /// Re-creates the pending reminders for the active project's stages from
    /// the saved preferences. Call whenever those stages change (rename,
    /// import, project switch) so titles and dates never go stale.
    static func reschedule(for stages: [ProjectStage]) {
        rescheduleAll(load(for: stages), stages: stages)
    }

    private static let deadlineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    // MARK: - Permission

    static func requestPermission(completion: @escaping (Bool) -> Void = { _ in }) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                DispatchQueue.main.async { completion(granted) }
            }
    }

    static func checkPermission(completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { completion(settings.authorizationStatus) }
        }
    }

    // MARK: - Helpers

    private static func notifID(stageID: UUID, weekday: Int) -> String {
        "fyp-stage-\(stageID.uuidString)-wd\(weekday)"
    }
}
