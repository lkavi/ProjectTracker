import SwiftUI

/// Add, rename, reorder and delete stages and tasks by hand. Edits a copy
/// and hands the result back on Done; ids are kept, so progress survives.
struct StageEditorView: View {
    @State private var stages: [ProjectStage]
    let onSave: ([ProjectStage]) -> Void
    @Environment(\.dismiss) private var dismiss

    init(stages: [ProjectStage], onSave: @escaping ([ProjectStage]) -> Void) {
        _stages = State(initialValue: stages)
        self.onSave = onSave
    }

    /// Empty task titles are dropped; every stage must keep at least one task.
    private var cleaned: [ProjectStage] {
        stages.map { stage in
            var copy = stage
            copy.title = stage.title.trimmingCharacters(in: .whitespaces)
            if copy.title.isEmpty { copy.title = "Untitled stage" }
            copy.tasks = stage.tasks.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
            return copy
        }
    }

    private var canSave: Bool {
        !cleaned.isEmpty && cleaned.allSatisfy { !$0.tasks.isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($stages) { $stage in
                        NavigationLink {
                            StageDetailEditor(stage: $stage)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stage.title.isEmpty ? "Untitled stage" : stage.title)
                                Text(subtitle(for: stage))
                                    .font(.caption)
                                    .foregroundStyle(stage.tasks.isEmpty ? .red : .secondary)
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                stages.removeAll { $0.id == stage.id }
                            } label: {
                                Label("Delete Stage", systemImage: "trash")
                            }
                        }
                    }
                    .onMove { stages.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { stages.remove(atOffsets: $0) }

                    Button {
                        stages.append(ProjectStage(title: "", tasks: [ProjectTask(title: "")]))
                    } label: {
                        Label("Add Stage", systemImage: "plus")
                    }
                    .accessibilityIdentifier("add-stage-button")
                } footer: {
                    Text("Drag to reorder. Every stage needs at least one task. Ticked tasks keep their progress when renamed or moved.")
                }
            }
            .navigationTitle("Edit Stages")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
                #endif
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(cleaned)
                        dismiss()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("save-stages-button")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 620)
        #endif
    }

    private func subtitle(for stage: ProjectStage) -> String {
        var parts: [String] = []
        parts.append(stage.tasks.isEmpty ? "No tasks yet" : "\(stage.tasks.count) task\(stage.tasks.count == 1 ? "" : "s")")
        if let d = stage.deadlineDate { parts.append(d.formatted(date: .abbreviated, time: .omitted)) }
        if let w = stage.weight { parts.append(w) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - One stage

struct StageDetailEditor: View {
    @Binding var stage: ProjectStage
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var weight: String

    init(stage: Binding<ProjectStage>) {
        _stage = stage
        _hasDeadline = State(initialValue: stage.wrappedValue.deadlineDate != nil)
        _deadline = State(initialValue: stage.wrappedValue.deadlineDate ?? Date())
        _weight = State(initialValue: stage.wrappedValue.weight ?? "")
    }

    var body: some View {
        Form {
            Section("Stage") {
                TextField("Title", text: $stage.title)
                Toggle("Has a deadline", isOn: $hasDeadline)
                if hasDeadline {
                    DatePicker("Deadline", selection: $deadline, displayedComponents: .date)
                }
                TextField("Weighting, e.g. 15% (optional)", text: $weight)
            }

            Section {
                ForEach($stage.tasks) { $task in
                    HStack {
                        TextField("Task", text: $task.title)
                        Button(role: .destructive) {
                            stage.tasks.removeAll { $0.id == task.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Delete task")
                    }
                }
                .onMove { stage.tasks.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { stage.tasks.remove(atOffsets: $0) }

                Button {
                    stage.tasks.append(ProjectTask(title: ""))
                } label: {
                    Label("Add Task", systemImage: "plus")
                }
            } header: {
                Text("Tasks")
            } footer: {
                Text("A stage counts as done when every task is ticked. Keep tasks short and specific.")
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .navigationTitle(stage.title.isEmpty ? "Stage" : stage.title)
        .onChange(of: hasDeadline) { _, on in
            stage.deadline = on ? Self.string(from: deadline) : nil
        }
        .onChange(of: deadline) { _, date in
            if hasDeadline { stage.deadline = Self.string(from: date) }
        }
        .onChange(of: weight) { _, text in
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            stage.weight = trimmed.isEmpty ? nil : trimmed
        }
    }

    private static func string(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}
