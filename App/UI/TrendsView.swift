import ZoopData
import Charts
import SwiftUI

/// Longitudinal view. One hero chart whose metric you switch, a 7-day rolling average
/// behind the daily points, an 8-week heat-strip of sleep, and weekday patterns.
/// Sections say what they need instead of drawing a line through one point.
struct TrendsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var history = TrendStore()
    @State private var metric: TrendMetric = .sleep
    @State private var heatmapNight: ZoopAPI.Night?
    @State private var detailDay: Date?
    @State private var detailNight: ZoopAPI.Night?
    @State private var showNight = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    NavigationLink { HealthProgressView() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "chart.bar.fill").foregroundStyle(ZoopStyle.steps)
                            Text("Your progress").font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(ZoopStyle.secondary)
                        }.foregroundStyle(ZoopStyle.text).zoopCard()
                    }.buttonStyle(.plain).accessibilityIdentifier("openProgress")
                    chips
                    TrendHistoryView(snapshot: history.snapshot, metric: metric, open: openReading)
                    TrendSleepHeatStrip(byDay: sleepByDay, today: Calendar.current.startOfDay(for: Date()), calendar: .current, selected: heatmapNight?.endTs) { date in
                        heatmapNight = nights.first { Calendar.current.isDate($0.endTs, inSameDayAs: date) }
                    }
                    if let error = history.error { Text(error).font(.footnote).foregroundStyle(.red) }
                }
                .padding(.horizontal, ZoopStyle.gutter)
                .padding(.bottom, 24)
            }
            .navigationTitle("Trends")
            .mainScreenChrome("Trends")
            .navigationDestination(item: $detailDay) { day in
                DayStepsView(day: day, summary: days.first { DayKey.date($0.day) == day }, summariesLoaded: true)
            }
            .navigationDestination(isPresented: $showNight) {
                if let detailNight { TrendSleepDetailView(summary: detailNight) }
            }
            .navigationDestination(for: ZoopAPI.Workout.self) { WorkoutDetailView(workout: $0) }
            .sheet(item: $heatmapNight) { night in
                SleepHeatmapDetail(night: night) {
                    heatmapNight = nil; detailNight = night; showNight = true
                }
            }
            .refreshable { await ZoopAPI.invalidateReads(); await load() }
            .task(id: "\(model.strap.serial)-\(Settings.connectionID.hashValue)-\(model.sleep.changeToken)-\(model.analysisRevision)-\(scenePhase)") {
                if scenePhase == .active { await load() }
            }
        }
    }

    // All ranges come from one prepared snapshot. A picker tap only selects a value.
    private var nights: [ZoopAPI.Night] { history.snapshot.nights }
    private var days: [ZoopAPI.Day] { history.snapshot.days }
    private var sleepByDay: [Date: Double] { history.snapshot.sleepByDay }

    // MARK: - Sections

    private var chips: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TrendMetric.allCases) { m in
                        Button { metric = m } label: {
                            Text(m.rawValue)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12).padding(.vertical, 7).frame(minHeight: 44)
                                .background(metric == m ? m.color.opacity(0.18) : Color.secondary.opacity(0.12), in: Capsule())
                                .foregroundStyle(ZoopStyle.text)
                                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: metric)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(metric == m ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func openReading(_ point: TrendPoint) {
        if metric == .steps { detailDay = point.date }
        else if let night = nights.first(where: { $0.endTs == point.date }) {
            detailNight = night; showNight = true
        }
    }

    private func load() async {
        let device = model.strap.serial, connection = Settings.connectionID
        await history.reload(device: device, connection: connection) {
            model.strap.serial == device && Settings.connectionID == connection
        }
    }
}
