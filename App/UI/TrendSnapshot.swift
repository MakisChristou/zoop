import Foundation
import SnoopData

/// Immutable display data built away from the UI executor once per history refresh.
struct TrendSnapshot: Sendable {
    let nights: [SnoopAPI.Night]
    let days: [SnoopAPI.Day]
    let sleepByDay: [Date: Double]
    private let ranges: [TrendRange: [TrendMetric: TrendSeries]]
    private static let emptySeries = TrendSeries([])

    init() { nights = []; days = []; sleepByDay = [:]; ranges = [:] }

    init(nights: [SnoopAPI.Night], days: [SnoopAPI.Day], now: Date, calendar: Calendar) {
        self.nights = nights; self.days = days
        var values: [TrendMetric: [TrendPoint]] = [:]
        values[.steps] = days.compactMap { day in
            guard let date = DayKey.date(day.day, timeZone: calendar.timeZone), let value = day.stepsWalking else { return nil }
            return TrendPoint(date: date, value: Double(value))
        }
        for night in nights {
            let p = night.metrics.physiology, w = night.metrics.window
            let row: [(TrendMetric, Double?)] = [(.sleep, Double(w.asleepS) / 3600), (.restingHr, p.restingHr), (.hrv, p.hrvRmssdMs), (.breathing, p.respiratoryRate), (.skinTemp, p.skinTempC), (.efficiency, w.efficiency * 100)]
            for (metric, value) in row {
                if let value { values[metric, default: []].append(TrendPoint(date: night.endTs, value: value)) }
            }
        }
        ranges = Dictionary(uniqueKeysWithValues: TrendRange.allCases.map { range in
            let cutoff = calendar.date(byAdding: .day, value: -range.days, to: now) ?? now
            let series = Dictionary(uniqueKeysWithValues: TrendMetric.allCases.map { metric in
                (metric, TrendSeries((values[metric] ?? []).filter { $0.date >= cutoff }, calendar: calendar))
            })
            return (range, series)
        })
        sleepByDay = Dictionary(nights.map { (calendar.startOfDay(for: $0.endTs), Double($0.metrics.window.asleepS) / 3600) }, uniquingKeysWith: { a, _ in a })
    }

    func series(_ metric: TrendMetric, range: TrendRange) -> TrendSeries { ranges[range]?[metric] ?? Self.emptySeries }
}
