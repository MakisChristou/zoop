import SwiftUI
import SnoopHealth

struct WeightOptionsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("weightUnit") private var unit = "kg"
    @AppStorage("weightMovingAverage") private var showAverage = false
    @State private var importing = false
    @State private var settingGoal = false
    @State private var exportURL: URL?
    @State private var exportError: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink("Reminders") { NotificationSettingsView() }
                }
                Section {
                    if model.weeklyWeight.goal?.active == true {
                        NavigationLink("Weekly outlook") { WeeklyWeightView() }.accessibilityIdentifier("weightGoalOptions")
                    } else {
                        Button("Start a cut") { settingGoal = true }.accessibilityIdentifier("weightGoalOptions").disabled(!model.weeklyWeight.loaded)
                    }
                    if let error = model.weeklyWeight.error {
                        Text(error).foregroundStyle(SnoopStyle.secondary)
                        Button("Retry") { Task { await model.weeklyWeight.reload() } }
                            .disabled(model.weeklyWeight.loading)
                    }
                }
                Section("Chart") {
                    Toggle("7-day moving average", isOn: $showAverage).accessibilityIdentifier("weightMovingAverage")
                    Picker("Weight unit", selection: $unit) { Text("Kilograms").tag("kg"); Text("Pounds").tag("lb") }
                }
                Section {
                    NavigationLink { WeightHistoryView() } label: { Label("All weigh-ins", systemImage: "list.bullet") }
                        .accessibilityIdentifier("weightHistory")
                    Button { importing = true } label: { Label("Import weight history", systemImage: "heart") }
                        .accessibilityIdentifier("importWeightFromOptions")
                    if let exportURL {
                        ShareLink(item: exportURL) { Label("Export CSV", systemImage: "square.and.arrow.up") }
                            .accessibilityIdentifier("exportWeightCSV")
                            .accessibilityHint("All saved weigh-ins, in kilograms.")
                    } else {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                            .foregroundStyle(SnoopStyle.secondary)
                            .accessibilityIdentifier("exportWeightCSVUnavailable")
                    }
                    if let exportError { Text(exportError).foregroundStyle(SnoopStyle.unfavourable) }
                }
            }
            .scrollContentBackground(.hidden).snoopScreen().tint(SnoopStyle.load)
            .navigationTitle("Weight options").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $settingGoal) { WeightGoalSetupView(onSaved: { dismiss() }) }
            .sheet(isPresented: $importing) { WeightImportView() }
            .task { await model.battery.refreshAuthorization() }
            .task { await model.weeklyWeight.reload() }
            .task(id: model.health.rows) {
                exportURL = nil; exportError = nil
                let rows = model.health.rows, timeZone = TimeZone.current
                guard !rows.isEmpty else { return }
                let result = await Task.detached(priority: .userInitiated) { () -> (URL?, String?) in
                    do {
                        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WeightExport-" + UUID().uuidString, isDirectory: true)
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        let url = folder.appendingPathComponent("Snoop-weight.csv")
                        try WeightCSV.encode(rows, timeZone: timeZone).write(to: url, atomically: true, encoding: .utf8)
                        return (url, nil)
                    } catch { return (nil, "Couldn’t prepare CSV. Reopen this page to retry.") }
                }.value
                guard !Task.isCancelled else { return }
                exportURL = result.0; exportError = result.1
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.battery.refreshAuthorization() } } }
        }
    }
}
