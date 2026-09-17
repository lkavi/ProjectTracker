import Foundation

extension Notification.Name {
    static let iCloudContainerReady = Notification.Name("iCloudContainerReady")
    /// Posted whenever iCloud Drive files for this app change (new files synced
    /// from another device, downloads completing, deletions). Views that show
    /// file lists should reload when they receive this.
    static let iCloudFilesChanged = Notification.Name("iCloudFilesChanged")
}

/// Resolves the shared iCloud Drive directory for all Project Tracker file data.
/// Falls back to local Documents if iCloud is unavailable or not signed in.
///
/// All reads/writes inside the ubiquity container go through the coordinated
/// I/O helpers below (NSFileCoordinator), as required for iCloud Documents.
@MainActor
enum CloudContainer {
    /// Registered iCloud container. Deliberately kept from the app's original
    /// identifier so existing users' synced data keeps loading after the rename.
    /// A fork must register its own container and change this (and the
    /// matching entries in both .entitlements files).
    private static let containerID = "iCloud.lkavi.fyppipeline"

    /// On-disk folder name inside iCloud Drive / local Documents. Also kept
    /// from the original identifier: renaming it would orphan every user's data.
    static let dataFolderName = "FYPPipeline"
    private static var _icloudBase: URL?
    private static var _isResolving = false

    /// The app's data directory in iCloud Drive, or local Documents as fallback.
    /// Returns cached URL immediately without blocking; call `resolveAsync()` at startup.
    static var baseURL: URL { _icloudBase ?? localFallback }

    /// `true` once the iCloud container URL has been successfully resolved.
    static var isAvailable: Bool { _icloudBase != nil }

    enum SyncStatus {
        case syncing            // container resolved — PDFs sync across devices
        case notSignedIn        // no Apple ID / iCloud account on this device
        case driveAccessNeeded  // signed in, but the container never resolved —
                                 // almost always means iCloud Drive access for
                                 // this app is off in system Settings
    }

    /// Best-effort status for a "Settings" screen. Not for gating logic —
    /// `baseURL`/`isAvailable` already fall back to local storage safely.
    static var status: SyncStatus {
        if isAvailable { return .syncing }
        if FileManager.default.ubiquityIdentityToken == nil { return .notSignedIn }
        return .driveAccessNeeded
    }

    /// Resolves the iCloud container URL, moving the blocking call off the main thread.
    /// Posts `.iCloudContainerReady` when done so views can reload synced file lists.
    /// Safe to call multiple times — no-ops if already resolved or resolving.
    static func resolveAsync() {
        guard !UITestSupport.isActive else { return }   // UI tests stay fully local
        guard _icloudBase == nil, !_isResolving else { return }

        // Fast pre-check: if not signed into iCloud, container will never resolve.
        guard FileManager.default.ubiquityIdentityToken != nil else {
            print("[ProjectTracker] ⚠️ Not signed into iCloud — PDFs can't sync. Sign in via Settings → Apple Account.")
            return
        }

        _isResolving = true
        let id = containerID   // Capture before leaving @MainActor
        Task {
            // Only this one call must be off the main thread (Apple docs).
            let container = await Task.detached(priority: .userInitiated) {
                // Try named container; fall back to the app's default container.
                FileManager.default.url(forUbiquityContainerIdentifier: id)
                    ?? FileManager.default.url(forUbiquityContainerIdentifier: nil)
            }.value
            // Back on @MainActor from here.
            _isResolving = false
            guard let container else {
                print("[ProjectTracker] ⚠️ iCloud container did not resolve — PDFs use local storage.")
                print("[ProjectTracker]    Fix: Xcode → Signing & Capabilities → iCloud → ensure '\(id)' has a green checkmark.")
                return
            }
            let url = container.appendingPathComponent("Documents/\(dataFolderName)", isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            _icloudBase = url
            print("[ProjectTracker] ✅ iCloud container resolved: \(url.path)")
            mergeLocalDataIntoCloud()
            CloudMetadataMonitor.shared.start()
            NotificationCenter.default.post(name: .iCloudContainerReady, object: nil)
        }
    }

    /// Retries iCloud container resolution. Call when the app foregrounds in case
    /// iCloud wasn't ready at launch (common on cold boots or after sign-in).
    static func retryIfNeeded() {
        resolveAsync()
    }

    /// Local Documents/<dataFolderName> — used when iCloud is unavailable.
    static var localFallback: URL {
        let url = UITestSupport.isActive
            ? UITestSupport.dataRoot
            : FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                .appendingPathComponent(dataFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Anything written to local storage before the container resolved (or while
    /// signed out of iCloud) gets moved into iCloud here. Runs on every resolve
    /// and after each metadata gather — each store's merge is idempotent and
    /// clears its local copy once safely merged, so repeat calls are cheap no-ops.
    static func mergeLocalDataIntoCloud() {
        guard isAvailable else { return }
        ResearchStore.mergeLocalIntoCloud()
        ArtifactsStore.mergeLocalIntoCloud()
        ProjectStore.mergeLocalIntoCloud()
    }

    // MARK: - Coordinated I/O

    /// Coordinated read. If the file lives in iCloud but isn't downloaded yet
    /// (iOS never auto-downloads), this starts the download and returns nil —
    /// `.iCloudFilesChanged` fires when it lands, and callers reload then.
    static func read(at url: URL) -> Data? {
        if downloadStatus(url) == .notDownloaded {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            return nil
        }
        var data: Data?
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { actualURL in
            data = try? Data(contentsOf: actualURL)
        }
        return data
    }

    /// Coordinated atomic write, creating parent directories as needed.
    /// Failures are reported to `StorageErrors` (shown as an alert) instead of
    /// being swallowed. Returns false when nothing was written.
    @discardableResult
    static func write(_ data: Data, to url: URL) -> Bool {
        let action = "save \(describe(url))"
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            StorageErrors.shared.report(action, error: error)
            return false
        }
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { actualURL in
            do { try data.write(to: actualURL, options: .atomic) } catch { writeError = error }
        }
        if let error = (coordinationError as Error?) ?? writeError {
            StorageErrors.shared.report(action, error: error)
            return false
        }
        return true
    }

    /// Coordinated copy of an external file (e.g. from the document picker) into the container.
    static func copyIn(from source: URL, to dest: URL) -> Bool {
        let action = "copy \(describe(dest))"
        do {
            try FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            StorageErrors.shared.report(action, error: error)
            return false
        }
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(writingItemAt: dest, options: .forReplacing, error: &coordinationError) { actualURL in
            if FileManager.default.fileExists(atPath: actualURL.path) {
                do { try FileManager.default.removeItem(at: actualURL) } catch { copyError = error; return }
            }
            do { try FileManager.default.copyItem(at: source, to: actualURL) } catch { copyError = error }
        }
        if let error = (coordinationError as Error?) ?? copyError {
            StorageErrors.shared.report(action, error: error)
            return false
        }
        return true
    }

    /// Coordinated delete. A file that is already gone is not an error.
    static func delete(at url: URL) {
        var coordinationError: NSError?
        var deleteError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { actualURL in
            do {
                try FileManager.default.removeItem(at: actualURL)
            } catch let error as NSError
                        where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
                // Nothing to delete.
            } catch {
                deleteError = error
            }
        }
        if let error = (coordinationError as Error?) ?? deleteError {
            StorageErrors.shared.report("delete \(describe(url))", error: error)
        }
    }

    /// Human-readable name for what lives at a container path, for alerts.
    private static func describe(_ url: URL) -> String {
        let path = url.path
        if path.contains("/projects/") { return "the project" }
        if path.contains("/notes/") { return "the stage notes" }
        if path.hasSuffix("/research/index.json") { return "the reference library" }
        if path.contains("/files/") { return "the attached PDF" }
        return "\"\(url.lastPathComponent)\""
    }

    /// Kicks off a download if the item exists in iCloud but isn't local yet.
    static func ensureDownloaded(_ url: URL) {
        guard downloadStatus(url) == .notDownloaded else { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    /// nil means the item doesn't exist (locally or in iCloud) or isn't ubiquitous.
    static func downloadStatus(_ url: URL) -> URLUbiquitousItemDownloadingStatus? {
        (try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?
            .ubiquitousItemDownloadingStatus
    }
}

// MARK: - Metadata monitor

/// Watches the app's iCloud Documents scope. iOS does not auto-download iCloud
/// Drive files, so on every gather/update this requests downloads for anything
/// still remote, then posts `.iCloudFilesChanged` so views refresh their lists.
final class CloudMetadataMonitor {
    static let shared = CloudMetadataMonitor()
    private let query = NSMetadataQuery()
    private var started = false
    private var observers: [NSObjectProtocol] = []

    /// Must be called on the main thread (NSMetadataQuery requirement).
    func start() {
        guard !started else { return }
        started = true
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
        let handler: (Notification) -> Void = { [weak self] _ in self?.processResults() }
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main, using: handler))
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate, object: query, queue: .main, using: handler))
        query.start()
    }

    private func processResults() {
        query.disableUpdates()
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  let status = item.value(
                      forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            else { continue }
            if status == NSMetadataUbiquitousItemDownloadingStatusNotDownloaded {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
        }
        query.enableUpdates()
        MainActor.assumeIsolated {
            // Local data stranded from a pre-resolution save may now be mergeable.
            CloudContainer.mergeLocalDataIntoCloud()
        }
        NotificationCenter.default.post(name: .iCloudFilesChanged, object: nil)
    }
}
