import SwiftUI

struct StageRowView: View {
    let stage: ProjectStage
    let number: Int
    let isDone: Bool
    let completedTaskIDs: Set<UUID>
    let onToggle: (UUID, Bool) -> Void
    let bufferDays: Int
    @Binding var isExpanded: Bool

    private var status: StageStatus { stage.status(done: isDone, daysEarly: bufferDays) }

    var body: some View {
        Group {
            #if os(iOS)
            iosBody
            #else
            macBody
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appControlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .animation(.easeInOut(duration: 0.15), value: isExpanded)
    }

    // MARK: - iOS: slim colour bar + inline number, content flush left

    #if os(iOS)
    private var iosBody: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(status.color).frame(width: 3)

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(format: "%02d", number))
                            .font(.system(.footnote, design: .monospaced).weight(.bold))
                            .foregroundStyle(status.color)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(stage.title)
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            HStack(spacing: 5) {
                                Text(status.rawValue)
                                    .font(.appLabelBold)
                                    .foregroundStyle(status.color)
                                Text("· \(stage.dueText())")
                                    .font(.appMeta)
                                    .foregroundStyle(.secondary)
                                if let weight = stage.weight {
                                    Text("· \(weight)")
                                        .font(.appMeta)
                                        .foregroundStyle(.purple)
                                }
                            }
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
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
            .padding(10)
        }
    }
    #endif

    // MARK: - macOS: numbered gutter design

    #if os(macOS)
    private var macBody: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack {
                Text(String(format: "%02d", number))
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(status.color)
            }
            .frame(width: 56)
            .padding(.vertical, 14)
            .background(status.color.opacity(0.08))

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(stage.title)
                                .font(.title3.bold())
                                .foregroundStyle(.primary)
                            if let weight = stage.weight {
                                Text("summative · \(weight)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.purple)
                            } else {
                                Text("formative")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(status.rawValue)
                                .font(.caption.monospaced().bold())
                                .foregroundStyle(status.color)
                            Text(stage.dueText())
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .padding(.leading, 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    expandedContent
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    #endif

    // MARK: - Shared expanded content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let deadline = stage.deadlineDate {
                let target = stage.targetDate(daysEarly: bufferDays) ?? deadline
                Text("deadline: \(formatted(deadline))   ·   your target: \(formatted(target))")
                    .font(.appMeta)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(stage.tasks) { task in
                    let done = completedTaskIDs.contains(task.id)
                    Toggle(isOn: Binding(
                        get: { done },
                        set: { onToggle(task.id, $0) }
                    )) {
                        Text(task.title)
                            #if os(iOS)
                            .font(.subheadline)
                            #else
                            .font(.body)
                            #endif
                            .strikethrough(done)
                            .foregroundStyle(done ? .secondary : .primary)
                    }
                    .checkboxToggleStyle()
                }
            }
            .padding(.top, 2)

            StageNotesView(stageKey: stage.id.uuidString)
        }
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }
}
