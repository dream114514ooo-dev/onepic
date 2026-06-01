import SwiftUI
import SwiftData

#if os(iOS)
import UserNotifications

struct ReminderSettingsView: View {
    let project: Project

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var loc: LocalizationManager

    @State private var isEnabled: Bool
    @State private var time: Date
    @State private var isSaving = false
    @State private var showDeniedAlert = false

    init(project: Project) {
        self.project = project
        if let minutes = project.reminderMinutes {
            _isEnabled = State(initialValue: true)
            _time = State(initialValue: Self.dateFromMinutes(minutes))
        } else {
            _isEnabled = State(initialValue: false)
            _time = State(initialValue: Self.dateFromMinutes(20 * 60))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Toggle(loc.t("reminder.enable_daily"), isOn: $isEnabled)

                DatePicker(loc.t("reminder.time"), selection: $time, displayedComponents: .hourAndMinute)
                    .disabled(!isEnabled)
            }
            .navigationTitle(loc.t("reminder.settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(loc.t("common.cancel")) { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(loc.t("common.save")) { Task { await save() } }
                        .disabled(isSaving)
                }
            }
            .alert(loc.t("reminder.permission_denied.title"), isPresented: $showDeniedAlert) {
                Button(loc.t("common.ok"), role: .cancel) {}
            } message: {
                Text(loc.t("reminder.permission_denied.message"))
            }
        }
    }

    @MainActor
    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

#if os(iOS)
        let center = UNUserNotificationCenter.current()
#endif

        if !isEnabled {
            project.reminderMinutes = nil
            try? modelContext.save()
#if os(iOS)
            center.removePendingNotificationRequests(withIdentifiers: [Self.identifier(for: project.id)])
#endif
            dismiss()
            return
        }

        let minutes = Self.minutesFromDate(time)
        project.reminderMinutes = minutes
        try? modelContext.save()

#if os(iOS)
        let granted = await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                    continuation.resume(returning: true)
                    return
                }
                if settings.authorizationStatus == .denied {
                    continuation.resume(returning: false)
                    return
                }
                center.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
                    continuation.resume(returning: ok)
                }
            }
        }
        if !granted {
            showDeniedAlert = true
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier(for: project.id)])

        var comps = DateComponents()
        comps.hour = minutes / 60
        comps.minute = minutes % 60

        let content = UNMutableNotificationContent()
        content.title = loc.t("app.name")
        content.body = loc.tf("reminder.notification_body", project.name)
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(
            identifier: Self.identifier(for: project.id),
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
#endif

        dismiss()
    }

    private static func identifier(for projectID: UUID) -> String {
        "onepic.reminder.daily.\(projectID.uuidString)"
    }

    private static func minutesFromDate(_ date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    private static func dateFromMinutes(_ minutes: Int) -> Date {
        let h = minutes / 60
        let m = minutes % 60
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = h
        comps.minute = m
        return Calendar.current.date(from: comps) ?? Date()
    }
}
#else
struct ReminderSettingsView: View {
    let project: Project
    @EnvironmentObject private var loc: LocalizationManager

    var body: some View {
        Text(loc.t("platform.iphone_only_reminders"))
    }
}
#endif
