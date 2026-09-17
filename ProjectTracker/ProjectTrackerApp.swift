import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct ProjectTrackerApp: App {
    init() {
        // UI tests start from an isolated, empty data set (no-op otherwise).
        UITestSupport.resetIfNeeded()
        // Fetch the latest iCloud KV values before the first view appears.
        NSUbiquitousKeyValueStore.default.synchronize()
        // Resolve iCloud Drive container on a background thread (Apple-recommended).
        // Posts .iCloudContainerReady when done so ContentView can reload file lists.
        CloudContainer.resolveAsync()
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup("Project Tracker") {
            ContentView()
                .onOpenURL { _ in
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first?.makeKeyAndOrderFront(nil)
                }
        }
        .windowResizability(.contentSize)
        #else
        WindowGroup {
            ContentView()
        }
        #endif
    }
}
