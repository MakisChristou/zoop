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
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline).foregroundStyle(SnoopStyle.secondary)
                if error {
                    Button("Couldn’t update insights. Retry") { Task { await load() } }
                        .frame(minHeight: 44).accessibilityIdentifier("retryInsights")
                }
                if let insights {
                    MorningOutlookView(insights: insights, showsChanges: false)
                    ForEach(insights.metrics) { InsightMetricView(metric: $0) }
                    DisclosureGroup {
                        weekly(insights)
                        timing(insights)
                    } label: {
                        Text("Weekly comparisons").font(.subheadline.weight(.medium)).frame(minHeight: 44)
                    }.tint(SnoopStyle.secondary).snoopCard()
                } else if loading {
                    ProgressView().frame(maxWidth: .infinity).accessibilityLabel("Loading morning insights")
                }
            }.padding(.horizontal, SnoopStyle.gutter).padding(.vertical, 16)
        }
        .navigationTitle("Morning insights").navigationBarTitleDisplayMode(.inline).snoopScreen()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showMethod = true } label: { Image(systemName: "info.circle") }.accessibilityLabel("About morning insights")
            }
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
    private func weekly(_ insights: MorningInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Past 7 days").font(.headline)
            ForEach(insights.metrics) { metric in
                VStack(alignment: .leading, spacing: 4) {
                    Text(metric.title).font(.subheadline.weight(.medium))
                    if let average = metric.week.average {
                        Text("\(metric.formatted(average)) \(metric.unit) average · \(metric.week.count) nights").font(.subheadline)
                        if let previous = metric.week.previousAverage {
                            Text("Previous week: \(metric.formatted(previous)) \(metric.unit)").font(.caption).foregroundStyle(SnoopStyle.secondary)
                        }
                    } else {
                        Text("\(metric.week.count)/5 recorded nights").font(.caption).foregroundStyle(SnoopStyle.secondary)
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
    }
    private func timing(_ insights: MorningInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sleep timing").font(.headline)
            if let asleep = insights.timing.asleepSdMin, let wake = insights.timing.wakeSdMin {
                Text("Falling asleep varied by about \(Int(asleep.rounded())) min; waking up by \(Int(wake.rounded())) min.")
                    .font(.subheadline)
                Text("Across \(insights.timing.count) nights this week").font(.caption).foregroundStyle(SnoopStyle.secondary)
            } else {
                Text("Needs five recorded nights in the same time zone.").font(.subheadline).foregroundStyle(SnoopStyle.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
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
