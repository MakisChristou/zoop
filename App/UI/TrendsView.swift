import SnoopData
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
    @State private var range: TrendRange = .month
    @State private var detailDay: Date?
    @State private var detailNight: SnoopAPI.Night?
    @State private var showNight = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    chips
                    TrendChartCard(metric: metric, range: range, series: history.snapshot.series(metric, range: range), open: openReading)
                    TrendSleepHeatStrip(byDay: sleepByDay, nightCount: nights.count, today: Calendar.current.startOfDay(for: Date()), calendar: .current).equatable()
                    weekdayPattern
                    if let error = history.error { Text(error).font(.footnote).foregroundStyle(.red) }
                }
                .padding(.horizontal, SnoopStyle.gutter)
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
            .navigationDestination(for: SnoopAPI.Workout.self) { WorkoutDetailView(workout: $0) }
            .refreshable { await SnoopAPI.invalidateReads(); await load() }
            .task(id: "\(model.strap.serial)-\(Settings.connectionID.hashValue)-\(model.sleep.changeToken)-\(model.analysisRevision)-\(scenePhase)") {
                if scenePhase == .active { await load() }
            }
        }
    }

    // All ranges come from one prepared snapshot. A picker tap only selects a value.
    private var nights: [SnoopAPI.Night] { history.snapshot.nights }
    private var days: [SnoopAPI.Day] { history.snapshot.days }
    private var points: [TrendPoint] { history.snapshot.series(metric, range: range).points }
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
                                .foregroundStyle(SnoopStyle.text)
                                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: metric)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(metric == m ? .isSelected : [])
                    }
                }
            }
            Picker("Range", selection: $range) {
                ForEach(TrendRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    /// Average of the metric by weekday, once a fortnight of data exists.
    private var weekdayPattern: some View {
        let pts = points
        let cal = Calendar.current
        let symbols = cal.shortStandaloneWeekdaySymbols
        let order = (0..<7).map { ($0 + cal.firstWeekday - 1) % 7 + 1 }
        let bars: [(String, Double)] = order.compactMap { wd in
            guard let value = history.snapshot.series(metric, range: range).weekdays[wd] else { return nil }
            return (symbols[wd - 1], value)
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(metric.rawValue) by weekday").font(.caption.weight(.semibold)).foregroundStyle(SnoopStyle.secondary)
            if pts.count >= 14 {
                Chart(bars, id: \.0) { name, value in
                    BarMark(x: .value("Day", name), y: .value(metric.rawValue, value))
                        .foregroundStyle(metric.color.opacity(0.8))
                        .annotation(position: .top) { Text(format(value)).font(.caption2).foregroundStyle(SnoopStyle.secondary) }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis(.hidden)
                .frame(height: 120)
            } else if range == .week {
                Text("Choose a longer range to compare weekdays.")
                    .font(.footnote).foregroundStyle(SnoopStyle.secondary)
                Button("View 30 days") { range = .month }
                    .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                    .accessibilityIdentifier("weekdayLongerRange")
            } else {
                unlock("Needs 14 \(metric == .steps ? "days" : "nights") in this range. \(pts.count) recorded.")
            }
        }
        .padding()
        .background(SnoopStyle.surface, in: RoundedRectangle(cornerRadius: SnoopStyle.radius))
    }

    private func unlock(_ text: String) -> some View {
        HStack {
            Image(systemName: "lock.open").foregroundStyle(SnoopStyle.secondary)
            Text(text).font(.footnote).foregroundStyle(SnoopStyle.secondary)
            Spacer()
        }
    }

    private func format(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(metric.decimals)))
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
