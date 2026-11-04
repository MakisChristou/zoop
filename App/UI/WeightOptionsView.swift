import SwiftUI

struct WeightOptionsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("weightUnit") private var unit = "kg"
    @AppStorage("weightMovingAverage") private var showAverage = false
    @State private var importing = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Morning reminder", isOn: Binding(get: { model.health.canRemind }, set: { enabled in
                        model.health.setReminder(enabled)
                        if enabled { Task { await model.battery.requestNotificationsIfNeeded(); model.health.checkSoon() } }
                    }))
                    if model.battery.authorization == .denied {
                        Text("Notifications are off for Snoop.").font(.footnote).foregroundStyle(SnoopStyle.secondary)
                        Button("Open iPhone Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    } else if model.battery.authorization == .notDetermined {
                        Button("Allow notifications") { Task { await model.battery.requestNotificationsIfNeeded(); model.health.checkSoon() } }
                    }
                } footer: {
                    Text("After your wake-up is confirmed. Skipped when today’s weight is recorded.")
                }
                Section("Chart") {
                    Toggle("7-day moving average", isOn: $showAverage).accessibilityIdentifier("weightMovingAverage")
                    Picker("Weight unit", selection: $unit) { Text("Kilograms").tag("kg"); Text("Pounds").tag("lb") }
                }
                Section {
                    Button { importing = true } label: { Label("Import weight history", systemImage: "heart") }
                        .accessibilityIdentifier("importWeightFromOptions")
                }
            }
            .scrollContentBackground(.hidden).snoopScreen().tint(SnoopStyle.load)
            .navigationTitle("Weight options").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $importing) { WeightImportView() }
            .task { await model.battery.refreshAuthorization() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.battery.refreshAuthorization() } } }
        }
    }
}
