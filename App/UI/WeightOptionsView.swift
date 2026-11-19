import SwiftUI
import ZoopHealth

struct WeightOptionsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("weightUnit") private var unit = "kg"
    @AppStorage("weightMovingAverage") private var showAverage = false
    @State private var importing = false
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var preparingExport = false
    @State private var exportRequest = UUID()
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
                    NavigationLink { WeightHistoryView() } label: { Label("All weigh-ins", systemImage: "list.bullet") }
                        .accessibilityIdentifier("weightHistory")
                    Button { importing = true } label: { Label("Import weight history", systemImage: "heart") }
                        .accessibilityIdentifier("importWeightFromOptions")
                    if let exportURL {
                        ShareLink(item: exportURL) { Label("Export CSV", systemImage: "square.and.arrow.up") }
                            .accessibilityIdentifier("exportWeightCSV")
                            .accessibilityHint("All saved weigh-ins, in kilograms.")
                    } else {
                        HStack { Label("Export CSV", systemImage: "square.and.arrow.up"); Spacer(); if preparingExport { ProgressView().controlSize(.small).accessibilityLabel("Preparing CSV") } }
                            .foregroundStyle(ZoopStyle.secondary)
                            .accessibilityIdentifier("exportWeightCSVUnavailable")
                    }
                    if let exportError { Text(exportError).foregroundStyle(ZoopStyle.unfavourable) }
                }
            }
            .scrollContentBackground(.hidden).zoopScreen().tint(ZoopStyle.text)
            .navigationTitle("Weight options").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $importing) { WeightImportView() }
            .task { await model.battery.refreshAuthorization() }
            .task(id: model.health.rows) {
                let request = UUID(); exportRequest = request
                preparingExport = false
                exportURL = nil; exportError = nil
                let rows = model.health.rows, timeZone = TimeZone.current
                guard !rows.isEmpty else { return }
                preparingExport = true
                defer { if exportRequest == request { preparingExport = false } }
                let result = await Task.detached(priority: .userInitiated) { () -> (URL?, String?) in
                    do {
                        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WeightExport-" + UUID().uuidString, isDirectory: true)
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        let url = folder.appendingPathComponent("Zoop-weight.csv")
                        try WeightCSV.encode(rows, timeZone: timeZone).write(to: url, atomically: true, encoding: .utf8)
                        return (url, nil)
                    } catch { return (nil, "Couldn’t prepare CSV. Reopen this page to retry.") }
                }.value
                guard !Task.isCancelled, exportRequest == request else { return }
                exportURL = result.0; exportError = result.1
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.battery.refreshAuthorization() } } }
        }
    }
}
