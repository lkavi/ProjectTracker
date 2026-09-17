import Foundation

struct StageFile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var filename: String    // UUID-based filename stored on disk
    var isFinal: Bool
    var addedAt: Date = Date()
}

struct StageRecord: Codable, Equatable {
    var stageKey: String    // the stage's UUID string — stable across renames
    var notes: String = ""
    var files: [StageFile] = []
}

/// Persists per-stage notes and PDFs in iCloud Drive (Documents/FYPPipeline/)
/// so they sync across Mac and iPhone automatically. Records are keyed by the
/// stage's UUID, so they survive renames and follow stages across projects.
/// All I/O goes through CloudContainer's coordinated helpers.
@MainActor
enum ArtifactsStore {
    private static var baseURL: URL { CloudContainer.baseURL }

    private static func stageDir(for stageKey: String) -> URL {
        baseURL.appendingPathComponent("files/\(stageKey)", isDirectory: true)
    }

    private static func notesURL(for stageKey: String) -> URL {
        baseURL.appendingPathComponent("notes/\(stageKey).json")
    }

    static func load(stageKey: String) -> StageRecord {
        var record: StageRecord
        if let data = CloudContainer.read(at: notesURL(for: stageKey)),
           let stored = try? JSONDecoder().decode(StageRecord.self, from: data) {
            record = stored
        } else {
            record = StageRecord(stageKey: stageKey)
        }
        // Kick off downloads for attached PDFs (iOS doesn't auto-download).
        for file in record.files {
            CloudContainer.ensureDownloaded(fileURL(stageKey: stageKey, filename: file.filename))
        }
        return record
    }

    static func save(_ record: StageRecord) {
        do {
            let data = try JSONEncoder().encode(record)
            CloudContainer.write(data, to: notesURL(for: record.stageKey))
        } catch {
            StorageErrors.shared.report("save the stage notes", error: error)
        }
        // Notes may appear in the widget's snapshot of the next stage.
        ProjectStore.refreshWidgetSnapshots()
    }

    static func addFile(from sourceURL: URL, name: String, isFinal: Bool, stageKey: String) -> StageFile? {
        let filename = UUID().uuidString + ".pdf"
        let dest = stageDir(for: stageKey).appendingPathComponent(filename)
        guard CloudContainer.copyIn(from: sourceURL, to: dest) else { return nil }
        return StageFile(name: name, filename: filename, isFinal: isFinal)
    }

    static func fileURL(stageKey: String, filename: String) -> URL {
        stageDir(for: stageKey).appendingPathComponent(filename)
    }

    static func deleteFile(_ file: StageFile, stageKey: String) {
        CloudContainer.delete(at: fileURL(stageKey: stageKey, filename: file.filename))
    }

    // MARK: - Local → iCloud merge (files written before the container resolved)

    static func mergeLocalIntoCloud() {
        guard CloudContainer.isAvailable else { return }
        let localBase = CloudContainer.localFallback
        guard localBase.path != baseURL.path else { return }

        // Notes records: copy any local record the cloud doesn't have yet.
        let localNotes = localBase.appendingPathComponent("notes", isDirectory: true)
        var fullyMerged = true
        if let records = try? FileManager.default.contentsOfDirectory(
            at: localNotes, includingPropertiesForKeys: nil) {
            for record in records where record.pathExtension == "json" {
                let dest = baseURL.appendingPathComponent("notes/\(record.lastPathComponent)")
                if CloudContainer.downloadStatus(dest) == nil {
                    _ = CloudContainer.copyIn(from: record, to: dest)
                } else if CloudContainer.downloadStatus(dest) == .notDownloaded {
                    CloudContainer.ensureDownloaded(dest)
                    fullyMerged = false
                }
            }
        }

        // PDFs: copy any file the cloud doesn't have yet, per stage directory.
        let localFiles = localBase.appendingPathComponent("files", isDirectory: true)
        if let dirs = try? FileManager.default.contentsOfDirectory(
            at: localFiles, includingPropertiesForKeys: nil) {
            for dir in dirs {
                let pdfs = (try? FileManager.default.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: nil)) ?? []
                for pdf in pdfs {
                    let dest = baseURL.appendingPathComponent(
                        "files/\(dir.lastPathComponent)/\(pdf.lastPathComponent)")
                    if CloudContainer.downloadStatus(dest) == nil {
                        _ = CloudContainer.copyIn(from: pdf, to: dest)
                    }
                }
            }
        }

        if fullyMerged {
            try? FileManager.default.removeItem(at: localNotes)
            try? FileManager.default.removeItem(at: localFiles)
        }
    }
}
