import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

enum AppTab: Hashable {
    case pipeline, library
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
    @State private var selectedTab: AppTab = .pipeline

    // Projects
    @State private var projects: [Project] = []
    @State private var activeID: UUID?
    @State private var expandedStages: Set<UUID> = []
    @State private var bufferDays: Int = ProgressStore.loadBufferDays()
    @State private var hasLoaded = false

    // Sheets & alerts
    @State private var showNewProject = false
    @State private var newProjectName = ""
    @State private var showPersonalizeGuide = false
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showDeleteConfirm = false
    @State private var showResetConfirm = false
    @State private var resetConfirmText = ""
    @State private var importError: String?
    @State private var showImporter = false
    @State private var showNotificationSettings = false
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
            .alert("Clear all checked progress?", isPresented: $showResetConfirm) {
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
            .alert("New Project", isPresented: $showNewProject) {
                TextField("Project name", text: $newProjectName)
                Button("Cancel", role: .cancel) { newProjectName = "" }
                Button("Create") { createProject() }
            } message: {
                Text("Starts from the built-in template. Export it for an AI assistant to tailor the stages and tasks to your project.")
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
            .alert("Couldn't import that file",
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
                NotificationSettingsView(stages: active?.definition.stages ?? [])
            }
            .sheet(isPresented: $showPersonalizeGuide) {
                PersonalizeGuideView(
                    projectName: active?.definition.name ?? "your project",
                    onExport: {
                        showPersonalizeGuide = false
                        // Let the guide sheet dismiss before the share sheet /
                        // save panel presents.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            exportActive()
                        }
                    }
                )
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json, .plainText]) { result in
                guard let url = try? result.get() else { return }
                _ = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }
                importProject(from: url)
            }
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
            pipelineTab.tabItem { Label("Pipeline", systemImage: "list.bullet.clipboard") }.tag(AppTab.pipeline)
            ResearchView().tabItem { Label("Library", systemImage: "books.vertical") }.tag(AppTab.library)
        }
        .frame(minWidth: 640, idealWidth: 860, minHeight: 700, idealHeight: 900)
        #else
        TabView(selection: $selectedTab) {
            // One keyboard "Done" toolbar per tab hierarchy — per-field toolbars
            // get merged by SwiftUI and show duplicate buttons.
            NavigationStack { pipelineTab.keyboardDismissToolbar() }
                .tabItem { Label("Pipeline", systemImage: "list.bullet.clipboard") }
                .tag(AppTab.pipeline)
            NavigationStack { ResearchView().keyboardDismissToolbar() }
                .tabItem { Label("Library", systemImage: "books.vertical") }
                .tag(AppTab.library)
        }
        #endif
    }

    // MARK: - Pipeline tab

    private var pipelineTab: some View {
        Group {
            if let project = active {
                projectPipeline(project)
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
        }
        .onChange(of: expandedStages) { _, newValue in saveExpandedState(newValue) }
        .onChange(of: active?.definition.stages) { _, stages in
            // Reminders belong to the active project's stages: follow renames,
            // imports and project switches instead of keeping stale titles.
            if let stages { NotificationStore.reschedule(for: stages) }
        }
    }

    private func projectPipeline(_ project: Project) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: sectionSpacing) {
                    header(project)
                    alertBanner(project)
                    spotlight(project)
                    #if os(macOS)
                    macToolbar
                    #endif
                }
                .padding(platformPadding)
                .background(Color.appControlBackground)
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().overlay(Color.primary.opacity(0.08))

                VStack(alignment: .leading, spacing: rowSpacing) {
                    Text("ALL STAGES")
                        .font(.appLabel)
                        .foregroundStyle(.secondary)
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
                                )
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(platformPadding)
            }
        }
    }

    // MARK: - Empty state (no projects yet)

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)
            Text("No projects yet")
                .font(.title3.bold())
            Text("Create a project to get a ready-made stage template. Export it, give it to an AI assistant with your project idea and your real milestones or submission steps, then import the tailored file back.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack(spacing: 12) {
                Button("New Project") { newProjectName = ""; showNewProject = true }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("new-project-button")
                Button("Import Project JSON…") { showImporter = true }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var platformPadding: CGFloat {
        #if os(macOS)
        return 26
        #else
        return 16
        #endif
    }

    /// Vertical gap between the big header blocks (header/banner/spotlight).
    private var sectionSpacing: CGFloat {
        #if os(macOS)
        return 16
        #else
        return 12
        #endif
    }

    /// Gap between stage cards / the "ALL STAGES" label.
    private var rowSpacing: CGFloat {
        #if os(macOS)
        return 14
        #else
        return 10
        #endif
    }

    // MARK: - Header

    @ViewBuilder
    private func header(_ project: Project) -> some View {
        #if os(iOS)
        // The nav bar already shows the project name, so the header stays
        // compact: progress count + bar, plus the project menu and topic.
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(project.passedStageCount) of \(project.definition.stages.count) stages passed")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("progress-summary")
                Spacer()
                projectMenu(project)
            }
            if let topic = project.definition.topic, !topic.isEmpty {
                Text(topic)
                    .font(.appMeta)
                    .foregroundStyle(.blue)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ProgressView(value: Double(project.passedStageCount),
                         total: Double(max(project.definition.stages.count, 1)))
                .tint(.green)
        }
        #else
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("PROJECT TRACKER")
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                projectMenu(project)
            }
            Text(project.definition.name)
                .font(.largeTitle.bold())
                .foregroundStyle(.primary)
            if let topic = project.definition.topic, !topic.isEmpty {
                Text("topic · \(topic)")
                    .font(.callout.monospaced())
                    .foregroundStyle(.blue)
            }
            Text("\(project.passedStageCount) / \(project.definition.stages.count) stages passed")
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("progress-summary")
            ProgressView(value: Double(project.passedStageCount),
                         total: Double(max(project.definition.stages.count, 1)))
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
                        Label(p.definition.name, systemImage: p.id == project.id ? "checkmark" : "")
                    }
                }
                Divider()
            }
            Button { newProjectName = ""; showNewProject = true } label: {
                Label("New Project…", systemImage: "plus")
            }
            Button { renameText = project.definition.name; showRename = true } label: {
                Label("Rename…", systemImage: "pencil")
            }
            Divider()
            Button { exportActive() } label: {
                Label("Export for AI / Backup…", systemImage: "square.and.arrow.up")
            }
            Button { showImporter = true } label: {
                Label("Import Project JSON…", systemImage: "square.and.arrow.down")
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
            Label(projects.count > 1 ? "Projects (\(projects.count))" : "Project",
                  systemImage: "folder")
                .font(.callout)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
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

    // MARK: - Alert banner

    @ViewBuilder
    private func alertBanner(_ project: Project) -> some View {
        let urgent = project.urgentStages()
        if !urgent.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("⚠ \(urgent.count) stage\(urgent.count > 1 ? "s" : "") need\(urgent.count > 1 ? "" : "s") you now")
                    .font(.appLabelBold)
                    .foregroundStyle(.red)
                ForEach(urgent) { stage in
                    Text("• \(stage.title) — \(stage.dueText())")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Next Up spotlight

    @ViewBuilder
    private func spotlight(_ project: Project) -> some View {
        if let stage = project.nextStage,
           let index = project.definition.stages.firstIndex(where: { $0.id == stage.id }) {
            let done   = project.isStageDone(stage)
            let status = stage.status(done: done, daysEarly: bufferDays)

            HStack(alignment: .top, spacing: 0) {
                Rectangle().fill(status.color).frame(width: 4)

                VStack(alignment: .leading, spacing: 10) {
                    Text("▶ NEXT UP · STAGE \(index + 1) OF \(project.definition.stages.count)")
                        .font(.appLabelBold)
                        .foregroundStyle(status.color)
                        .accessibilityIdentifier("next-up-title")

                    Text(stage.title)
                        .font(.title3.bold())
                        .foregroundStyle(.primary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Text(stage.dueText())
                                .font(.appLabelBold)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(status.color.opacity(0.22))
                                .foregroundStyle(status.color)
                                .clipShape(Capsule())
                            if let target = stage.targetDate(daysEarly: bufferDays) {
                                Text("target · \(shortDate(target))")
                                    .font(.appMeta)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.appControlBackground)
                                    .foregroundStyle(.secondary)
                                    .clipShape(Capsule())
                            }
                            if let weight = stage.weight {
                                Text("summative · \(weight)")
                                    .font(.appMeta)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.purple.opacity(0.18))
                                    .foregroundStyle(.purple)
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    Divider().overlay(status.color.opacity(0.3))

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

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(status.color.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: status.color.opacity(0.2), radius: 8, y: 3)
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

    private func createProject() {
        let project = ProjectStore.create(named: newProjectName)
        newProjectName = ""
        projects.append(project)
        setActive(project.id)
        // Let the "New Project" alert finish dismissing before presenting the
        // personalization guide, so the two presentations don't collide.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            showPersonalizeGuide = true
        }
    }

    private func deleteActiveProject() {
        guard let project = active else { return }
        ProjectStore.delete(project)
        projects.removeAll { $0.id == project.id }
        activeID = projects.first?.id
        ProjectStore.activeProjectID = activeID
        ProjectStore.refreshWidgetSnapshots()
    }

    private func importProject(from url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            importError = "The file couldn't be read."
            return
        }
        do {
            let project = try ProjectStore.importProject(from: data)
            ProjectStore.save(project)
            reload()
            setActive(project.id)
        } catch let error as ProjectStore.ImportError {
            importError = error.message
        } catch {
            importError = "Unexpected error: \(error.localizedDescription)"
        }
    }

    private func exportActive() {
        guard let project = active, let data = ProjectStore.exportData(project) else { return }
        let filename = ProjectStore.exportFilename(project)
        #if os(macOS)
        let panel = NSSavePanel()
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

    private func loadExpandedState() -> Set<UUID>? {
        guard let saved = UserDefaults.standard.array(forKey: Self.expandedStorageKey) as? [String]
        else { return nil }
        return Set(saved.compactMap(UUID.init(uuidString:)))
    }

    private func saveExpandedState(_ expanded: Set<UUID>) {
        UserDefaults.standard.set(expanded.map(\.uuidString), forKey: Self.expandedStorageKey)
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: date)
    }
}

#Preview {
    ContentView()
}
