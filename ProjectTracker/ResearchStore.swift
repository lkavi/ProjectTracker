import Foundation

struct ResearchItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var filename: String? = nil        // UUID filename on disk; nil when no PDF attached
    var fileDisplayName: String? = nil // original PDF name shown in the UI
    var link: String = ""
    var notes: String = ""
    var addedAt: Date = Date()
}

/// Persists the research paper list and associated PDFs in iCloud Drive
/// (Documents/FYPPipeline/research/) so they sync across Mac and iPhone.
/// All I/O goes through CloudContainer's coordinated helpers.
@MainActor
enum ResearchStore {
    private static var baseURL: URL {
        CloudContainer.baseURL.appendingPathComponent("research", isDirectory: true)
    }

    private static var indexURL: URL {
        baseURL.appendingPathComponent("index.json")
    }

    static var filesDir: URL {
        baseURL.appendingPathComponent("files", isDirectory: true)
    }

    static func load() -> [ResearchItem] {
        guard let data = CloudContainer.read(at: indexURL),
              let items = try? JSONDecoder().decode([ResearchItem].self, from: data)
        else { return [] }
        // Kick off downloads for referenced PDFs so they're local by the time
        // the user taps one (iOS doesn't auto-download iCloud Drive files).
        for item in items {
            if let fn = item.filename {
                CloudContainer.ensureDownloaded(filesDir.appendingPathComponent(fn))
            }
        }
        return items
    }

    static func save(_ items: [ResearchItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        CloudContainer.write(data, to: indexURL)
    }

    static func addFile(from sourceURL: URL) -> String? {
        let filename = UUID().uuidString + ".pdf"
        let dest = filesDir.appendingPathComponent(filename)
        return CloudContainer.copyIn(from: sourceURL, to: dest) ? filename : nil
    }

    static func fileURL(filename: String) -> URL {
        filesDir.appendingPathComponent(filename)
    }

    static func deleteFile(filename: String) {
        CloudContainer.delete(at: fileURL(filename: filename))
    }

    /// Moves research data saved to local storage (before iCloud resolved) into
    /// iCloud, unioning index entries by id. Clears the local copy on success so
    /// deleted items can't be resurrected by a later merge. Idempotent.
    static func mergeLocalIntoCloud() {
        guard CloudContainer.isAvailable else { return }
        let localBase = CloudContainer.localFallback.appendingPathComponent("research", isDirectory: true)
        guard localBase.path != baseURL.path,
              FileManager.default.fileExists(atPath: localBase.path) else { return }

        // If a cloud index exists but hasn't downloaded yet, merging now would
        // overwrite it with local-only data. Wait for the download to finish
        // (this runs again after each metadata gather).
        if CloudContainer.downloadStatus(indexURL) == .notDownloaded {
            CloudContainer.ensureDownloaded(indexURL)
            return
        }

        // Copy PDFs that aren't in the cloud yet.
        let localFiles = localBase.appendingPathComponent("files", isDirectory: true)
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: localFiles, includingPropertiesForKeys: nil) {
            for file in contents where CloudContainer.downloadStatus(
                filesDir.appendingPathComponent(file.lastPathComponent)) == nil {
                _ = CloudContainer.copyIn(
                    from: file, to: filesDir.appendingPathComponent(file.lastPathComponent))
            }
        }

        // Union local index entries into the cloud index by id.
        let localIndex = localBase.appendingPathComponent("index.json")
        if let data = try? Data(contentsOf: localIndex),
           let localItems = try? JSONDecoder().decode([ResearchItem].self, from: data),
           !localItems.isEmpty {
            var merged = load()
            let existing = Set(merged.map(\.id))
            merged.append(contentsOf: localItems.filter { !existing.contains($0.id) })
            save(merged)
        }

        try? FileManager.default.removeItem(at: localBase)
    }
}
