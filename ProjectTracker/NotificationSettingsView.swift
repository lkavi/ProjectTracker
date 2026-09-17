import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    let stages: [ProjectStage]
    @State private var prefs: [StageNotificationPref]
    @State private var bufferDays: Int = ProgressStore.loadBufferDays()
    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var cloudStatus: CloudContainer.SyncStatus = CloudContainer.status
    @Environment(\.dismiss) var dismiss

    init(stages: [ProjectStage]) {
        self.stages = stages
        _prefs = State(initialValue: NotificationStore.load(for: stages))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings")
                        .font(.title2.bold())
                    Text("Personalise your deadlines and daily reminders.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .controlSize(.large)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── General ──────────────────────────────────────────
                    sectionHeader("GENERAL")

                    targetCard

                    // ── Notifications ─────────────────────────────────────
                    sectionHeader("DAILY REMINDERS")

                    if authStatus == .denied {
                        permissionDeniedBanner
                    } else if authStatus == .notDetermined {
                        requestPermissionBanner
                    }

                    VStack(spacing: 10) {
                        ForEach($prefs) { $pref in
                            if let index = stages.firstIndex(where: { $0.id == pref.id }) {
                                StageNotifRowView(pref: $pref, stage: stages[index], number: index + 1)
                            }
                        }
                    }

                    // ── iCloud ───────────────────────────────────────────
                    sectionHeader("ICLOUD SYNC")
                    iCloudStatusCard
                }
                .padding(20)
            }
        }
        #if os(macOS)
        .frame(minWidth: 580, idealWidth: 620, minHeight: 520, idealHeight: 720)
        #endif
        .onAppear {
            NotificationStore.checkPermission { authStatus = $0 }
            cloudStatus = CloudContainer.status
        }
        .onChange(of: prefs) { _, newValue in NotificationStore.save(newValue, stages: stages) }
        .onChange(of: bufferDays) { _, newValue in ProgressStore.saveBufferDays(newValue) }
        .onReceive(NotificationCenter.default.publisher(for: .iCloudContainerReady)) { _ in
            cloudStatus = CloudContainer.status
        }
    }

    // MARK: - Target buffer card

    /// Side by side on the Mac; stacked on iPhone, where a fixed-width picker
    /// next to the description squeezed the text into a narrow column.
    @ViewBuilder
    private var targetCard: some View {
        #if os(iOS)
        VStack(alignment: .leading, spacing: 12) {
            targetCardText
            HStack {
                Text("Finish")
                    .font(.callout)
                Spacer()
                bufferPicker.labelsHidden()
            }
        }
        .padding(14)
        .background(Color.appControlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        #else
        HStack(spacing: 14) {
            targetCardText
            Spacer()
            bufferPicker.frame(width: 170)
        }
        .padding(14)
        .background(Color.appControlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        #endif
    }

    private var targetCardText: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Personal target deadline")
                .font(.callout.bold())
            Text("How many days before the official deadline you want to finish. Shown as 'Your Target' in the app and widget.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bufferPicker: some View {
        Picker("Target buffer", selection: $bufferDays) {
            Text("Same day").tag(0)
            Text("1 day early").tag(1)
            Text("2 days early").tag(2)
            Text("3 days early").tag(3)
            Text("5 days early").tag(5)
            Text("1 week early").tag(7)
        }
    }

    // MARK: - iCloud status card

    @ViewBuilder
    private var iCloudStatusCard: some View {
        switch cloudStatus {
        case .syncing:
            HStack(spacing: 10) {
                Image(systemName: "checkmark.icloud").foregroundStyle(.green).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Syncing").font(.callout.bold()).foregroundStyle(.green)
                    Text("Projects, notes, PDFs and references sync automatically across your Mac and iPhone.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(Color.green.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 10))

        case .notSignedIn:
            iCloudActionBanner(
                icon: "icloud.slash",
                title: "Not signed in to iCloud",
                message: "Sign in with your Apple Account to sync projects, notes and PDFs across devices. Everything stays on this device only until then.",
                buttonTitle: "Open Apple Account Settings",
                action: openAppleIDSettings
            )

        case .driveAccessNeeded:
            iCloudActionBanner(
                icon: "icloud.slash",
                title: "iCloud Drive access needed",
                message: platformDriveAccessMessage,
                buttonTitle: "Open Settings",
                action: openAppleIDSettings
            )
        }
    }

    private var platformDriveAccessMessage: String {
        #if os(macOS)
        "Go to System Settings → your name → iCloud → iCloud Drive, turn it on, then make sure \"Project Tracker\" is enabled under Apps Using iCloud Drive."
        #else
        "Go to Settings → your name → iCloud → iCloud Drive, turn it on, then scroll down and enable \"Project Tracker\" in the apps list."
        #endif
    }

    private func iCloudActionBanner(
        icon: String, title: String, message: String, buttonTitle: String, action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(.orange).font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.bold()).foregroundStyle(.orange)
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(buttonTitle, action: action).font(.caption).padding(.top, 2)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func openAppleIDSettings() {
        #if os(macOS)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane")!)
        #else
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
    }

    // MARK: - Permission banners

    private var requestPermissionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.badge")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications not yet enabled")
                    .font(.callout.bold())
                    .foregroundStyle(.orange)
                Text("Grant permission so reminders can be delivered.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Allow") {
                NotificationStore.requestPermission { _ in
                    NotificationStore.checkPermission { authStatus = $0 }
                }
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var permissionDeniedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.slash")
                .foregroundStyle(.red)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications are blocked")
                    .font(.callout.bold())
                    .foregroundStyle(.red)
                #if os(macOS)
                Text("Go to System Settings → Notifications → Project Tracker to turn them on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #else
                Text("Go to Settings → Notifications → Project Tracker to turn them on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #endif
            }
            Spacer()
            Button("Open Settings") {
                #if os(macOS)
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                #else
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                #endif
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Per-stage notification row

struct StageNotifRowView: View {
    @Binding var pref: StageNotificationPref
    let stage: ProjectStage
    let number: Int

    // Mon → Sun ordering (Calendar weekday: 1=Sun … 7=Sat)
    private let weekdayOrder:  [Int]    = [2, 3, 4, 5, 6, 7, 1]
    private let weekdayLabels: [String] = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $pref.isEnabled) {
                HStack(spacing: 8) {
                    Text("Stage \(number)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .leading)
                    Text(stage.title)
                        .font(.callout.bold())
                    Spacer()
                    Text(stage.dueText())
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            if pref.isEnabled {
                // Time and weekday controls need about 350pt side by side,
                // which doesn't fit an iPhone card, so they stack there.
                #if os(iOS)
                VStack(alignment: .leading, spacing: 10) {
                    timeControls
                    weekdayControls
                }
                .padding(.leading, 4)
                #else
                HStack(spacing: 20) {
                    timeControls
                    Spacer()
                    weekdayControls
                }
                .padding(.leading, 4)
                #endif
            }
        }
        .padding(14)
        .background(Color.appControlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var timeControls: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Hour", selection: $pref.hour) {
                ForEach(0..<24, id: \.self) { h in
                    Text(String(format: "%02d", h)).tag(h)
                }
            }
            .labelsHidden()
            .frame(width: 62)
            Text(":")
                .foregroundStyle(.secondary)
            Picker("Minute", selection: $pref.minute) {
                ForEach([0, 15, 30, 45], id: \.self) { m in
                    Text(String(format: "%02d", m)).tag(m)
                }
            }
            .labelsHidden()
            .frame(width: 62)
        }
    }

    private var weekdayControls: some View {
        HStack(spacing: 4) {
            ForEach(Array(weekdayOrder.enumerated()), id: \.offset) { i, wd in
                let on = pref.weekdays.contains(wd)
                Button(action: {
                    if on { pref.weekdays.remove(wd) }
                    else  { pref.weekdays.insert(wd) }
                }) {
                    Text(weekdayLabels[i])
                        .font(.caption.monospaced().bold())
                        .frame(width: 28, height: 26)
                        .background(on ? Color.blue : Color.appControlBackground.opacity(0.6))
                        .foregroundStyle(on ? .white : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    NotificationSettingsView(stages: [
        ProjectStage(title: "Literature Review", deadline: "2026-09-17",
                     tasks: [ProjectTask(title: "Find papers")]),
    ])
}
