import SwiftUI
import SnoopHealth

struct AppleHealthView: View {
    @EnvironmentObject private var model: AppModel
    @State private var steps = false
    @State private var importWeight = true
    @State private var exportWeight = false
    @State private var connecting = false
    @State private var showBackfill = false
    @State private var confirmRemoval = false
    private var health: HealthCoordinator { model.health }
    var body: some View {
        Form {
            Section {
                Label(health.connected ? health.status : "Not connected", systemImage: "heart")
                    .font(.headline)
                if let last = health.journal.lastSync { LabeledContent("Last synced", value: last.formatted(date: .abbreviated, time: .shortened)) }
                if let error = health.error {
                    Text(error).font(.footnote).foregroundStyle(SnoopStyle.unfavourable)
                    Button("Retry sync") { health.checkSoon() }.disabled(health.busy)
                }
            }
            Section {
                permissionRow("Sleep", domain: "sleep")
                permissionRow("Workouts", domain: "workout")
                Toggle("Export steps", isOn: $steps)
                Toggle("Export weight", isOn: $exportWeight)
            } header: { Text("Share with Apple Health") } footer: {
                Text("If another app shares sleep or workouts, choose one exporter in Health. Steps follow Health’s source priority.")
            }
            Section {
                Toggle("Import weight", isOn: $importWeight)
                NavigationLink("Weight history") { WeightView() }
            } header: { Text("Weight") } footer: {
                Text("Imported weights are saved to your Snoop server with their date and source. Other apps’ records stay unchanged.")
            }
            if exportWeight {
                Section {
                    Text("Snoop skips dates with another weight it can read. Apple hides read-permission status, so an empty result may mean no access. Weight export can add an overlapping entry.")
                        .font(.footnote).foregroundStyle(SnoopStyle.secondary)
                }
            }
            Section {
                Button(health.connected ? "Update permissions" : "Connect Apple Health") {
                    connecting = true
                    Task { await health.connect(steps: steps, importWeight: importWeight, exportWeight: exportWeight); connecting = false }
                }
                .disabled(connecting || health.busy || !health.adapter.available)
                if connecting { ProgressView().accessibilityLabel("Connecting Apple Health") }
                if health.connected {
                    Button("Sync older history") { showBackfill = true }.disabled(health.busy)
                    Button(health.journal.paused ? "Resume syncing" : "Pause syncing") { health.pause(!health.journal.paused) }
                    Button("Disconnect Apple Health") { health.disconnect() }.disabled(health.busy)
                    Button("Remove Snoop exports", role: .destructive) { confirmRemoval = true }.disabled(health.busy)
                }
            } footer: { Text("Automatic sharing starts when you connect. Pausing keeps records already in Health.") }
        }
        .scrollContentBackground(.hidden).snoopScreen().tint(SnoopStyle.load)
        .navigationTitle("Apple Health").navigationBarTitleDisplayMode(.inline)
        .onAppear { if health.connected { steps = health.journal.exportSteps; importWeight = health.journal.importWeight; exportWeight = health.journal.exportWeight } }
        .sheet(isPresented: $showBackfill) { HealthBackfillView() }
        .confirmationDialog("Remove Snoop exports from Health?", isPresented: $confirmRemoval) {
            Button("Remove Snoop exports", role: .destructive) { Task { await health.removeExports() } }
        } message: { Text("Removes only exports from this Snoop connection and disconnects Health. Your Snoop history and other apps’ records stay unchanged.") }
    }
    private func permissionRow(_ title: String, domain: String) -> some View {
        LabeledContent(title, value: health.connected ? (health.adapter.canWrite(domain) ? "Allowed" : "Not allowed") : "Ask on connection")
    }
}
