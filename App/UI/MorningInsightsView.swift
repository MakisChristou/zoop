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
            VStack(alignment: .leading, spacing: 20) {
                summary
                if error {
                    Button("Couldn’t update insights. Retry") { Task { await load() } }
                        .frame(minHeight: 44).accessibilityIdentifier("retryInsights")
                }
                TrendHistoryView(snapshot: history.snapshot, metric: metric, initialDay: day,
                                 insights: insights, initialRange: .week, integrated: true) { point in
                    detailNight = history.snapshot.nights.first { $0.endTs == point.date }; showNight = detailNight != nil
                }
                if history.error != nil {
                    Button("Couldn’t update history. Retry") { Task { await loadHistory() } }.frame(minHeight: 44)
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
    private var pending: Bool {
        loading || history.loading || insights?.state == "updating"
    }
    private var summary: some View {
        VStack(alignment: .leading, spacing: 20) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center) { summaryDate; Spacer(minLength: 12); summaryStatus }
                VStack(alignment: .leading, spacing: 8) { summaryDate; summaryStatus }
            }
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            layout {
                if let insights, !insights.metrics.isEmpty {
                    ForEach(insights.metrics) { reading in
                        InsightMetricView(metric: reading, selected: metric == reading.trendMetric,
                                          reservesComparison: insights.metrics.contains { $0.visibleDelta != nil }) { metric = reading.trendMetric }
                            .overlay(alignment: .trailing) {
                                if !typeSize.isAccessibilitySize, reading.id != insights.metrics.last?.id {
                                    Rectangle().fill(ZoopStyle.separator.opacity(0.6))
                                        .frame(width: 0.5, height: 44).offset(x: 8)
                                        .accessibilityHidden(true)
                                }
                            }
                    }
                } else {
                    ForEach(["Sleep", "HRV", "Resting HR"], id: \.self) { title in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(title).font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                            Text("—").font(ZoopType.title3)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }.zoopCard()
    }
    private var summaryDate: some View {
        Text(day.formatted(.dateTime.day().month(.abbreviated)))
            .font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary)
    }
    @ViewBuilder private var summaryStatus: some View {
        if pending {
            ProgressView().tint(ZoopStyle.secondary)
                .accessibilityLabel("Updating morning insights")
                .accessibilityIdentifier("morningInsightsLoading")
        } else if let insights {
            Text(insights.outlookTitle).font(ZoopType.subheadline)
                .foregroundStyle(InsightTone.color(insights.outlook?.state))
                .accessibilityIdentifier("morningOutlookStatus")
        }
    }
    private func loadHistory() async {
        let device = model.dataDevice, connection = Settings.connectionID
        await history.reload(device: device, connection: connection) { model.dataDevice == device && Settings.connectionID == connection }
    }
    private func load() async {
        guard Settings.isConfigured else { morning.stop(clear: true); return }
        let request = scope
        await morning.reload(request) { visible && scenePhase == .active && scope == request }
    }
    private var scope: MorningInsightsStore.Scope {
        .init(device: model.dataDevice, day: day, connection: Settings.connectionID, timezone: TimeZone.current.identifier)
    }
}
