import SwiftUI
import ZoopHealth

struct AppleHealthView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var steps = false
    @State private var importWeight = true
    @State private var exportWeight = false
    @State private var connecting = false
    @State private var showBackfill = false
    @State private var showWeightImport = false
    @State private var confirmRemoval = false
    private var health: HealthCoordinator { model.health }
    var body: some View {
        Form {
            Section {
                Label(health.connected ? health.status : "Not connected", systemImage: "heart")
                    .font(ZoopType.headline)
                if connecting || health.busy { ZoopLoadingBar(label: connecting ? "Saving Health settings" : "Syncing Apple Health") }
                if let last = health.journal.lastSync { LabeledContent("Last synced", value: last.formatted(date: .abbreviated, time: .shortened)) }
                if let error = health.error {
                    Text(error).font(ZoopType.footnote).foregroundStyle(ZoopStyle.unfavourable)
                    Button("Retry sync") { health.checkSoon() }.disabled(health.busy)
                }
            }
            Section {
                permissionRow("Sleep", domain: "sleep")
                permissionRow("Workouts", domain: "workout")
                Toggle("Export steps", isOn: savingBinding($steps))
                    .disabled(controlsDisabled)
                Toggle("Export weight", isOn: savingBinding($exportWeight))
                    .disabled(controlsDisabled)
                if health.connected && !connecting && ((steps && !health.adapter.canWrite("steps")) || (exportWeight && !health.adapter.canWrite("weight"))) {
                    Text("Writing is not allowed in Apple Health.").foregroundStyle(ZoopStyle.unfavourable)
                    Button("Review Health permissions") { saveSettings() }
                        .disabled(controlsDisabled)
                }
            } header: { Text("Share with Apple Health") } footer: {
                Text("If another app shares sleep or workouts, choose one exporter in Health. Steps follow Health’s source priority.")
            }
            Section {
                Toggle("Import weight", isOn: savingBinding($importWeight))
                    .disabled(controlsDisabled)
                Button("Import weight history") { showWeightImport = true }
                    .accessibilityIdentifier("healthWeightImport")
            } header: { Text("Weight") } footer: {
                Text("Imported weights sync to your Zoop server. Originals in Health stay unchanged.")
            }
            if exportWeight {
                Section {
                    Text("Zoop skips dates with another weight it can read. Apple hides read-permission status, so an empty result may mean no access. Weight export can add an overlapping entry.")
                        .font(ZoopType.footnote).foregroundStyle(ZoopStyle.secondary)
                }
            }
            Section {
                if !health.connected {
                    Button("Connect Apple Health") { saveSettings() }
                        .disabled(controlsDisabled)
                }
                if health.connected {
                    Button("Export older Zoop history") { showBackfill = true }.disabled(health.busy)
                    Button(health.journal.paused ? "Resume syncing" : "Pause syncing") { health.pause(!health.journal.paused) }
                    Button("Disconnect Apple Health") { health.disconnect() }.disabled(health.busy)
                    Button("Remove Zoop exports", role: .destructive) { confirmRemoval = true }.disabled(health.busy)
                }
            } footer: { Text("Automatic sharing starts when you connect. Pausing keeps records already in Health.") }
        }
        .scrollContentBackground(.hidden).zoopScreen().tint(ZoopStyle.text)
        .navigationTitle("Apple Health").navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshSettings() }
        .onChange(of: health.connected) { _, _ in refreshSettings() }
        .onChange(of: scenePhase) { _, phase in if phase == .active && !connecting { refreshSettings() } }
        .sheet(isPresented: $showBackfill) { HealthBackfillView() }
        .sheet(isPresented: $showWeightImport) { WeightImportView() }
        .confirmationDialog("Remove Zoop exports from Health?", isPresented: $confirmRemoval) {
            Button("Remove Zoop exports", role: .destructive) { Task { await health.removeExports() } }
        } message: { Text("Removes only exports from this Zoop connection and disconnects Health. Your Zoop history and other apps’ records stay unchanged.") }
    }
    private var controlsDisabled: Bool { connecting || health.busy || !health.adapter.available }
    private func refreshSettings() {
        guard health.connected else { return }
        steps = health.journal.exportSteps
        importWeight = health.journal.importWeight
        exportWeight = health.journal.exportWeight
    }
    private func savingBinding(_ value: Binding<Bool>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue }, set: { newValue in
            guard !controlsDisabled else { return }
            value.wrappedValue = newValue
            if health.connected { saveSettings() }
        })
    }
    private func saveSettings() {
        guard !controlsDisabled else { return }
        connecting = true
        let resumeSync = !health.connected
        Task {
            await health.connect(steps: steps, importWeight: importWeight, exportWeight: exportWeight, resumeSync: resumeSync)
            refreshSettings()
            connecting = false
        }
    }
    private func permissionRow(_ title: String, domain: String) -> some View {
        LabeledContent(title, value: health.connected ? (health.adapter.canWrite(domain) ? "Allowed" : "Not allowed") : "Ask on connection")
    }
}
