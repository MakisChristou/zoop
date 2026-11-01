import Charts
import SwiftUI

/// Longitudinal view. One hero chart whose metric you switch, a 7-day rolling average
/// behind the daily points, an 8-week heat-strip of sleep, and weekday patterns.
/// Sections say what they need instead of drawing a line through one point.
struct TrendsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var nights: [SnoopAPI.Night] = []
    @State private var days: [SnoopAPI.Day] = []
    @State private var error: String?
    @State private var metric: Metric = .sleep
    @State private var range: Range = .month

    enum Range: String, CaseIterable, Identifiable {
        case week = "W", month = "M", quarter = "3M", all = "ALL"
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
            case .sleep: .indigo
            case .restingHr: .red
            case .hrv: .teal
            case .breathing: .mint
            case .skinTemp: .orange
            case .steps: .green
            case .efficiency: .purple
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
                .padding()
            }
            .navigationTitle("Trends")
            .mainScreenChrome()
            .refreshable { await load() }
            .task { await load() }
            .onChange(of: range) { _, _ in Task { await load() } }
        }
    }

    // MARK: - Data shaping

    private var points: [TrendsViewPoint] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -range.days, to: Date())!
        switch metric {
        case .steps:
            return days.compactMap { day in
                guard let date = Self.dayFormatter.date(from: day.day), date >= cutoff else { return nil }
                return (day.stepsWalking ?? day.steps).map { TrendsViewPoint(date: date, value: Double($0)) }
            }
        case .skinTemp:
            return nights.compactMap { n in
                guard n.endTs >= cutoff else { return nil }
                return n.metrics.physiology.skinTempC.map { TrendsViewPoint(date: n.endTs, value: $0) }
            }.sorted { $0.date < $1.date }
        default:
            return nights.compactMap { n in
                guard n.endTs >= cutoff else { return nil }
                let v: Double? = switch metric {
                case .sleep: Double(n.metrics.window.asleepS) / 3600
                case .restingHr: n.metrics.physiology.restingHr
                case .hrv: n.metrics.physiology.hrvRmssdMs
                case .breathing: n.metrics.physiology.respiratoryRate
                case .efficiency: n.metrics.window.efficiency * 100
                default: nil
                }
                return v.map { TrendsViewPoint(date: n.endTs, value: $0) }
            }.sorted { $0.date < $1.date }
        }
    }

    /// Trailing 7-day mean at each point.
    private var rolling: [TrendsViewPoint] {
        let pts = points
        return pts.map { p in
            let window = pts.filter { $0.date <= p.date && $0.date > p.date.addingTimeInterval(-7 * 86400) }
            return TrendsViewPoint(date: p.date, value: window.map(\.value).reduce(0, +) / Double(window.count))
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Sections

    private var chips: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Metric.allCases) { m in
                        Button { metric = m } label: {
                            Text(m.rawValue)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(metric == m ? m.color.opacity(0.18) : Color.secondary.opacity(0.12), in: Capsule())
                                .foregroundStyle(metric == m ? m.color : .primary)
                                .animation(.easeOut(duration: 0.15), value: metric)
                        }
                        .buttonStyle(.plain)
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
        let avg = pts.isEmpty ? nil : pts.map(\.value).reduce(0, +) / Double(pts.count)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.rawValue).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(pts.last.map { format($0.value) } ?? "—")
                            .font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(metric.color)
                        Text(metric.unit).font(.headline).foregroundStyle(.secondary)
                    }
                    if let last = pts.last {
                        Text("as of " + last.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
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
                                Text("avg \(format(avg))").font(.caption2).foregroundStyle(.secondary)
                            }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                .frame(height: 180)
                HStack {
                    stat("min", pts.map(\.value).min())
                    Spacer()
                    stat("avg", avg)
                    Spacer()
                    stat("max", pts.map(\.value).max())
                    Spacer()
                    stat("days", Double(pts.count), decimals: 0)
                }
            } else {
                unlock(pts.isEmpty ? "No values in this range yet." : "One value so far. The chart appears with the second \(metric == .steps ? "day" : "night").")
                    .frame(height: 120)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }

    private func delta(_ d: Double) -> some View {
        let good: Bool? = metric.higherIsBetter.map { $0 ? d >= 0 : d <= 0 }
        return VStack(alignment: .trailing, spacing: 2) {
            Text((d >= 0 ? "+" : "") + format(d)).font(.headline).monospacedDigit()
                .foregroundStyle(deltaColor(good))
            Text("vs \(range.rawValue) avg").font(.caption2).foregroundStyle(.secondary)
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
        let byDay: [Date: Double] = Dictionary(nights.map { (cal.startOfDay(for: $0.endTs), Double($0.metrics.window.asleepS) / 3600) }, uniquingKeysWith: { a, _ in a })
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday
        let labels = (0..<7).map { symbols[($0 + first - 1) % 7] }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sleep, last \(weeks) weeks").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                HStack(spacing: 3) {
                    Text("<5h").font(.caption2).foregroundStyle(.tertiary)
                    ForEach(0..<5) { i in RoundedRectangle(cornerRadius: 2).fill(Color.indigo.opacity(0.15 + Double(i) * 0.2)).frame(width: 10, height: 10) }
                    Text("8h+").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { col in
                    VStack(spacing: 4) {
                        Text(labels[col]).font(.caption2).foregroundStyle(.tertiary)
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
                Text("Fills in night by night. \(nights.count) so far.").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }

    private func cell(_ hours: Double?, future: Bool) -> Color {
        if future { return .clear }
        guard let hours else { return Color.secondary.opacity(0.08) }
        let t = min(max((hours - 4) / 4.5, 0), 1)
        return Color.indigo.opacity(0.15 + t * 0.8)
    }

    /// Average of the metric by weekday, once a fortnight of data exists.
    private var weekdayPattern: some View {
        let pts = points
        let cal = Calendar.current
        let grouped = Dictionary(grouping: pts) { cal.component(.weekday, from: $0.date) }
        let symbols = cal.shortStandaloneWeekdaySymbols
        let order = (0..<7).map { ($0 + cal.firstWeekday - 1) % 7 + 1 }
        let bars: [(String, Double)] = order.compactMap { wd in
            guard let values = grouped[wd], !values.isEmpty else { return nil }
            return (symbols[wd - 1], values.map(\.value).reduce(0, +) / Double(values.count))
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(metric.rawValue) by weekday").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            if pts.count >= 14 {
                Chart(bars, id: \.0) { name, value in
                    BarMark(x: .value("Day", name), y: .value(metric.rawValue, value))
                        .foregroundStyle(metric.color.opacity(0.8))
                        .annotation(position: .top) { Text(format(value)).font(.caption2).foregroundStyle(.secondary) }
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
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }

    private func unlock(_ text: String) -> some View {
        HStack {
            Image(systemName: "lock.open").foregroundStyle(.tertiary)
            Text(text).font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func stat(_ label: String, _ value: Double?, decimals: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.tertiary).textCase(.uppercase)
            Text(value.map { String(format: "%.\(decimals ?? metric.decimals)f", $0) } ?? "—").font(.subheadline.weight(.medium)).monospacedDigit()
        }
    }

    private func format(_ v: Double) -> String {
        String(format: "%.\(metric.decimals)f", v)
    }

    private func load() async {
        guard !model.strap.serial.isEmpty else {
            error = "Waiting for the strap's serial number."
            return
        }
        do {
            async let n = SnoopAPI.nights(deviceId: model.strap.serial, limit: max(range.days, 56))
            async let d = SnoopAPI.days(deviceId: model.strap.serial, limit: range.days)
            nights = try await n
            days = try await d
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Shared point type for the trend charts.
struct TrendsViewPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}
