import WidgetKit
import SwiftUI

struct StageEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let bufferDays: Int
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StageEntry {
        StageEntry(date: Date(), snapshot: .sample, bufferDays: 3)
    }

    func snapshot(for configuration: SelectProjectIntent, in context: Context) async -> StageEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SelectProjectIntent, in context: Context) async -> Timeline<StageEntry> {
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 6, to: Date())
            ?? Date().addingTimeInterval(6 * 3600)
        return Timeline(entries: [entry(for: configuration)], policy: .after(nextRefresh))
    }

    private func entry(for configuration: SelectProjectIntent) -> StageEntry {
        // configuration.project == nil → follow the active project (fallback snapshot).
        StageEntry(date: Date(),
                   snapshot: ProgressStore.loadSnapshot(projectID: configuration.project?.id),
                   bufferDays: ProgressStore.loadBufferDays())
    }
}

// MARK: - Widget view

struct ProjectTrackerWidgetView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                SnapshotView(snapshot: snapshot, bufferDays: entry.bufferDays, family: family)
            } else {
                emptyBody
            }
        }
        .widgetURL(URL(string: "projecttracker://open"))
    }

    private var emptyBody: some View {
        VStack(spacing: 6) {
            Image(systemName: "list.bullet.clipboard")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.5))
            Text("Open the app to set up a project")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SnapshotView: View {
    let snapshot: WidgetSnapshot
    let bufferDays: Int
    let family: WidgetFamily

    private var status: StageStatus {
        StageStatus.compute(done: snapshot.isDone, deadline: snapshot.deadline, daysEarly: bufferDays)
    }
    private var doneCount: Int { snapshot.tasks.filter(\.done).count }
    private var due: String { dueText(for: snapshot.deadline) }
    private var targetDate: Date? {
        guard let d = snapshot.deadline else { return nil }
        return Calendar.current.date(byAdding: .day, value: -bufferDays, to: d)
    }

    var body: some View {
        if family == .systemLarge {
            largeBody
        } else if family == .systemMedium {
            mediumBody
        } else {
            smallBody
        }
    }

    // MARK: Small

    @ViewBuilder
    private var smallBody: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(status.color).frame(width: 4)
            VStack(alignment: .leading, spacing: 5) {
                Text("▶ \(snapshot.projectName.uppercased())")
                    .font(.system(size: 9).monospaced().bold())
                    .foregroundStyle(status.color)
                    .lineLimit(1)
                Text(snapshot.stageTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(4)
                Spacer(minLength: 0)
                Text(due)
                    .font(.system(size: 10).monospaced().bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(status.color.opacity(0.22))
                    .foregroundStyle(status.color)
                    .clipShape(Capsule())
            }
            .padding(12)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Medium — left panel (info) + right panel (tasks)

    @ViewBuilder
    private var mediumBody: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(status.color).frame(width: 4)

            // Left: stage info
            VStack(alignment: .leading, spacing: 5) {
                Text("▶ \(snapshot.projectName.uppercased())")
                    .font(.system(size: 9).monospaced().bold())
                    .foregroundStyle(status.color)
                    .lineLimit(1)
                Text(snapshot.stageTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                Spacer(minLength: 0)
                dateLabels
                if let weight = snapshot.weight {
                    Text("summative · \(weight)")
                        .font(.system(size: 9).monospaced())
                        .foregroundStyle(.purple)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(.white.opacity(0.08)).frame(width: 1)

            // Right: task checklist
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text("TASKS")
                        .font(.system(size: 9).monospaced().bold())
                        .foregroundStyle(.white.opacity(0.4))
                    Text("\(doneCount)/\(snapshot.tasks.count)")
                        .font(.system(size: 9).monospaced())
                        .foregroundStyle(.white.opacity(0.4))
                }
                ForEach(Array(snapshot.tasks.prefix(4).enumerated()), id: \.offset) { _, task in
                    taskRow(task: task, fontSize: 10)
                }
                if !snapshot.notes.isEmpty {
                    Spacer(minLength: 2)
                    Text(snapshot.notes)
                        .font(.system(size: 9).italic())
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(2)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Large — rich full layout

    @ViewBuilder
    private var largeBody: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(status.color).frame(width: 4)

            VStack(alignment: .leading, spacing: 0) {
                // ── Title + dates, grouped together at the top ──
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("▶ \(snapshot.projectName.uppercased())  ·  STAGE \(snapshot.stageNumber) OF \(snapshot.stageCount)")
                                .font(.system(size: 9).monospaced().bold())
                                .foregroundStyle(status.color)
                                .lineLimit(1)
                            Text(snapshot.stageTitle)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 6)
                        if let weight = snapshot.weight {
                            Text(weight)
                                .font(.system(size: 10).monospaced())
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Color.purple.opacity(0.25))
                                .foregroundStyle(.purple)
                                .clipShape(Capsule())
                        }
                    }

                    // ── Dates directly under the stage ──
                    HStack(alignment: .top, spacing: 16) {
                        if let deadline = snapshot.deadline {
                            dateColumn(label: "DEADLINE", date: deadline, color: status.color)
                            if let target = targetDate {
                                dateColumn(label: "YOUR TARGET", date: target,
                                           color: .white.opacity(0.8),
                                           suffix: bufferDays > 0 ? "\(bufferDays)d early" : nil)
                            }
                        } else {
                            Text("no deadline")
                                .font(.system(size: 10).monospaced())
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)

                sectionDivider

                // ── Task checklist ──
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("TASKS")
                            .font(.system(size: 9).monospaced().bold())
                            .foregroundStyle(.white.opacity(0.4))
                        taskDots
                        Text("\(doneCount) / \(snapshot.tasks.count) done")
                            .font(.system(size: 9).monospaced())
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    ForEach(Array(snapshot.tasks.prefix(7).enumerated()), id: \.offset) { _, task in
                        taskRow(task: task, fontSize: 12)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                sectionDivider

                // ── Notes last — expands to fill whatever space is left ──
                VStack(alignment: .leading, spacing: 4) {
                    Text("NOTES")
                        .font(.system(size: 9).monospaced().bold())
                        .foregroundStyle(.white.opacity(0.4))
                    if snapshot.notes.isEmpty {
                        Text("No notes yet — jot progress in the app.")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.3))
                    } else {
                        Text(snapshot.notes)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Shared sub-views

    @ViewBuilder
    private var dateLabels: some View {
        HStack(spacing: 10) {
            if let deadline = snapshot.deadline {
                VStack(alignment: .leading, spacing: 1) {
                    Text("DUE").font(.system(size: 8).monospaced()).foregroundStyle(.white.opacity(0.4))
                    Text(shortDate(deadline)).font(.system(size: 10).monospaced().bold()).foregroundStyle(status.color)
                }
                if let target = targetDate {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("TARGET").font(.system(size: 8).monospaced()).foregroundStyle(.white.opacity(0.4))
                        Text(shortDate(target)).font(.system(size: 10).monospaced()).foregroundStyle(.white.opacity(0.75))
                    }
                }
            } else {
                Text("no deadline")
                    .font(.system(size: 9).monospaced())
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    @ViewBuilder
    private func dateColumn(label: String, date: Date, color: Color, suffix: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8).monospaced())
                .foregroundStyle(.white.opacity(0.4))
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(longDate(date))
                    .font(.system(size: 12, weight: .semibold).monospaced())
                    .foregroundStyle(color)
                if let s = suffix {
                    Text(s)
                        .font(.system(size: 9).monospaced())
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
        }
    }

    @ViewBuilder
    private func taskRow(task: WidgetSnapshot.TaskItem, fontSize: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: task.done ? "checkmark.square.fill" : "square")
                .font(.system(size: fontSize - 1))
                .foregroundStyle(task.done ? .green : .white.opacity(0.4))
            Text(task.title)
                .font(.system(size: fontSize))
                .foregroundStyle(task.done ? .white.opacity(0.3) : .white.opacity(0.9))
                .strikethrough(task.done, color: .white.opacity(0.3))
                .lineLimit(fontSize > 10 ? 2 : 1)
        }
    }

    @ViewBuilder
    private var taskDots: some View {
        HStack(spacing: 3) {
            ForEach(Array(snapshot.tasks.prefix(12).enumerated()), id: \.offset) { _, task in
                Circle()
                    .fill(task.done ? Color.green : Color.white.opacity(0.2))
                    .frame(width: 6, height: 6)
            }
        }
    }

    @ViewBuilder
    private var sectionDivider: some View {
        Rectangle()
            .fill(status.color.opacity(0.18))
            .frame(height: 1)
            .padding(.horizontal, 4)
    }

    // MARK: - Formatting

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private func longDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }
}

// MARK: - Widget configuration

struct ProjectTrackerWidget: Widget {
    let kind: String = "ProjectTrackerWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: SelectProjectIntent.self,
                               provider: Provider()) { entry in
            let status = StageStatus.compute(
                done: entry.snapshot?.isDone ?? false,
                deadline: entry.snapshot?.deadline,
                daysEarly: entry.bufferDays
            )
            ProjectTrackerWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    ZStack {
                        Color(red: 0.10, green: 0.11, blue: 0.14)
                        status.color.opacity(0.14)
                    }
                }
        }
        .configurationDisplayName("Project Tracker")
        .description("Shows your next stage with checklist, deadlines and notes. Long-press to pick a project.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Preview

#Preview(as: .systemLarge) {
    ProjectTrackerWidget()
} timeline: {
    StageEntry(date: .now, snapshot: .sample, bufferDays: 3)
}
