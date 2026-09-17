import SwiftUI
import UniformTypeIdentifiers

// MARK: - Library tab (papers, links, PDFs, notes)

struct ResearchView: View {
    @State private var items: [ResearchItem]
    @State private var lastSaved: [ResearchItem]
    @State private var pendingSave: Task<Void, Never>?
    @State private var showingAdd = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let loaded = ResearchStore.load()
        _items = State(initialValue: loaded)
        _lastSaved = State(initialValue: loaded)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("REFERENCE LIBRARY")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.primary)
                }
                Spacer()
                Button { showingAdd = true } label: {
                    Label("Add Item", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(26)
            .background(Color.appControlBackground)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach($items) { $item in
                            ResearchItemCard(item: $item) { deleteItem(item) }
                        }
                    }
                    .padding(26)
                }
            }
        }
        .background(Color.appWindowBackground)
        .onChange(of: items) { scheduleSave() }
        .onDisappear { saveNow() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveNow() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .iCloudContainerReady)) { _ in
            reloadFromCloud()
        }
        .onReceive(NotificationCenter.default.publisher(for: .iCloudFilesChanged)) { _ in
            reloadFromCloud()
        }
        .sheet(isPresented: $showingAdd) {
            AddResearchItemSheet { newItem in
                items.insert(newItem, at: 0)
                saveNow()
            }
        }
    }

    /// Refreshes the list once the iCloud container resolves or synced files
    /// change (e.g. an item added on the Mac arriving on the iPhone). Local
    /// edits are flushed first so a synced copy never overwrites unsaved typing.
    private func reloadFromCloud() {
        saveNow()
        let fresh = ResearchStore.load()
        if fresh != items {
            lastSaved = fresh
            items = fresh
        }
    }

    // MARK: - Saving (debounced)

    /// Title, link and note edits save after a one-second pause instead of on
    /// every keystroke, so the index isn't rewritten in iCloud Drive per key.
    /// Structural changes (add, delete) and leaving the tab save immediately.
    private func scheduleSave() {
        guard items != lastSaved else { return }
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            pendingSave = nil
            saveNow()
        }
    }

    private func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        guard items != lastSaved else { return }
        lastSaved = items
        ResearchStore.save(items)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)
            Text("No references yet")
                .font(.title3.bold())
            Text("Add papers, links, and notes to build your reference library.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add First Reference") { showingAdd = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func deleteItem(_ item: ResearchItem) {
        if let fn = item.filename { ResearchStore.deleteFile(filename: fn) }
        items.removeAll { $0.id == item.id }
        saveNow()
    }
}

// MARK: - Research item card

struct ResearchItemCard: View {
    @Binding var item: ResearchItem
    let onDelete: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var showFilePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    TextField("Title", text: $item.name)
                        .font(.title3.bold())
                        .textFieldStyle(.plain)
                    Text("Added \(item.addedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }

            // Link row
            HStack(spacing: 8) {
                Image(systemName: "link").foregroundStyle(.blue).font(.callout).frame(width: 18)
                TextField("https://…", text: $item.link)
                    .textFieldStyle(.plain)
                    .font(.callout.monospaced())
                    .foregroundStyle(.blue)
                if !item.link.isEmpty, let url = URL(string: item.link) {
                    Button("Open") { openURL(url) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            .padding(10)
            .background(Color.blue.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // PDF row
            if let fn = item.filename {
                let pdfURL = ResearchStore.fileURL(filename: fn)
                HStack(spacing: 8) {
                    Image(systemName: "doc.fill").foregroundStyle(.red).font(.callout)
                    Text(item.fileDisplayName ?? "PDF")
                        .font(.callout).lineLimit(1)
                    Spacer()
                    openPDFControl(url: pdfURL)
                    Button(role: .destructive) {
                        ResearchStore.deleteFile(filename: fn)
                        item.filename = nil
                        item.fileDisplayName = nil
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                .padding(10)
                .background(Color.red.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Button { showFilePicker = true } label: {
                    Label("Attach PDF", systemImage: "doc.badge.plus")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }

            // Notes
            ZStack(alignment: .topLeading) {
                if item.notes.isEmpty {
                    Text("Add notes…")
                        .font(.body).foregroundStyle(.tertiary)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $item.notes)
                    .font(.body)
                    .frame(minHeight: 60, maxHeight: 160)
                    .scrollContentBackground(.hidden)
            }
            .padding(6)
            .background(Color.appTextBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.10), lineWidth: 1))
        }
        .padding(16)
        .background(Color.appControlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.pdf]) { result in
            guard let url = try? result.get() else { return }
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            item.filename = ResearchStore.addFile(from: url)
            item.fileDisplayName = item.filename == nil
                ? nil : url.deletingPathExtension().lastPathComponent
        }
    }

    @ViewBuilder
    private func openPDFControl(url: URL) -> some View {
        #if os(macOS)
        Button("Open PDF") { NSWorkspace.shared.open(url) }
            .buttonStyle(.borderless).font(.caption)
        #else
        ShareLink(item: url) {
            Text("Share PDF").font(.caption)
        }
        .buttonStyle(.borderless)
        #endif
    }
}

// MARK: - Add item sheet

struct AddResearchItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (ResearchItem) -> Void

    @State private var name = ""
    @State private var link = ""
    @State private var notes = ""
    // PDF is copied immediately in fileImporter (security scope only valid there).
    // We keep the stored filename and a display name separately.
    @State private var pendingFilename: String?       // UUID filename in ResearchStore
    @State private var pendingDisplayName = ""        // original name shown in UI
    @State private var showFilePicker = false
    @State private var didCommit = false              // true when Add was tapped

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add Reference")
                .font(.title2.bold())

            Grid(alignment: .leading, verticalSpacing: 14) {
                GridRow {
                    Text("Title").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    TextField("Paper or resource name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("reference-title-field")
                }
                GridRow {
                    Text("Link").foregroundStyle(.secondary)
                    TextField("https://…", text: $link).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("PDF").foregroundStyle(.secondary)
                    HStack {
                        if !pendingDisplayName.isEmpty {
                            Image(systemName: "doc.fill").foregroundStyle(.red)
                            Text(pendingDisplayName).font(.callout).lineLimit(1)
                            Spacer()
                            Button("Remove") {
                                if let fn = pendingFilename { ResearchStore.deleteFile(filename: fn) }
                                pendingFilename = nil
                                pendingDisplayName = ""
                            }
                            .buttonStyle(.borderless).foregroundStyle(.secondary)
                        } else {
                            Button("Choose PDF…") { showFilePicker = true }
                            Spacer()
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes").foregroundStyle(.secondary)
                ZStack(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Optional notes…").foregroundStyle(.tertiary)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $notes)
                        .frame(height: 100)
                        .scrollContentBackground(.hidden)
                }
                .padding(6)
                .background(Color.appTextBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.10), lineWidth: 1))
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    // Remove any PDF copied during this session.
                    if let fn = pendingFilename { ResearchStore.deleteFile(filename: fn) }
                    dismiss()
                }
                Spacer()
                Button("Add") {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    var newItem = ResearchItem(
                        name: trimmed.isEmpty ? "Untitled" : trimmed,
                        link: link, notes: notes
                    )
                    newItem.filename = pendingFilename
                    newItem.fileDisplayName = pendingDisplayName.isEmpty ? nil : pendingDisplayName
                    didCommit = true
                    onAdd(newItem)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("add-reference-button")
            }
        }
        .padding(28)
        #if os(macOS)
        .frame(width: 480)
        #endif
        .keyboardDismissToolbar()
        .onDisappear {
            // Swipe-to-dismiss path: clean up PDF if Add was never tapped.
            if !didCommit, let fn = pendingFilename { ResearchStore.deleteFile(filename: fn) }
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.pdf]) { result in
            guard let url = try? result.get() else { return }
            // Security scope is only valid inside this callback — copy the file now.
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            if let fn = pendingFilename { ResearchStore.deleteFile(filename: fn) } // replace prev pick
            pendingDisplayName = url.deletingPathExtension().lastPathComponent
            pendingFilename = ResearchStore.addFile(from: url)
        }
    }
}
