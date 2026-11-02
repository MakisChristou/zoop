import SnoopData
import Charts
import SwiftUI

/// Longitudinal view. One hero chart whose metric you switch, a 7-day rolling average
/// behind the daily points, an 8-week heat-strip of sleep, and weekday patterns.
/// Sections say what they need instead of drawing a line through one point.
struct TrendsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var nights: [SnoopAPI.Night] = []
    @State private var days: [SnoopAPI.Day] = []
    @State private var error: String?
    @State private var requestID = UUID()
    @State private var series: [Metric: TrendSeries] = [:]
    @State private var sleepByDay: [Date: Double] = [:]
    @State private var metric: Metric = .sleep
    @State private var range: Range = .month

    enum Range: String, CaseIterable, Identifiable {
        case week = "7 days", month = "30 days", quarter = "90 days", all = "Year"
        var id: String { rawValue }
        var days: Int {
            switch self {
            case .week: 7
            case .month: 30
            case .quarter: 90
            case .all: 365
            }
        }
    }

    enum Metric: String, CaseIterable, Identifiable {
        case sleep = "Sleep", restingHr = "Resting HR", hrv = "HRV", breathing = "Breathing", skinTemp = "Skin temp", steps = "Steps", efficiency = "Efficiency"
        var id: String { rawValue }
        var unit: String {
            switch self {
            case .sleep: "h"
            case .restingHr: "bpm"
            case .hrv: "ms"
            case .breathing: "/min"
            case .skinTemp: "°C"
            case .steps: ""
            case .efficiency: "%"
            }
        }
        var decimals: Int {
            switch self {
            case .sleep, .breathing, .skinTemp: 1
            default: 0
            }
        }
        var color: Color {
            switch self {
            case .sleep: SnoopStyle.sleep
            case .restingHr: SnoopStyle.heartRate
            case .hrv: SnoopStyle.sleep
            case .breathing: SnoopStyle.steps
            case .skinTemp: SnoopStyle.temperature
            case .steps: SnoopStyle.steps
            case .efficiency: SnoopStyle.sleep
            }
        }
        /// Whether a higher value is good, for the delta colour.
        var higherIsBetter: Bool? {
            switch self {
            case .sleep, .hrv, .efficiency: true
            case .restingHr: false
            default: nil
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    chips
                    hero
                    sleepHeatStrip
                    weekdayPattern
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                }
                .padding(.horizontal, SnoopStyle.gutter)
                .padding(.bottom, 24)
            }
            .navigationTitle("Trends")
            .mainScreenChrome("Trends")
            .refreshable { await SnoopAPI.invalidateReads(); await load() }
            .task(id: "\(model.strap.serial)-\(range.rawValue)-\(model.sleep.changeToken)-\(model.analysisRevision)") { await load() }
        }
    }

    // MARK: - Data shaping

    private var points: [TrendPoint] { series[metric]?.points ?? [] }
    private var rolling: [TrendPoint] { series[metric]?.rolling ?? [] }

    /// One preparation per data/range change; chart updates only read these values.
    private func prepare() {
        PerformanceTrace.measure("Trend preparation") { prepareSeries() }
    }

    private func prepareSeries() {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -range.days, to: Date())!
        var result: [Metric: TrendSeries] = [:]
        for metric in Metric.allCases {
            let points: [TrendPoint]
            if metric == .steps {
                points = days.compactMap { day in
                    guard let date = DayKey.date(day.day), date >= cutoff, let value = day.stepsWalking else { return nil }
                    return TrendPoint(date: date, value: Double(value))
                }
            } else {
                points = nights.compactMap { night in
                    guard night.endTs >= cutoff else { return nil }
                    let value: Double? = switch metric {
                    case .sleep: Double(night.metrics.window.asleepS) / 3600
                    case .restingHr: night.metrics.physiology.restingHr
                    case .hrv: night.metrics.physiology.hrvRmssdMs
                    case .breathing: night.metrics.physiology.respiratoryRate
                    case .skinTemp: night.metrics.physiology.skinTempC
                    case .efficiency: night.metrics.window.efficiency * 100
                    case .steps: nil
                    }
                    return value.map { TrendPoint(date: night.endTs, value: $0) }
                }
            }
            result[metric] = TrendSeries(points, calendar: calendar)
        }
        series = result
        sleepByDay = Dictionary(nights.map { (calendar.startOfDay(for: $0.endTs), Double($0.metrics.window.asleepS) / 3600) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: - Sections

    private var chips: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Metric.allCases) { m in
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
                ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var hero: some View {
        let pts = points
        let avg = series[metric]?.average
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        return VStack(alignment: .leading, spacing: 10) {
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.rawValue).font(.caption.weight(.semibold)).foregroundStyle(SnoopStyle.secondary)
                    MetricValue(pts.last.map { format($0.value) } ?? "—", unit: metric.unit, size: 40)
                        .foregroundStyle(metric.color)
                    if let last = pts.last {
                        Text("as of " + last.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                            .font(.caption).foregroundStyle(SnoopStyle.secondary)
                    }
                }
                if !typeSize.isAccessibilitySize { Spacer() }
                if let last = pts.last, let avg, pts.count >= 3 {
                    delta(last.value - avg)
                }
            }

            if pts.count >= 2 {
                Chart {
                    ForEach(rolling) { p in
                        AreaMark(x: .value("Date", p.date), y: .value("7-day", p.value))
                            .foregroundStyle(metric.color.opacity(0.12))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Date", p.date), y: .value("7-day", p.value))
                            .foregroundStyle(metric.color.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .interpolationMethod(.monotone)
                    }
                    ForEach(pts) { p in
                        LineMark(x: .value("Date", p.date), y: .value(metric.rawValue, p.value), series: .value("s", "daily"))
                            .foregroundStyle(metric.color)
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Date", p.date), y: .value(metric.rawValue, p.value))
                            .foregroundStyle(metric.color)
                            .symbolSize(28)
                    }
                    if let avg {
                        RuleMark(y: .value("avg", avg))
                            .foregroundStyle(.secondary.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                            .annotation(position: .top, alignment: .trailing) {
                                Text("avg \(format(avg))").font(.caption2).foregroundStyle(SnoopStyle.secondary)
                            }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                .frame(height: 180)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: typeSize.isAccessibilitySize ? 2 : 4), alignment: .leading, spacing: 12) {
                    stat("min", series[metric]?.minimum)
                    stat("avg", avg)
                    stat("max", series[metric]?.maximum)
                    stat("days", Double(pts.count), decimals: 0)
                }
            } else {
                unlock(pts.isEmpty ? "No values in this range yet." : "One value so far. The chart appears with the second \(metric == .steps ? "day" : "night").")
                    .frame(height: 120)
            }
        }
        .padding()
        .background(SnoopStyle.surface, in: RoundedRectangle(cornerRadius: SnoopStyle.radius))
    }

    private func delta(_ d: Double) -> some View {
        let good: Bool? = metric.higherIsBetter.map { $0 ? d >= 0 : d <= 0 }
        return VStack(alignment: .trailing, spacing: 2) {
            Text((d >= 0 ? "+" : "") + format(d)).font(.headline).monospacedDigit()
                .foregroundStyle(deltaColor(good))
            Text("vs period average").font(.caption2).foregroundStyle(SnoopStyle.secondary)
        }
    }

    private func deltaColor(_ good: Bool?) -> Color {
        switch good {
        case nil: .secondary
        case true?: .green
        case false?: .orange
        }
    }

    /// Eight weeks of sleep duration, one cell per night, Monday-first columns.
    private var sleepHeatStrip: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weeks = 8
        let startOfThisWeek = cal.dateInterval(of: .weekOfYear, for: today)!.start
        let gridStart = cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: startOfThisWeek)!
        let byDay = sleepByDay
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday
        let labels = (0..<7).map { symbols[($0 + first - 1) % 7] }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sleep, last \(weeks) weeks").font(.caption.weight(.semibold)).foregroundStyle(SnoopStyle.secondary)
                Spacer()
                HStack(spacing: 3) {
                    Text("<5h").font(.caption2).foregroundStyle(SnoopStyle.secondary)
                    ForEach(0..<5) { i in RoundedRectangle(cornerRadius: 2).fill(SnoopStyle.sleep.opacity(0.15 + Double(i) * 0.2)).frame(width: 10, height: 10) }
                    Text("8h+").font(.caption2).foregroundStyle(SnoopStyle.secondary)
                }
            }
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { col in
                    VStack(spacing: 4) {
                        Text(labels[col]).font(.caption2).foregroundStyle(SnoopStyle.secondary)
                        ForEach(0..<weeks, id: \.self) { row in
                            let date = cal.date(byAdding: .day, value: row * 7 + col, to: gridStart)!
                            let hours = byDay[date]
                            RoundedRectangle(cornerRadius: 3)
                                .fill(cell(hours, future: date > today))
                                .frame(height: 14)
                        }
                    }
                }
            }
            if nights.count < 7 {
                Text("Fills in night by night. \(nights.count) so far.").font(.caption2).foregroundStyle(SnoopStyle.secondary)
            }
        }
        .padding()
        .background(SnoopStyle.surface, in: RoundedRectangle(cornerRadius: SnoopStyle.radius))
    }

    private func cell(_ hours: Double?, future: Bool) -> Color {
        if future { return .clear }
        guard let hours else { return Color.secondary.opacity(0.08) }
        let t = min(max((hours - 4) / 4.5, 0), 1)
        return SnoopStyle.sleep.opacity(0.15 + t * 0.8)
    }

    /// Average of the metric by weekday, once a fortnight of data exists.
    private var weekdayPattern: some View {
        let pts = points
        let cal = Calendar.current
        let symbols = cal.shortStandaloneWeekdaySymbols
        let order = (0..<7).map { ($0 + cal.firstWeekday - 1) % 7 + 1 }
        let bars: [(String, Double)] = order.compactMap { wd in
            guard let value = series[metric]?.weekdays[wd] else { return nil }
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
            } else {
                unlock("Unlocks after 14 \(metric == .steps ? "days" : "nights"). \(pts.count) so far.")
                    .frame(height: 70)
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

    private func stat(_ label: String, _ value: Double?, decimals: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(SnoopStyle.secondary)
            Text(value.map { String(format: "%.\(decimals ?? metric.decimals)f", $0) } ?? "—").font(.subheadline.weight(.medium)).monospacedDigit()
        }
    }

    private func format(_ v: Double) -> String {
        String(format: "%.\(metric.decimals)f", v)
    }

    private func load() async {
        let serial = model.strap.serial, selectedRange = range, connection = Settings.connectionID
        let request = UUID(); requestID = request
        guard !serial.isEmpty else { error = "Connect your WHOOP to load trends."; return }
        prepare()
        do {
            async let n = SnoopAPI.nights(deviceId: serial, limit: max(selectedRange.days, 56), summary: true)
            async let d = SnoopAPI.days(deviceId: serial, limit: selectedRange.days)
            let (loadedNights, loadedDays) = try await (n, d)
            guard !Task.isCancelled, requestID == request, model.strap.serial == serial,
                  range == selectedRange, Settings.connectionID == connection else { return }
            nights = loadedNights; days = loadedDays
            prepare(); error = nil
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled, requestID == request else { return }
            self.error = error.localizedDescription
        }
    }
}
