import SwiftUI

struct MorningInsightsView: View {
    let day: Date
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var morning = MorningInsightsStore()
    private var insights: MorningInsights? { morning.value(for: scope) }
    private var error: Bool { morning.failed(for: scope) }
    private var loading: Bool { morning.loading }
    @State private var showMethod = false
    @State private var history = TrendStore()
    @State private var metric: TrendMetric = .sleep
    @State private var detailNight: ZoopAPI.Night?
    @State private var showNight = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline).foregroundStyle(ZoopStyle.secondary)
                if error {
                    Button("Couldn’t update insights. Retry") { Task { await load() } }
                        .frame(minHeight: 44).accessibilityIdentifier("retryInsights")
                }
                if let insights {
                    HStack {
                        Text(insights.outlookTitle).font(.headline).foregroundStyle(InsightTone.color(insights.outlook?.state))
                            .accessibilityIdentifier("morningOutlookStatus")
                        Spacer()
                        if insights.isLearning, let outlook = insights.outlook {
                            Text("\(outlook.baselineCount)/\(outlook.baselineRequired) nights").font(.subheadline).foregroundStyle(ZoopStyle.secondary)
                        }
                    }
                    let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
                    layout {
                        ForEach(insights.metrics) { reading in
                            InsightMetricView(metric: reading, selected: metric == reading.trendMetric) { metric = reading.trendMetric }
                        }
                    }
                    TrendHistoryView(snapshot: history.snapshot, metric: metric, initialDay: day, insights: insights, initialRange: .week) { point in
                        detailNight = history.snapshot.nights.first { $0.endTs == point.date }; showNight = detailNight != nil
                    }
                    if history.error != nil {
                        Button("Couldn’t update history. Retry") { Task { await loadHistory() } }.frame(minHeight: 44)
                    }
                } else if loading {
                    ProgressView().frame(maxWidth: .infinity).accessibilityLabel("Loading morning insights")
                }
            }.padding(.horizontal, ZoopStyle.gutter).padding(.vertical, 16)
        }
        .navigationTitle("Morning insights").navigationBarTitleDisplayMode(.inline).zoopScreen()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showMethod = true } label: { Image(systemName: "info.circle") }.accessibilityLabel("About morning insights")
            }
        }
        .navigationDestination(isPresented: $showNight) { if let detailNight { TrendSleepDetailView(summary: detailNight) } }
        .task(id: "\(scope)-\(model.analysisRevision)-\(model.sleep.changeToken)-\(scenePhase)") {
            if scenePhase == .active { await loadHistory() }
        }
        .sheet(isPresented: $showMethod) { InsightMethodView() }
        .onAppear { visible = true }
        .onDisappear { visible = false; morning.stop() }
        .task(id: MorningInsightsStore.FollowKey(scope: scope, active: visible && scenePhase == .active)) {
            guard visible, scenePhase == .active, Settings.isConfigured else {
                morning.stop(clear: !Settings.isConfigured); return
            }
            let request = scope
            await morning.follow(request) { visible && scenePhase == .active && scope == request }
        }
        .refreshable { await load() }
        .onChange(of: model.sleep.changeToken) { _, _ in Task { await load() } }
        .onChange(of: model.analysisRevision) { _, _ in Task { await load() } }
    }
    private func loadHistory() async {
        let device = model.strap.serial, connection = Settings.connectionID
        await history.reload(device: device, connection: connection) { model.strap.serial == device && Settings.connectionID == connection }
    }
    private func load() async {
        guard Settings.isConfigured else { morning.stop(clear: true); return }
        let request = scope
        await morning.reload(request) { visible && scenePhase == .active && scope == request }
    }
    private var scope: MorningInsightsStore.Scope {
        .init(device: model.strap.serial, day: day, connection: Settings.connectionID, timezone: TimeZone.current.identifier)
    }
}
