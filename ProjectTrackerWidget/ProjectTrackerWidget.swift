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
            Image(systemName: "checklist")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Open the app to set up a project")
                .font(.caption)
                .foregroundStyle(.secondary)
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
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 2).fill(status.color).frame(width: 4)
            Group {
                switch family {
                case .systemLarge:  largeBody
                case .systemMedium: mediumBody
                default:            smallBody
                }
            }
            .padding(.leading, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Small

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            projectLabel
            Text(snapshot.stageTitle)
                .font(.headline)
                .lineLimit(3)
            Spacer(minLength: 0)
            dueCapsule
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Medium: stage info on the left, task list on the right

    private var mediumBody: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                projectLabel
                Text(snapshot.stageTitle)
                    .font(.headline)
                    .lineLimit(3)
                Spacer(minLength: 0)
                dueCapsule
                if let target = targetDate {
                    Text("Target \(shortDate(target))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text("Tasks · \(doneCount)/\(snapshot.tasks.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(snapshot.tasks.prefix(4).enumerated()), id: \.offset) { _, task in
                    taskRow(task: task, font: .caption2)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Large

    private var largeBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(snapshot.projectName) · Stage \(snapshot.stageNumber) of \(snapshot.stageCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(snapshot.stageTitle)
                        .font(.title3.bold())
                        .lineLimit(2)
                }
                Spacer(minLength: 6)
                if let weight = snapshot.weight {
                    Text(weight)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                }
            }

            HStack(alignment: .top, spacing: 16) {
                if let deadline = snapshot.deadline {
                    dateColumn(label: "Deadline", date: deadline, color: status.color)
                    if let target = targetDate {
                        dateColumn(label: "Your target", date: target, color: .primary,
                                   suffix: bufferDays > 0 ? "\(bufferDays)d early" : nil)
                    }
                } else {
                    Text("No deadline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                Text("Tasks · \(doneCount) of \(snapshot.tasks.count) done")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(snapshot.tasks.prefix(7).enumerated()), id: \.offset) { _, task in
                    taskRow(task: task, font: .caption)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Notes")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(snapshot.notes.isEmpty ? "No notes yet." : snapshot.notes)
                    .font(.caption)
                    .foregroundStyle(snapshot.notes.isEmpty ? .tertiary : .primary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Pieces

    private var projectLabel: some View {
        Text(snapshot.projectName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var dueCapsule: some View {
        Text(due)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(status == .queued ? Color.primary.opacity(0.06) : status.color.opacity(0.15))
            .foregroundStyle(status == .queued ? AnyShapeStyle(.secondary) : AnyShapeStyle(status.color))
            .clipShape(Capsule())
    }

    private func dateColumn(label: String, date: Date, color: Color, suffix: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(longDate(date))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                if let s = suffix {
                    Text(s)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func taskRow(task: WidgetSnapshot.TaskItem, font: Font) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                .font(font)
                .foregroundStyle(task.done ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
            Text(task.title)
                .font(font)
                .foregroundStyle(task.done ? .secondary : .primary)
                .strikethrough(task.done)
                .lineLimit(2)
        }
    }

    // MARK: - Formatting

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }

    private func longDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - Widget configuration

struct ProjectTrackerWidget: Widget {
    let kind: String = "ProjectTrackerWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: SelectProjectIntent.self,
                               provider: Provider()) { entry in
            ProjectTrackerWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Project Tracker")
        .description("Your next stage with its checklist, deadline and notes. Long-press to pick a project.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Preview

#Preview(as: .systemLarge) {
    ProjectTrackerWidget()
} timeline: {
    StageEntry(date: .now, snapshot: .sample, bufferDays: 3)
}
