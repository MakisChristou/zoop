import Foundation
import SnoopData

/// Every available calendar page is prepared off the UI executor on refresh.
struct TrendSnapshot: Sendable {
    let nights: [SnoopAPI.Night]
    let days: [SnoopAPI.Day]
    let sleepByDay: [Date: Double]
    let calendar: Calendar
    let now: Date
    let first: Date?
    private let pages: [TrendRange: [Date: [TrendMetric: TrendSeries]]]
    private let patterns: [TrendMetric: TrendSeries]
    private static let emptySeries = TrendSeries([])

    init() { self.init(nights: [], days: [], now: .now, calendar: .current) }

    init(nights: [SnoopAPI.Night], days: [SnoopAPI.Day], now: Date, calendar: Calendar) {
        self.nights = nights; self.days = days; self.calendar = calendar; self.now = now
        var values: [TrendMetric: [TrendPoint]] = [:]
        values[.steps] = days.compactMap { day in
            guard let date = DayKey.date(day.day, timeZone: calendar.timeZone), let value = day.stepsWalking else { return nil }
            return TrendPoint(date: date, value: Double(value))
        }
        for night in nights {
            let p = night.metrics.physiology, w = night.metrics.window
            let row: [(TrendMetric, Double?)] = [(.sleep, Double(w.asleepS) / 3600), (.restingHr, p.restingHr), (.hrv, p.hrvRmssdMs), (.breathing, p.respiratoryRate), (.skinTemp, p.skinTempC), (.efficiency, w.efficiency * 100)]
            for (metric, value) in row {
                if let value, value.isFinite { values[metric, default: []].append(TrendPoint(date: night.endTs, value: value)) }
            }
        }
        first = values.values.flatMap { $0.map(\.date) }.min()
        var prepared: [TrendRange: [Date: [TrendMetric: TrendSeries]]] = [:]
        for range in TrendRange.allCases {
            for (metric, points) in values {
                let groups = Dictionary(grouping: points) { range.interval(containing: $0.date, calendar: calendar).start }
                for (start, group) in groups {
                    prepared[range, default: [:]][start, default: [:]][metric] = TrendSeries(group, calendar: calendar)
                }
            }
        }
        pages = prepared
        let cutoff = calendar.date(byAdding: .weekOfYear, value: -8, to: calendar.startOfDay(for: now))!
        patterns = values.mapValues { TrendSeries($0.filter { $0.date >= cutoff && $0.date <= now }, calendar: calendar) }
        sleepByDay = Dictionary(nights.map { (calendar.startOfDay(for: $0.endTs), Double($0.metrics.window.asleepS) / 3600) }, uniquingKeysWith: { a, _ in a })
    }

    func series(_ metric: TrendMetric, range: TrendRange, containing date: Date? = nil) -> TrendSeries {
        pages[range]?[range.interval(containing: date ?? now, calendar: calendar).start]?[metric] ?? Self.emptySeries
    }
    func weekdayPattern(_ metric: TrendMetric) -> TrendSeries? {
        guard let series = patterns[metric], series.points.count >= 14 else { return nil }
        let counts = Dictionary(grouping: series.points) { calendar.component(.weekday, from: $0.date) }
        guard counts.count == 7, counts.values.allSatisfy({ $0.count >= 2 }) else { return nil }
        return series
    }
}
