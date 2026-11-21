import SwiftUI

struct RecoveryDetailView: View {
    let day: Date
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var morning = MorningInsightsStore()
    @State private var showMethod = false
    @State private var selectedDay: Date?
    @State private var timezone = TimeZone.current.identifier
    @State private var refreshID = 0
    private var insights: MorningInsights? { morning.value(for: scope) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RecoveryHistoryView(initialDay: day, refreshID: refreshID, detail: true, insights: insights) { date, zone in
                    selectedDay = date; timezone = zone
                }
                if selectedDay != nil, morning.failed(for: scope) {
                    Button("Couldn’t update details. Retry") { Task { await load() } }
                        .frame(minHeight: 44).accessibilityIdentifier("retryRecovery")
                }
            }.padding(ZoopStyle.gutter)
        }
        .navigationTitle("Recovery").navigationBarTitleDisplayMode(.inline).zoopScreen()
        .toolbar(.visible, for: .navigationBar)
        .zoopLoading(morning.loading, label: "Loading recovery")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showMethod = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("About recovery")
            }
        }
        .sheet(isPresented: $showMethod) { RecoveryMethodView() }
        .onAppear { visible = true }
        .onDisappear { visible = false; morning.stop() }
        .task(id: MorningInsightsStore.FollowKey(scope: scope, active: visible && scenePhase == .active && selectedDay != nil)) {
            guard visible, scenePhase == .active, selectedDay != nil, Settings.isConfigured else {
                morning.stop(clear: !Settings.isConfigured); return
            }
            let request = scope
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            await morning.follow(request) { visible && scenePhase == .active && selectedDay != nil && scope == request }
        }
        .refreshable { refreshID += 1; await load() }
        .onChange(of: model.sleep.changeToken) { _, _ in Task { await load() } }
        .onChange(of: model.analysisRevision) { _, _ in Task { await load() } }
    }

    private var scope: MorningInsightsStore.Scope {
        .init(device: model.dataDevice, day: selectedDay ?? day, connection: Settings.connectionID, timezone: timezone)
    }
    private func load() async {
        guard Settings.isConfigured, selectedDay != nil else { morning.stop(clear: true); return }
        let request = scope
        await morning.reload(request) { visible && scenePhase == .active && selectedDay != nil && scope == request }
    }
}
