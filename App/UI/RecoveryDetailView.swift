import SwiftUI

struct RecoveryDetailView: View {
    let day: Date
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var visible = false
    @State private var morning = MorningInsightsStore()
    @State private var showMethod = false
    private var insights: MorningInsights? { morning.value(for: scope) }
    private var recovery: RecoveryReading? { insights?.recovery }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary)
                if morning.failed(for: scope) {
                    Button("Couldn’t update recovery. Retry") { Task { await load() } }
                        .frame(minHeight: 44).accessibilityIdentifier("retryRecovery")
                }
                VStack(spacing: 16) {
                    TodaySummaryRing(title: "Recovery", value: recovery?.value ?? "—",
                                     color: RecoveryTone.color(recovery), progress: recovery?.progress,
                                     isLoading: morning.loading || insights?.state == "updating" || insights?.state == "awaiting_sync" || recovery?.isPending == true, showsTitle: false)
                        .frame(maxWidth: 160)
                    Text(recovery?.status ?? (morning.loading ? "Loading" : "No reading"))
                        .font(ZoopType.headline).foregroundStyle(RecoveryTone.color(recovery))
                        .accessibilityIdentifier("recoveryStatus")
                }.frame(maxWidth: .infinity).padding(.vertical, 8)
                if recovery?.displayedScore != nil, let insights {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(insights.metrics) { metric in
                            let layout = typeSize.isAccessibilitySize
                                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                                : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                            layout {
                                Text(metric.title).font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary)
                                if !typeSize.isAccessibilitySize { Spacer(minLength: 16) }
                                Text([metric.formatted(metric.value), metric.unit].filter { !$0.isEmpty }.joined(separator: " "))
                                    .font(ZoopType.title3).monospacedDigit()
                            }
                            .accessibilityElement(children: .combine)
                        }
                        if let limiting = recovery?.limitingText {
                            Divider().overlay(ZoopStyle.separator)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Main influence").font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                                Text(limiting).font(ZoopType.subheadline)
                            }
                        }
                        if recovery?.conflict == true {
                            Text("Heart readings differ").font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).zoopCard()
                }
            }.padding(ZoopStyle.gutter)
        }
        .navigationTitle("Recovery").navigationBarTitleDisplayMode(.inline).zoopScreen()
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

    private var scope: MorningInsightsStore.Scope {
        .init(device: model.strap.serial, day: day, connection: Settings.connectionID, timezone: TimeZone.current.identifier)
    }
    private func load() async {
        guard Settings.isConfigured else { morning.stop(clear: true); return }
        let request = scope
        await morning.reload(request) { visible && scenePhase == .active && scope == request }
    }
}
