import SwiftUI

/// One collapsible stage card: number, title, status line, and when expanded
/// the deadline, task checklist and notes.
struct StageRowView: View {
    let stage: ProjectStage
    let number: Int
    let isDone: Bool
    let completedTaskIDs: Set<UUID>
    let onToggle: (UUID, Bool) -> Void
    let bufferDays: Int
    @Binding var isExpanded: Bool
    var onEdit: (() -> Void)? = nil

    private var status: StageStatus { stage.status(done: isDone, daysEarly: bufferDays) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(number)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(status == .queued ? AnyShapeStyle(.secondary) : AnyShapeStyle(status.color))
                        .frame(width: 22, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(stage.title)
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            StatusBadge(status: status)
                            Text("· \(stage.dueText())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let weight = stage.weight {
                                Text("· \(weight)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .padding(.leading, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appControlBackground)
        .overlay(alignment: .leading) { Rectangle().fill(status.color).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            if let onEdit {
                Button { onEdit() } label: { Label("Edit Stages…", systemImage: "list.bullet") }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isExpanded)
    }

    // MARK: - Expanded content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let deadline = stage.deadlineDate {
                let target = stage.targetDate(daysEarly: bufferDays) ?? deadline
                Text("Deadline \(formatted(deadline))  ·  Your target \(formatted(target))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 34)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(stage.tasks) { task in
                    let done = completedTaskIDs.contains(task.id)
                    Toggle(isOn: Binding(
                        get: { done },
                        set: { onToggle(task.id, $0) }
                    )) {
                        Text(task.title)
                            .font(.subheadline)
                            .strikethrough(done)
                            .foregroundStyle(done ? .secondary : .primary)
                    }
                    .checkboxToggleStyle()
                }
            }
            .padding(.leading, 34)
            .padding(.top, 2)

            StageNotesView(stageKey: stage.id.uuidString)
                .padding(.leading, 34)
        }
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}
