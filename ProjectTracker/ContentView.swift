import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

enum AppTab: Hashable {
    case pipeline, library
}

extension ProjectStore.ImportSummary: Identifiable {
    var id: UUID { project.id }
}

// MARK: - iOS share sheet wrapper

#if os(iOS)
import UIKit
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - Main content view

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = UITestSupport.initialTab ?? .pipeline

    // Projects
    @State private var projects: [Project] = []
    @State private var activeID: UUID?
    @State private var expandedStages: Set<UUID> = []
    @State private var bufferDays: Int = ProgressStore.loadBufferDays()
    @State private var hasLoaded = false

    // Sheets & alerts
    @State private var showNewProject = false
    @State private var showSetupGuide = false
    @State private var showStageEditor = false
    @State private var editingStage: ProjectStage?
    /// Set to open the paste sheet; says whether it starts in update or replace mode.
    @State private var pasteMode: PasteMode?
    @State private var showPasteNewProject = false
    @State private var pendingImport: ProjectStore.ImportSummary?
    @State private var inboxItem: URL?
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showDeleteConfirm = false
    @State private var showResetConfirm = false
    @State private var resetConfirmText = ""
    @State private var importError: String?
    @State private var showImporter = false
    @State private var showNotificationSettings = false
    @State private var infoMessage: String?
    @State private var storageErrors = StorageErrors.shared
    #if os(iOS)
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    #endif

    private static let expandedStorageKey = "fyp-expanded-stages-v2"

    private var active: Project? {
        projects.first { $0.id == activeID } ?? projects.first
    }

    var body: some View {
        tabContent
            .alert("Clear all ticked tasks?", isPresented: $showResetConfirm) {
                TextField("Type CONFIRM", text: $resetConfirmText)
                Button("Cancel", role: .cancel) { resetConfirmText = "" }
                Button("Reset", role: .destructive) {
                    if resetConfirmText == "CONFIRM" {
                        mutateActive { $0.progress.completedTaskIDs = [] }
                    }
                    resetConfirmText = ""
                }
                .disabled(resetConfirmText != "CONFIRM")
            } message: {
                Text("This clears every ticked task in \"\(active?.definition.name ?? "this project")\". It can't be undone. Type CONFIRM (all caps) to proceed.")
            }
            .alert("Rename Project", isPresented: $showRename) {
                TextField("Project name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    mutateActive { $0.definition.name = trimmed }
                }
            }
            .alert("Delete \"\(active?.definition.name ?? "project")\"?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { deleteActiveProject() }
            } message: {
                Text("The project structure and progress are removed. Attached PDFs and notes stay in iCloud Drive.")
            }
            .alert("Couldn't import",
                   isPresented: .constant(importError != nil), presenting: importError) { _ in
                Button("OK") { importError = nil }
            } message: { msg in Text(msg) }
            .alert("Couldn't save",
                   isPresented: Binding(get: { storageErrors.pending != nil },
                                        set: { if !$0 { storageErrors.pending = nil } }),
                   presenting: storageErrors.pending) { _ in
                Button("OK") { storageErrors.pending = nil }
            } message: { failure in Text(failure.message) }
            .sheet(isPresented: $showNotificationSettings, onDismiss: {
                bufferDays = ProgressStore.loadBufferDays()
                ProjectStore.refreshWidgetSnapshots()
            }) {
                NotificationSettingsView(stages: active?.definition.stages ?? [],
                                         doneStageIDs: Set((active?.definition.stages ?? [])
                                             .filter { active?.isStageDone($0) == true }.map(\.id)))
            }
            .sheet(isPresented: $showNewProject) {
                NewProjectView(onPasteInstead: { afterDismissal { showPasteNewProject = true } }) { name, template, start, end in
                    createProject(named: name, template: template, start: start, end: end)
                }
            }
            .sheet(isPresented: $showSetupGuide) {
                SetupGuideView(
                    projectName: active?.definition.name ?? "your project",
                    onCopyPrompt: { copyPrompt() },
                    onImportClipboard: { afterDismissal { importFromClipboard() } },
                    onPasteDeadlines: { afterDismissal { pasteMode = .replace } },
                    onEditStages: { afterDismissal { showStageEditor = true } }
                )
            }
            .sheet(isPresented: $showStageEditor) {
                if let project = active {
                    StageEditorView(stages: project.definition.stages) { applyStages($0) }
                }
            }
            .sheet(item: $editingStage) { stage in
                SingleStageEditorView(stage: stage,
                                      onSave: { replaceStage($0) },
                                      onDelete: { removeStage(stage.id) })
            }
            .sheet(item: $pasteMode) { mode in
                PasteDeadlinesView(existingStages: active?.definition.stages ?? [],
                                   updatesByDefault: mode == .update,
                                   onImportProjectFile: importPastedProjectFile) { _, stages in
                    applyStages(stages)
                }
            }
            .sheet(isPresented: $showPasteNewProject) {
                PasteDeadlinesView(createsProject: true, onImportProjectFile: importPastedProjectFile) { name, stages in
                    createProject(named: name, stages: stages)
                }
            }
            .sheet(item: $pendingImport, onDismiss: { finishInboxItem() }) { summary in
                ImportPreviewView(summary: summary) { commitImport(summary.project) }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json, .plainText]) { result in
                guard let url = try? result.get() else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                importProject(from: url)
            }
            .onOpenURL { url in
                // Files handed over by Files, Mail, Finder or another app.
                // The widget's projecttracker:// link just opens the app.
                guard url.isFileURL else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                importProject(from: url)
            }
            .overlay(alignment: .bottom) {
                if let infoMessage {
                    Text(infoMessage)
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.regularMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 70)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .accessibilityIdentifier("info-message")
                }
            }
            .animation(.easeInOut(duration: 0.2), value: infoMessage)
            #if os(iOS)
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: shareItems)
            }
            #endif
    }

    // MARK: - Tab container

    @ViewBuilder
    private var tabContent: some View {
        #if os(macOS)
        TabView(selection: $selectedTab) {
            stagesTab.tabItem { Label("Stages", systemImage: "checklist") }.tag(AppTab.pipeline)
            ResearchView().tabItem { Label("Library", systemImage: "book.closed") }.tag(AppTab.library)
        }
        .frame(minWidth: 640, idealWidth: 860, minHeight: 700, idealHeight: 900)
        #else
        TabView(selection: $selectedTab) {
            // One keyboard "Done" toolbar per tab hierarchy — per-field toolbars
            // get merged by SwiftUI and show duplicate buttons.
            NavigationStack { stagesTab.keyboardDismissToolbar() }
                .tabItem { Label("Stages", systemImage: "checklist") }
                .tag(AppTab.pipeline)
            NavigationStack { ResearchView().keyboardDismissToolbar() }
                .tabItem { Label("Library", systemImage: "book.closed") }
                .tag(AppTab.library)
        }
        #endif
    }

    // MARK: - Stages tab

    private var stagesTab: some View {
        Group {
            if let project = active {
                projectStages(project)
            } else {
                emptyState
            }
        }
        .background(Color.appWindowBackground)
        #if os(iOS)
        .navigationTitle(active?.definition.name ?? "Project Tracker")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { iosMenu }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNotificationSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("settings-button")
            }
        }
        #endif
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            reload()
            checkSharedInbox()
            if UITestSupport.opensSettingsAtLaunch {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { showNotificationSettings = true }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .iCloudContainerReady)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .iCloudFilesChanged)) { _ in
            reload()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: NSUbiquitousKeyValueStore.default
            )
        ) { note in
            guard let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String],
                  keys.contains(ProgressStore.bufferDaysKey) else { return }
            bufferDays = ProgressStore.loadBufferDays()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            CloudContainer.retryIfNeeded()
            NSUbiquitousKeyValueStore.default.synchronize()
            reload()
            checkSharedInbox()
        }
        .onChange(of: expandedStages) { _, newValue in saveExpandedState(newValue) }
        .onChange(of: active?.definition.stages) { _, stages in
            // Reminders belong to the active project's stages: follow renames,
            // imports and project switches instead of keeping stale titles.
            if let stages { NotificationStore.reschedule(for: stages) }
        }
    }

    private func projectStages(_ project: Project) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: sectionSpacing) {
                header(project)
                alertBanner(project)
                nextUp(project)
                #if os(macOS)
                macToolbar
                #endif

                SectionTitle("All stages")
                    .padding(.top, 6)

                LazyVStack(alignment: .leading, spacing: rowSpacing) {
                    ForEach(Array(project.definition.stages.enumerated()), id: \.element.id) { index, stage in
                        StageRowView(
                            stage: stage,
                            number: index + 1,
                            isDone: project.isStageDone(stage),
                            completedTaskIDs: project.progress.completedTaskIDs,
                            onToggle: { taskID, newValue in
                                mutateActive { $0.setTask(taskID, done: newValue) }
                            },
                            bufferDays: bufferDays,
                            isExpanded: Binding(
                                get: { expandedStages.contains(stage.id) },
                                set: { newVal in
                                    if newVal { expandedStages.insert(stage.id) }
                                    else { expandedStages.remove(stage.id) }
                                }
                            ),
                            onEdit: { editingStage = stage }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(platformPadding)
        }
    }

    // MARK: - Empty state (no projects yet)

    private var aiSetupAvailable: Bool { AIStagePlanner.isAvailable }

    private var pasteCard: some View {
        ActionCard(
            icon: aiSetupAvailable ? "apple.intelligence" : "doc.on.clipboard",
            title: aiSetupAvailable ? "Set up in seconds" : "Paste your deadlines",
            subtitle: aiSetupAvailable
                ? "Paste your course's deadlines email or handbook page. Apple Intelligence builds the stages, dates and tasks."
                : "Paste the deadlines email or handbook page from your course and get the stages from it.",
            prominent: aiSetupAvailable
        ) { showPasteNewProject = true }
            .accessibilityIdentifier("paste-deadlines-card")
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    Image(systemName: "checklist")
                        .font(.system(size: 44))
                        .foregroundStyle(.tertiary)
                    Text("No projects yet")
                        .font(.title2.bold())
                    Text("Track a thesis, dissertation or any project as a set of dated stages. Start one of three ways:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 28)

                VStack(spacing: 12) {
                    // With Apple Intelligence, pasting is the quickest start, so it leads.
                    if aiSetupAvailable { pasteCard }

                    ActionCard(
                        icon: "plus.circle.fill",
                        title: "New project",
                        subtitle: "Start from a template, then shape the stages by hand or with an AI assistant.",
                        prominent: !aiSetupAvailable
                    ) { showNewProject = true }
                        .accessibilityIdentifier("new-project-button")

                    if !aiSetupAvailable { pasteCard }

                    ActionCard(
                        icon: "square.and.arrow.down",
                        title: "Import a file",
                        subtitle: "Open a project file (.json) you already have."
                    ) { showImporter = true }
                        .accessibilityIdentifier("import-file-card")
                }
                .frame(maxWidth: 460)
            }
            .frame(maxWidth: .infinity)
            .padding(platformPadding)
        }
    }

    private var platformPadding: CGFloat {
        #if os(macOS)
        return 26
        #else
        return 16
        #endif
    }

    /// Vertical gap between the header blocks.
    private var sectionSpacing: CGFloat {
        #if os(macOS)
        return 16
        #else
        return 12
        #endif
    }

    /// Gap between stage cards.
    private var rowSpacing: CGFloat {
        #if os(macOS)
        return 12
        #else
        return 10
        #endif
    }

    // MARK: - Header

    @ViewBuilder
    private func header(_ project: Project) -> some View {
        let done = project.passedStageCount
        let total = project.definition.stages.count
        #if os(iOS)
        // The navigation bar already shows the project name.
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(done) of \(total) stages done")
                    .font(.headline)
                    .accessibilityIdentifier("progress-summary")
                Spacer()
                projectMenu(project)
            }
            if let topic = project.definition.topic, !topic.isEmpty {
                Text(topic)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .tint(.green)
        }
        #else
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(project.definition.name)
                    .font(.largeTitle.bold())
                Spacer()
                projectMenu(project)
            }
            if let topic = project.definition.topic, !topic.isEmpty {
                Text(topic)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text("\(done) of \(total) stages done")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("progress-summary")
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .tint(.green)
                .padding(.top, 2)
        }
        #endif
    }

    // MARK: - Project menu

    private func projectMenu(_ project: Project) -> some View {
        Menu {
            if projects.count > 1 {
                ForEach(projects) { p in
                    Button { setActive(p.id) } label: {
                        if p.id == project.id {
                            Label(p.definition.name, systemImage: "checkmark")
                        } else {
                            Text(p.definition.name)
                        }
                    }
                }
                Divider()
            }
            Button { showNewProject = true } label: {
                Label("New Project…", systemImage: "plus")
            }
            Button { renameText = project.definition.name; showRename = true } label: {
                Label("Rename…", systemImage: "pencil")
            }
            Button { showStageEditor = true } label: {
                Label("Edit Stages…", systemImage: "list.bullet")
            }
            Button { pasteMode = .update } label: {
                Label("Update Deadlines…", systemImage: "arrow.triangle.2.circlepath")
            }
            Divider()
            Button { copyPrompt() } label: {
                Label("Copy Prompt for AI", systemImage: "doc.on.doc")
            }
            Button { importFromClipboard() } label: {
                Label("Import from Clipboard", systemImage: "doc.on.clipboard")
            }
            Button { exportActive() } label: {
                Label("Export File…", systemImage: "square.and.arrow.up")
            }
            Button { shareTemplate() } label: {
                Label("Share as Template…", systemImage: "square.and.arrow.up.on.square")
            }
            Button { showImporter = true } label: {
                Label("Import File…", systemImage: "square.and.arrow.down")
            }
            #if os(macOS)
            Button { revealProjectsFolder() } label: {
                Label("Show Projects Folder", systemImage: "folder")
            }
            #endif
            Divider()
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Delete Project…", systemImage: "trash")
            }
        } label: {
            HStack(spacing: 4) {
                Text(projects.count > 1 ? "Projects" : "Project")
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.callout)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityIdentifier("project-menu")
    }

    #if os(iOS)
    private var iosMenu: some View {
        Menu {
            Button { expandedStages = Set(active?.definition.stages.map(\.id) ?? []) } label: {
                Label("Expand All", systemImage: "chevron.down.circle")
            }
            Button { expandedStages = [] } label: {
                Label("Collapse All", systemImage: "chevron.up.circle")
            }
            Divider()
            Button("Reset Progress", role: .destructive) {
                showResetConfirm = true
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("more-menu")
    }
    #endif

    // MARK: - Attention banner

    @ViewBuilder
    private func alertBanner(_ project: Project) -> some View {
        let urgent = project.urgentStages()
        if !urgent.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(urgent.count == 1 ? "1 stage needs attention" : "\(urgent.count) stages need attention")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                    ForEach(urgent) { stage in
                        Text("\(stage.title) · \(stage.dueText())")
                            .font(.subheadline)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Next up

    @ViewBuilder
    private func nextUp(_ project: Project) -> some View {
        if let stage = project.nextStage,
           let index = project.definition.stages.firstIndex(where: { $0.id == stage.id }) {
            let done   = project.isStageDone(stage)
            let status = stage.status(done: done, daysEarly: bufferDays)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Next up · Stage \(index + 1) of \(project.definition.stages.count)")
                        .font(.appLabel)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("next-up-title")
                    Spacer()
                    StatusBadge(status: status)
                }

                Text(stage.title)
                    .font(.title3.bold())

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        TagCapsule(text: stage.dueText(), tint: status == .queued ? nil : status.color)
                        if let target = stage.targetDate(daysEarly: bufferDays) {
                            TagCapsule(text: "Target \(shortDate(target))")
                        }
                        if let weight = stage.weight {
                            TagCapsule(text: "Weighted \(weight)")
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(stage.tasks) { task in
                        let checked = project.isTaskDone(task.id)
                        Toggle(isOn: Binding(
                            get: { checked },
                            set: { newVal in mutateActive { $0.setTask(task.id, done: newVal) } }
                        )) {
                            Text(task.title)
                                .font(.subheadline)
                                .strikethrough(checked)
                                .foregroundStyle(checked ? .secondary : .primary)
                        }
                        .checkboxToggleStyle()
                    }
                }
            }
            .padding(14)
            .padding(.leading, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appControlBackground)
            .overlay(alignment: .leading) { Rectangle().fill(status.color).frame(width: 4) }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - macOS toolbar (in-content)

    #if os(macOS)
    private var macToolbar: some View {
        HStack(spacing: 12) {
            Button { showNotificationSettings = true } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .accessibilityIdentifier("settings-button")
            Button { showStageEditor = true } label: {
                Label("Edit Stages", systemImage: "list.bullet")
            }
            Spacer()
            Button("Reset Progress", role: .destructive) { showResetConfirm = true }
            Button("Collapse All") { expandedStages = [] }
            Button("Expand All") { expandedStages = Set(active?.definition.stages.map(\.id) ?? []) }
        }
        .font(.callout)
        .controlSize(.large)
    }
    #endif

    // MARK: - Project actions

    private func reload() {
        projects = ProjectStore.loadAll()
        if activeID == nil || !projects.contains(where: { $0.id == activeID }) {
            let stored = ProjectStore.activeProjectID
            activeID = projects.first { $0.id == stored }?.id ?? projects.first?.id
        }
        ProjectStore.activeProjectID = activeID
        if expandedStages.isEmpty, let project = active {
            expandedStages = loadExpandedState() ?? Set(project.definition.stages.map(\.id))
        }
        ProjectStore.refreshWidgetSnapshots()
    }

    private func setActive(_ id: UUID) {
        activeID = id
        ProjectStore.activeProjectID = id
        if let project = active {
            expandedStages = Set(project.definition.stages.map(\.id))
        }
        ProjectStore.refreshWidgetSnapshots()
    }

    private func mutateActive(_ change: (inout Project) -> Void) {
        guard var project = active else { return }
        change(&project)
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx] = project
        }
        ProjectStore.save(project)
    }

    /// A project built from pasted, reviewed stages. No setup guide afterwards:
    /// the stages are already the user's real ones.
    private func createProject(named name: String, stages: [ProjectStage]) {
        let project = ProjectStore.create(named: name, stages: stages)
        projects.append(project)
        setActive(project.id)
    }

    /// Someone pasted a project file (e.g. an AI assistant's reply) into the
    /// deadlines box: show the usual import preview once that sheet is gone.
    private func importPastedProjectFile(_ text: String) {
        afterDismissal { previewImport(Data(text.utf8)) }
    }

    private func createProject(named name: String, template: ProjectTemplate, start: Date, end: Date) {
        let project = ProjectStore.create(named: name, template: template, start: start, end: end)
        projects.append(project)
        setActive(project.id)
        // Let the New Project sheet finish dismissing before the guide appears.
        afterDismissal { showSetupGuide = true }
    }

    private func deleteActiveProject() {
        guard let project = active else { return }
        ProjectStore.delete(project)
        projects.removeAll { $0.id == project.id }
        activeID = projects.first?.id
        ProjectStore.activeProjectID = activeID
        ProjectStore.refreshWidgetSnapshots()
    }

    // MARK: - Import / export / AI prompt

    private func importProject(from url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            importError = "The file couldn't be read."
            return
        }
        previewImport(data)
    }

    private func importFromClipboard() {
        guard let text = Clipboard.text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            importError = "The clipboard is empty. Copy the JSON your assistant returned, then try again."
            return
        }
        previewImport(Data(text.utf8))
    }

    private func previewImport(_ data: Data) {
        do {
            pendingImport = try ProjectStore.importSummary(from: data)
        } catch let error as ProjectStore.ImportError {
            importError = error.message
        } catch {
            importError = "Unexpected error: \(error.localizedDescription)"
        }
    }

    private func commitImport(_ project: Project) {
        ProjectStore.save(project)
        reload()
        setActive(project.id)
    }

    private func copyPrompt() {
        guard let project = active else { return }
        Clipboard.copy(ProjectStore.aiPrompt(for: project))
        showInfo("Prompt copied. Paste it into your AI assistant.")
    }

    /// Replaces the active project's stages (from the editor or a pasted
    /// list). Progress is kept for task ids that still exist.
    /// Saves one stage edited from its card. Its id is kept, so ticks on tasks
    /// that still exist survive; ticks on deleted tasks are dropped.
    private func replaceStage(_ stage: ProjectStage) {
        guard let project = active,
              let index = project.definition.stages.firstIndex(where: { $0.id == stage.id }) else { return }
        var stages = project.definition.stages
        stages[index] = stage
        applyStages(stages)
    }

    private func removeStage(_ id: UUID) {
        guard let project = active else { return }
        let remaining = project.definition.stages.filter { $0.id != id }
        guard !remaining.isEmpty else {
            showInfo("A project needs at least one stage.")
            return
        }
        applyStages(remaining)
    }

    private func applyStages(_ stages: [ProjectStage]) {
        mutateActive {
            $0.definition.stages = stages
            $0.progress.completedTaskIDs.formIntersection($0.allTaskIDs)
        }
        expandedStages.formUnion(stages.map(\.id))
    }

    // MARK: - Share extension inbox

    /// Shows the import preview for anything another app shared to us.
    private func checkSharedInbox() {
        guard pendingImport == nil, inboxItem == nil, let url = SharedInbox.pending().first else { return }
        inboxItem = url
        guard let data = try? Data(contentsOf: url) else { finishInboxItem(); return }
        previewImport(data)
        if pendingImport == nil { finishInboxItem() }   // invalid content: alert shown, drop the file
    }

    private func finishInboxItem() {
        if let url = inboxItem { SharedInbox.remove(url) }
        inboxItem = nil
        // More than one item may be waiting.
        if pendingImport == nil { DispatchQueue.main.async { checkSharedInbox() } }
    }

    private func exportActive() {
        guard let project = active, let data = ProjectStore.exportData(project) else { return }
        shareFile(data, named: ProjectStore.exportFilename(project), panelTitle: "Export Project")
    }

    private func shareTemplate() {
        guard let project = active, let data = ProjectStore.templateData(project) else { return }
        shareFile(data, named: ProjectStore.templateFilename(project), panelTitle: "Save Template")
    }

    /// Save panel on the Mac, share sheet on iOS (AirDrop, Messages, Files…).
    private func shareFile(_ data: Data, named filename: String, panelTitle: String) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.title = panelTitle
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = filename
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url)
            } catch {
                Task { @MainActor in StorageErrors.shared.report("save the export file", error: error) }
            }
        }
        #else
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url)
        } catch {
            StorageErrors.shared.report("save the export file", error: error)
            return
        }
        shareItems = [url]
        showShareSheet = true
        #endif
    }

    #if os(macOS)
    private func revealProjectsFolder() {
        let dir = ProjectStore.projectsDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }
    #endif

    // MARK: - Helpers

    /// Runs after the current sheet has had time to dismiss, so two
    /// presentations don't collide.
    private func afterDismissal(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: action)
    }

    private func showInfo(_ message: String) {
        infoMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if infoMessage == message { infoMessage = nil }
        }
    }

    private func loadExpandedState() -> Set<UUID>? {
        guard let saved = UserDefaults.standard.array(forKey: Self.expandedStorageKey) as? [String]
        else { return nil }
        return Set(saved.compactMap(UUID.init(uuidString:)))
    }

    private func saveExpandedState(_ expanded: Set<UUID>) {
        UserDefaults.standard.set(expanded.map(\.uuidString), forKey: Self.expandedStorageKey)
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }
}

#Preview {
    ContentView()
}

/// How the paste sheet starts: merging into the project's stages (from the
/// menu) or replacing a fresh template (from the setup guide).
private enum PasteMode: Identifiable {
    case update, replace
    var id: Self { self }
}
