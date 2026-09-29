import SwiftUI

/// Paste a deadline table, a handbook page or a whole email; see how many
/// stages were found, optionally let Apple Intelligence (on-device) write the
/// tasks, then tidy the draft in the stage editor before saving it.
///
/// On a project that already has stages the paste is an *update* by default:
/// matching stages take the new dates and weightings but keep their tasks and
/// ticks, new stages are added, and nothing is deleted (see `StageUpdater`).
struct PasteDeadlinesView: View {
    /// Creating a new project from the paste (shows a name field) instead of
    /// changing the current project's stages.
    var createsProject = false
    /// The current project's stages, which the paste updates or replaces.
    var existingStages: [ProjectStage] = []
    /// Called with the raw text when what was pasted is a project file (JSON),
    /// e.g. the reply from an AI assistant. Nil hides that option.
    var onImportProjectFile: ((String) -> Void)? = nil
    /// Project name (only used when `createsProject`) and the reviewed stages.
    let onSave: (String, [ProjectStage]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var result: DeadlineListParser.Result
    @State private var projectName = ""
    @State private var stages: [ProjectStage] = []
    @State private var reviewNotes: [UUID: String] = [:]
    @State private var reviewing = false
    @State private var updateExisting = true
    @State private var useAI = true
    @State private var planning = false
    @State private var stagesDone = 0
    @State private var progressTotal = 0
    @State private var planTask: Task<Void, Never>?
    @State private var aiNote: String?

    private let aiAvailable = AIStagePlanner.isAvailable
    private let aiHint = AIStagePlanner.unavailableHint

    /// - Parameter updatesByDefault: start in "Update stages". False right
    ///   after creating from a template, whose placeholder stages should be
    ///   replaced rather than merged into.
    init(createsProject: Bool = false,
         existingStages: [ProjectStage] = [],
         updatesByDefault: Bool = true,
         initialText: String = "",
         onImportProjectFile: ((String) -> Void)? = nil,
         onSave: @escaping (String, [ProjectStage]) -> Void) {
        self.createsProject = createsProject
        self.existingStages = existingStages
        self.onImportProjectFile = onImportProjectFile
        self.onSave = onSave
        _text = State(initialValue: initialText)
        _result = State(initialValue: DeadlineListParser.parse(initialText))
        _updateExisting = State(initialValue: updatesByDefault)
    }

    /// There are stages the paste could update instead of replace.
    private var canUpdate: Bool { !createsProject && !existingStages.isEmpty }
    private var isUpdate: Bool { canUpdate && updateExisting }

    /// Tasks the user typed as bullets in the paste (never placeholders or AI).
    private func userWrittenTaskStageIDs(in draft: [ProjectStage]) -> Set<UUID> {
        Set(draft.filter { !DeadlineListParser.hasOnlyPlaceholderTask($0) }.map(\.id))
    }

    private let example = """
    Literature review – 17 Oct 2026 – 15%
    Methodology chapter – 21 Nov 2026
    • Choose methods
    • Ethics form
    Final report – 15 Apr 2027 – 70%
    """

    /// Looks like a project file rather than a deadline list.
    private var looksLikeProjectFile: Bool {
        onImportProjectFile != nil && text.contains("\"definition\"") && text.contains("{")
    }

    private var willUseAI: Bool { aiAvailable && useAI }

    private var canReview: Bool {
        guard !planning, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return !result.stages.isEmpty || willUseAI
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if createsProject {
                        TextField("Project name, e.g. Final Year Project", text: $projectName)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("paste-project-name-field")
                    }

                    if canUpdate {
                        Picker("What the paste does", selection: $updateExisting) {
                            Text("Update stages").tag(true)
                            Text("Replace all").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .accessibilityIdentifier("paste-mode-picker")
                    }

                    Text(isUpdate
                         ? "Paste the new deadlines email or list. Matching stages get the new dates and keep your tasks and ticks; new stages are added."
                         : "Paste your deadlines email, a handbook page or a deadline table. Every line with a date becomes a stage; bullet points under a line become its tasks.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    editor

                    HStack(alignment: .firstTextBaseline) {
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(result.stages.isEmpty ? .secondary : .primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("deadline-list-summary")
                        Spacer(minLength: 8)
                        PasteButton(payloadType: String.self) { strings in
                            if let pasted = strings.first { text = pasted }
                        }
                        .labelStyle(.titleAndIcon)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                    }

                    if looksLikeProjectFile, let onImportProjectFile {
                        Button {
                            let raw = text
                            dismiss()
                            onImportProjectFile(raw)
                        } label: {
                            Label("This looks like a project file. Import it instead", systemImage: "square.and.arrow.down")
                                .font(.subheadline.weight(.semibold))
                        }
                        .accessibilityIdentifier("paste-import-project-file-button")
                    }

                    aiSection
                }
                .padding()
            }
            .navigationTitle(createsProject ? "New Project" : (isUpdate ? "Update Deadlines" : "Paste Deadlines"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onChange(of: text) { _, newValue in
                result = DeadlineListParser.parse(newValue)
                aiNote = nil
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        planTask?.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Review") { review() }
                        .disabled(!canReview)
                        .accessibilityIdentifier("review-stages-button")
                }
            }
            .navigationDestination(isPresented: $reviewing) {
                StageListEditor(stages: $stages, notes: reviewNotes)
                    .navigationTitle("Review Stages")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(createsProject ? "Create" : (isUpdate ? "Update" : "Done")) {
                                onSave(projectName, StageListEditor.cleaned(stages))
                                dismiss()
                            }
                            .disabled(!StageListEditor.isValid(stages))
                            .accessibilityIdentifier("save-stages-button")
                        }
                    }
            }
            .overlay {
                if planning { planningOverlay }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 600)
        #endif
    }

    // MARK: - Pieces

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(example)
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(4)
                .accessibilityIdentifier("deadline-list-field")
        }
        .frame(minHeight: 220, maxHeight: 360)
        .background(Color.appTextBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Color.primary.opacity(0.1), lineWidth: 1))
    }

    @ViewBuilder
    private var aiSection: some View {
        if aiAvailable {
            Toggle(isOn: $useAI) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Write tasks with Apple Intelligence")
                        .font(.subheadline.weight(.semibold))
                    Text("Runs on this device. Dates and weightings still come from your text.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .card()
            .accessibilityIdentifier("paste-ai-toggle")
        } else if let aiHint {
            Label(aiHint, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if let aiNote {
            Label(aiNote, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("paste-ai-note")
        }
    }

    private var planningOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 14) {
                let total = progressTotal
                if total > 0 {
                    ProgressView(value: Double(min(stagesDone, total)), total: Double(total))
                        .frame(width: 180)
                    Text("Writing tasks… \(min(stagesDone, total)) of \(total) stages")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                } else {
                    ProgressView()
                        .controlSize(.large)
                    Text(stagesDone > 0 ? "Reading your document… \(stagesDone) stages so far"
                                        : "Reading your document…")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                Text("Apple Intelligence · on this device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Cancel") {
                    planTask?.cancel()
                    planning = false
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(24)
            .frame(maxWidth: 300)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var summary: String {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Nothing pasted yet."
        }
        let r = result
        let replaceNote = createsProject || isUpdate ? nil : "This replaces the current stages; you can tidy them first."
        if willUseAI && AIStagePlanner.mode(for: r.stages) == .extract {
            let read = "This reads like an email or document. Apple Intelligence will pick out the stages and dates"
            return isUpdate ? read + " and update the matching ones." : [read + ".", replaceNote].compactMap { $0 }.joined(separator: " ")
        }
        if r.stages.isEmpty { return "No lines with a date found." }
        if isUpdate {
            // A live preview of the update, before anything is saved.
            let preview = StageUpdater.merge(existing: existingStages, incoming: r.stages,
                                             userWrittenTaskStageIDs: userWrittenTaskStageIDs(in: r.stages))
            return "Found \(r.stages.count) stage\(r.stages.count == 1 ? "" : "s") with dates. " + preview.summary.sentence
        }
        var parts = ["Found \(r.stages.count) stage\(r.stages.count == 1 ? "" : "s") with dates."]
        if r.skippedLines > 0 {
            parts.append("\(r.skippedLines) other line\(r.skippedLines == 1 ? "" : "s") ignored.")
        }
        if let replaceNote { parts.append(replaceNote) }
        return parts.joined(separator: " ")
    }

    // MARK: - Actions

    private func review() {
        let draft = result.stages
        let document = text
        let userWritten = userWrittenTaskStageIDs(in: draft)
        let mode = AIStagePlanner.mode(for: draft)
        let updatingList = isUpdate && mode == .writeTasks

        // What, if anything, Apple Intelligence is asked about. When updating a
        // list, only the new stages need tasks: a dates-only update skips the
        // model entirely.
        let aiStages: [ProjectStage]? = {
            guard willUseAI else { return nil }
            guard updatingList else { return draft }
            let new = StageUpdater.unmatched(existing: existingStages, incoming: draft)
            return new.contains(where: DeadlineListParser.hasOnlyPlaceholderTask) ? new : nil
        }()
        guard let aiStages else {
            show(draft, userWritten: userWritten)
            return
        }

        aiNote = nil
        stagesDone = 0
        progressTotal = updatingList ? aiStages.count : (mode == .writeTasks ? draft.count : 0)
        planning = true
        planTask = Task {
            var incoming = draft
            var written = userWritten
            do {
                let progress: (Int) -> Void = { done in if done > stagesDone { stagesDone = done } }
                if updatingList {
                    let planned = try await AIStagePlanner.writeTasks(for: aiStages, document: document,
                                                                      onProgress: progress)
                    let byID = Dictionary(uniqueKeysWithValues: planned.map { ($0.id, $0) })
                    incoming = draft.map { byID[$0.id] ?? $0 }
                } else {
                    incoming = try await AIStagePlanner.plan(document: document, draft: draft,
                                                             onProgress: progress)
                    // Stages the model read out of prose are new objects; none
                    // of their tasks are the user's own.
                    if mode == .extract { written = [] }
                }
            } catch is CancellationError {
                return
            } catch {
                aiNote = (error as? LocalizedError)?.errorDescription
                    ?? AIStagePlanner.PlanError.failed.errorDescription
                planning = false
                if draft.isEmpty { return }   // nothing to fall back to
                show(draft, userWritten: userWritten)
                return
            }
            guard !Task.isCancelled else { return }
            planning = false
            show(incoming, userWritten: written)
        }
    }

    /// Opens the review list: the pasted stages as they are, or merged into
    /// the existing ones (with a note on what changed) when updating.
    private func show(_ incoming: [ProjectStage], userWritten: Set<UUID>) {
        if isUpdate {
            let merged = StageUpdater.merge(existing: existingStages, incoming: incoming,
                                            userWrittenTaskStageIDs: userWritten)
            stages = merged.stages
            reviewNotes = merged.notes
        } else {
            stages = incoming
            reviewNotes = [:]
        }
        reviewing = true
    }
}

#Preview {
    PasteDeadlinesView(createsProject: true) { _, _ in }
}
