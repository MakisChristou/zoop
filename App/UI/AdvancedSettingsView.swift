import SwiftUI

struct AdvancedSettingsView: View {
    var body: some View {
        List {
            Section {
                NavigationLink { ServerSettingsView() } label: { Label("Server connection", systemImage: "network") }
                NavigationLink { AnalysisResetView() } label: { Label("Reset to automatic", systemImage: "arrow.counterclockwise") }
                NavigationLink { DiagnosticsView() } label: { Label("Diagnostics", systemImage: "waveform.path.ecg.rectangle") }
            }
            .listRowBackground(SnoopStyle.surface)
        }
        .scrollContentBackground(.hidden)
        .snoopScreen()
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
    }
}
