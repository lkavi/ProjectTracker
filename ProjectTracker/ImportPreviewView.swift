import SwiftUI

/// Shows what an import will do before anything is written.
struct ImportPreviewView: View {
    let summary: ProjectStore.ImportSummary
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Project", value: summary.project.definition.name)
                    if let topic = summary.project.definition.topic, !topic.isEmpty {
                        LabeledContent("Topic", value: topic)
                    }
                    LabeledContent("Stages", value: "\(summary.stageCount)")
                    LabeledContent("Tasks", value: "\(summary.taskCount)")
                    if let first = summary.firstDeadline, let last = summary.lastDeadline {
                        LabeledContent("Deadlines",
                                       value: "\(first.formatted(date: .abbreviated, time: .omitted)) to \(last.formatted(date: .abbreviated, time: .omitted))")
                    }
                    LabeledContent("Ticked tasks kept", value: "\(summary.keptTicks)")
                } footer: {
                    Text(summary.replacesExisting
                         ? "This replaces the stages of your existing project with the same ID. Progress on tasks that still exist is kept."
                         : "This is added as a new project.")
                }

                Section("Stages") {
                    ForEach(summary.project.definition.stages) { stage in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stage.title)
                            Text(detail(for: stage))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Import Project")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(summary.replacesExisting ? "Replace" : "Import") {
                        onConfirm()
                        dismiss()
                    }
                    .accessibilityIdentifier("confirm-import-button")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 520)
        #endif
    }

    private func detail(for stage: ProjectStage) -> String {
        var parts = ["\(stage.tasks.count) task\(stage.tasks.count == 1 ? "" : "s")"]
        if let d = stage.deadlineDate { parts.append(d.formatted(date: .abbreviated, time: .omitted)) }
        if let w = stage.weight { parts.append(w) }
        return parts.joined(separator: " · ")
    }
}
