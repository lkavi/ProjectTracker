import SwiftUI
import UniformTypeIdentifiers

struct StageNotesView: View {
    let stageKey: String
    @State private var record: StageRecord
    @State private var showFilePicker = false
    @State private var pendingPickIsFinal = false

    init(stageKey: String) {
        self.stageKey = stageKey
        _record = State(initialValue: ArtifactsStore.load(stageKey: stageKey))
    }

    private var drafts: [StageFile] { record.files.filter { !$0.isFinal } }
    private var finals: [StageFile] { record.files.filter { $0.isFinal } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider().padding(.vertical, 2)

            sectionLabel("NOTES")
            notesEditor

            sectionLabel("DRAFT PDFs")
            ForEach(drafts) { file in fileRow(file: file, isFinal: false) }
            addFileButton("Add Draft PDF", isFinal: false)

            sectionLabel("FINAL SUBMISSION PDF")
            ForEach(finals) { file in fileRow(file: file, isFinal: true) }
            if finals.isEmpty {
                addFileButton("Add Final PDF", isFinal: true)
            }
        }
        .padding(.top, 6)
        .onAppear { reloadFromCloud() }
        .onReceive(NotificationCenter.default.publisher(for: .iCloudContainerReady)) { _ in
            reloadFromCloud()
        }
        .onReceive(NotificationCenter.default.publisher(for: .iCloudFilesChanged)) { _ in
            reloadFromCloud()
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.pdf]) { result in
            guard let url = try? result.get() else { return }
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            let name = url.deletingPathExtension().lastPathComponent
            if let file = ArtifactsStore.addFile(from: url, name: name,
                                                   isFinal: pendingPickIsFinal,
                                                   stageKey: stageKey) {
                record.files.append(file)
                ArtifactsStore.save(record)
            }
        }
    }

    /// Refreshes from iCloud when synced data arrives. Saves happen on every
    /// keystroke, so disk always matches state for local edits — any diff here
    /// is a genuine remote change (last writer wins).
    private func reloadFromCloud() {
        let fresh = ArtifactsStore.load(stageKey: stageKey)
        if fresh != record { record = fresh }
    }

    // MARK: - Sub-views

    private var notesEditor: some View {
        ZStack(alignment: .topLeading) {
            if record.notes.isEmpty {
                Text("Add notes for this stage…")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $record.notes)
                .font(.body)
                .frame(minHeight: 70, maxHeight: 180)
                .scrollContentBackground(.hidden)
                .onChange(of: record.notes) { ArtifactsStore.save(record) }
        }
        .padding(6)
        .background(Color.appTextBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.10), lineWidth: 1))
    }

    private func fileRow(file: StageFile, isFinal: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.fill")
                .foregroundStyle(isFinal ? Color.green : Color.orange)
                .font(.callout)

            TextField("Name", text: nameBinding(for: file))
                .textFieldStyle(.plain)
                .font(.callout)

            Spacer()

            openFileControl(file: file)

            Button(role: .destructive) { deleteFile(file) } label: {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.appWindowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    @ViewBuilder
    private func openFileControl(file: StageFile) -> some View {
        #if os(macOS)
        Button("Open") { openFile(file) }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .font(.caption)
        #else
        ShareLink(item: ArtifactsStore.fileURL(stageKey: stageKey, filename: file.filename)) {
            Text("Share")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        #endif
    }

    private func addFileButton(_ label: String, isFinal: Bool) -> some View {
        Button { pickPDF(isFinal: isFinal) } label: {
            Label(label, systemImage: "plus")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.appLabelBold)
            .foregroundStyle(.secondary)
    }

    // MARK: - Helpers

    private func nameBinding(for file: StageFile) -> Binding<String> {
        Binding(
            get: { file.name },
            set: { newName in
                guard let idx = record.files.firstIndex(where: { $0.id == file.id }) else { return }
                record.files[idx].name = newName
                ArtifactsStore.save(record)
            }
        )
    }

    private func pickPDF(isFinal: Bool) {
        pendingPickIsFinal = isFinal
        showFilePicker = true
    }

    #if os(macOS)
    private func openFile(_ file: StageFile) {
        NSWorkspace.shared.open(ArtifactsStore.fileURL(stageKey: stageKey, filename: file.filename))
    }
    #endif

    private func deleteFile(_ file: StageFile) {
        ArtifactsStore.deleteFile(file, stageKey: stageKey)
        record.files.removeAll { $0.id == file.id }
        ArtifactsStore.save(record)
    }
}
