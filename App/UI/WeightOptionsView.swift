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
                    NavigationLink("Reminders") { NotificationSettingsView() }
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
