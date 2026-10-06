import Foundation

/// Hooks used only when the UI tests launch the app.
///
/// `--ui-testing` keeps every file in a scratch folder and skips iCloud, so
/// tests never touch real data. `--ui-testing-reset` additionally wipes that
/// folder and the app's preferences at launch, giving each test the same
/// first-run state. Both are no-ops in normal use.
enum UITestSupport {
    static let isActive = ProcessInfo.processInfo.arguments.contains("--ui-testing")
    private static let shouldReset = ProcessInfo.processInfo.arguments.contains("--ui-testing-reset")

    /// Apple Intelligence is off under UI tests so they don't depend on the
    /// device's model; `--ui-testing-ai` keeps it on for the on-device check.
    static let blocksAppleIntelligence = isActive
        && !ProcessInfo.processInfo.arguments.contains("--ui-testing-ai")

    /// Replaces the iCloud / Documents data folder while testing.
    static var dataRoot: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectTrackerUITests", isDirectory: true)
    }

    /// `--open-tab=library` (or `pipeline`) chooses the tab shown at launch.
    /// Used by UI tests and for screenshots; ignored without `--ui-testing`.
    static var initialTab: AppTab? {
        guard isActive else { return nil }
        for arg in ProcessInfo.processInfo.arguments where arg.hasPrefix("--open-tab=") {
            switch arg.dropFirst("--open-tab=".count) {
            case "library":  return .library
            case "pipeline": return .pipeline
            default:         return nil
            }
        }
        return nil
    }

    /// `--open-settings` presents the Settings sheet right after launch.
    static var opensSettingsAtLaunch: Bool {
        isActive && ProcessInfo.processInfo.arguments.contains("--open-settings")
    }

    /// `--open-paste=<file>` opens the new-project paste sheet filled with that
    /// file's text. Used for store screenshots; ignored without `--ui-testing`.
    static var pasteTextAtLaunch: String? {
        guard isActive else { return nil }
        for arg in ProcessInfo.processInfo.arguments where arg.hasPrefix("--open-paste=") {
            return try? String(contentsOfFile: String(arg.dropFirst("--open-paste=".count)), encoding: .utf8)
        }
        return nil
    }

    /// `--window-size=1240x1000` sets the Mac window's content size at launch,
    /// for store screenshots; ignored without `--ui-testing`.
    static var windowSizeAtLaunch: CGSize? {
        guard isActive else { return nil }
        for arg in ProcessInfo.processInfo.arguments where arg.hasPrefix("--window-size=") {
            let parts = arg.dropFirst("--window-size=".count).split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 { return CGSize(width: parts[0], height: parts[1]) }
        }
        return nil
    }

    /// Call once at launch, before anything reads preferences or files.
    static func resetIfNeeded() {
        guard isActive, shouldReset else { return }
        try? FileManager.default.removeItem(at: dataRoot)
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        ProgressStore.defaults?.removePersistentDomain(forName: ProgressStore.appGroupID)
    }
}
