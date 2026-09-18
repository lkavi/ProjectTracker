import Foundation

/// Hand-off folder inside the App Group container. The share extension drops
/// shared text or files here; the app shows the import preview for each item
/// the next time it becomes active and removes the file afterwards.
///
/// File names start with a millisecond timestamp so they sort oldest-first
/// without touching file attributes.
enum SharedInbox {
    static let appGroupID = "group.lkavi.fyppipeline"

    static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("Inbox", isDirectory: true)
    }

    /// True when the App Group container exists and can be written to. False
    /// for builds without the App Group entitlement (e.g. unsigned test hosts).
    static var isAvailable: Bool {
        guard let dir = directory else { return false }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return false
        }
        return FileManager.default.isWritableFile(atPath: dir.path)
    }

    /// Writes the shared bytes and returns the file, or nil if the App Group
    /// container isn't available.
    @discardableResult
    static func save(_ data: Data) -> URL? {
        guard let dir = directory else { return nil }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let stamp = Int(Date().timeIntervalSince1970 * 1000)
            let url = dir.appendingPathComponent("\(stamp)-\(UUID().uuidString).json")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Waiting items, oldest first.
    static func pending() -> [URL] {
        guard let dir = directory,
              let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        return urls.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
