import SwiftUI

/// Name, template and the two dates that stretch the template's deadlines.
struct NewProjectView: View {
    let onCreate: (String, ProjectTemplate, Date, Date) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var template: ProjectTemplate = .default
    @State private var start = Calendar.current.startOfDay(for: Date())
    @State private var end = Calendar.current.date(byAdding: .day, value: 30 * 7, to: Date()) ?? Date()

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && end >= start
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. MSc Dissertation", text: $name)
                        .accessibilityIdentifier("project-name-field")
                }

                Section {
                    ForEach(ProjectTemplate.all) { candidate in
                        Button { template = candidate } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.name).foregroundStyle(.primary)
                                    Text(candidate.summary).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                                    .opacity(candidate == template ? 1 : 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(candidate == template ? .isSelected : [])
                    }
                } header: {
                    Text("Template")
                } footer: {
                    Text("\(template.stages.count) stages to start with. Change anything afterwards, by hand or with an AI assistant.")
                }

                Section {
                    DatePicker("Start", selection: $start, displayedComponents: .date)
                    DatePicker("Final deadline", selection: $end, in: start..., displayedComponents: .date)
                } header: {
                    Text("Dates")
                } footer: {
                    Text("Stage deadlines are spread between these two dates.")
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle("New Project")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(name, template, start, end)
                        dismiss()
                    }
                    .disabled(!canCreate)
                    .accessibilityIdentifier("create-project-button")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 600)
        #endif
    }
}

#Preview {
    NewProjectView { _, _, _, _ in }
}
