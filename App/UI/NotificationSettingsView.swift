import SwiftUI

struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Form {
            Section {
                Toggle("Weigh-in", isOn: Binding(get: { model.health.canRemind }, set: { model.health.setReminder($0); requestPermission() }))
                    .accessibilityIdentifier("weightReminderEnabled")
                if model.health.canRemind {
                    DatePicker("Time", selection: time(get: { model.reminders.weightMinute }, set: { model.reminders.weightMinute = $0 }), displayedComponents: .hourAndMinute)
                        .accessibilityLabel("Weigh-in time").accessibilityIdentifier("weightReminderTime")
                }
                if BuildFeatures.manualECG {
                    Toggle("ECG", isOn: Binding(get: { model.reminders.ecgEnabled }, set: { model.reminders.ecgEnabled = $0; requestPermission() }))
                        .accessibilityIdentifier("ecgReminderEnabled")
                    if model.reminders.ecgEnabled {
                        DatePicker("Time", selection: time(get: { model.reminders.ecgMinute }, set: { model.reminders.ecgMinute = $0 }), displayedComponents: .hourAndMinute)
                            .accessibilityLabel("ECG time").accessibilityIdentifier("ecgReminderTime")
                    }
                }
            } header: { Text("Daily check-ins") } footer: { Text("Skipped once you’ve checked in.") }
            .listRowBackground(ZoopStyle.surface)
            Section("My WHOOP") {
                Toggle("Battery alerts", isOn: Binding(get: { model.battery.alertsEnabled }, set: { model.battery.alertsEnabled = $0; requestPermission() }))
                if OffBodyMonitor.available {
                    Toggle(isOn: Binding(get: { model.offBody.enabled }, set: { model.offBody.enabled = $0; requestPermission() })) {
                        VStack(alignment: .leading, spacing: 3) { Text("Off-body"); Text("After 10 minutes").font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary) }
                    }.accessibilityIdentifier("offBodyReminderEnabled")
                }
            }.listRowBackground(ZoopStyle.surface)
            if model.weeklyWeight.goal?.dailyStepsGoal != nil {
                Section("Cut steps") {
                    Toggle("Goal completions", isOn: Binding(get: { model.stepsReminder.completion.enabled }, set: { model.stepsReminder.completion.enabled = $0; requestPermission(); model.stepsReminder.refresh(force: true) }))
                        .accessibilityIdentifier("stepsCompletionEnabled")
                    if let error = model.stepsReminder.completion.error { Text(error).foregroundStyle(ZoopStyle.secondary); Button("Retry") { model.stepsReminder.refresh(force: true) } }
                    Toggle("Steps reminder", isOn: Binding(get: { model.stepsReminder.enabled }, set: { model.stepsReminder.enabled = $0; requestPermission(); model.stepsReminder.refresh(force: true) }))
                    if model.stepsReminder.enabled { DatePicker("Time", selection: time(get: { model.stepsReminder.minute }, set: { model.stepsReminder.minute = $0 }), displayedComponents: .hourAndMinute) }
                    if let error = model.stepsReminder.error { Text(error).foregroundStyle(ZoopStyle.secondary); Button("Retry") { model.stepsReminder.refresh(force: true) } }
                }.listRowBackground(ZoopStyle.surface)
            }
            Section {
                if model.battery.authorization == .notDetermined {
                    Button("Allow notifications", action: requestPermission)
                } else {
                    Button("iPhone notification settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                if model.battery.authorization == .denied { Text("Notifications are off for Zoop.").foregroundStyle(ZoopStyle.secondary) }
                if let error = model.reminders.error {
                    Text(error).foregroundStyle(ZoopStyle.secondary)
                    Button("Retry") { model.refreshReminders() }
                }
            }.listRowBackground(ZoopStyle.surface)
        }.scrollContentBackground(.hidden).zoopScreen().tint(ZoopStyle.text)
            .navigationTitle("Notifications").navigationBarTitleDisplayMode(.inline)
            .task { await model.battery.refreshAuthorization(); model.refreshReminders() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.battery.refreshAuthorization(); model.refreshReminders() } } }
    }
    private func requestPermission() {
        guard ((model.stepsReminder.enabled || model.stepsReminder.completion.enabled) && model.weeklyWeight.goal?.dailyStepsGoal != nil) || model.health.canRemind || (BuildFeatures.manualECG && model.reminders.ecgEnabled) || model.battery.alertsEnabled || (OffBodyMonitor.available && model.offBody.enabled) else { return }
        Task { await model.battery.requestNotificationsIfNeeded(); model.refreshReminders() }
    }
    private func time(get: @escaping () -> Int, set: @escaping (Int) -> Void) -> Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: get() / 60, minute: get() % 60, second: 0, of: Date()) ?? Date() }, set: {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
            set((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        })
    }
}
