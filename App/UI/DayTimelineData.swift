import Foundation

/// Presentation only: clips server readings to the viewed day and keeps recording gaps.
struct DayTimelineData {
    enum Metric: String, CaseIterable {
        case heartRate, steps, temperature
        var title: String { switch self { case .heartRate: "Heart rate"; case .steps: "Steps"; case .temperature: "Temperature" } }
        var unit: String { switch self { case .heartRate: "bpm"; case .steps: "steps"; case .temperature: "°C" } }
    }
    enum Event: String, CaseIterable { case sleep = "Sleep", walk = "Walk", workout = "Workout" }
    struct Point: Identifiable {
        let date: Date
        let value: Double
        let group: Int
        var isolated = false
        var id: Date { date }
    }
    struct Hour: Identifiable {
        let start: Date
        let end: Date
        let steps: Int
        var id: Date { start }
        var middle: Date { start.addingTimeInterval(end.timeIntervalSince(start) / 2) }
    }
    let domain: ClosedRange<Date>
    let cutoff: Date
    let calendar: Calendar
    let heartRate: [Point]
    let temperature: [Point]
    let hours: [Hour]
    let events: [Event: [DateInterval]]

    init(minutes: [ZoopAPI.Minute], day: Date, now: Date?, sessions: [ZoopAPI.Workout], walkingHours: [Int]?, calendar: Calendar = .current) {
        self.calendar = calendar
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        domain = start...end
        cutoff = min(end, max(start, now ?? end))
        let limit = cutoff
        let rows = minutes.filter { $0.ts >= start && $0.ts < end && $0.ts <= limit }.sorted { $0.ts < $1.ts }
        heartRate = Self.points(rows.compactMap { row in row.hr.map { (row.ts, Double($0)) } })
        temperature = Self.points(rows.compactMap { row in row.skinTempC.map { (row.ts, $0) } })
        // API buckets are wall-clock hours, including the combined repeated hour at DST end.
        let starts = (0..<24).compactMap { hour -> (Int, Date)? in
            guard let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: start),
                  calendar.isDate(date, inSameDayAs: start), calendar.component(.hour, from: date) == hour else { return nil }
            return (hour, date)
        }.sorted { $0.1 < $1.1 }
        hours = starts.enumerated().compactMap { index, entry in
            guard let walkingHours, entry.0 < walkingHours.count, entry.1 < limit else { return nil }
            let stop = min(index + 1 < starts.count ? starts[index + 1].1 : end, limit)
            return Hour(start: entry.1, end: stop, steps: max(0, walkingHours[entry.0]))
        }
        func spans(_ matches: (ZoopAPI.Minute) -> Bool) -> [DateInterval] {
            Self.merged(rows.filter(matches).compactMap { row in
                let stop = min(row.ts.addingTimeInterval(60), limit)
                return stop > row.ts ? DateInterval(start: row.ts, end: stop) : nil
            })
        }
        events = [
            .sleep: spans { $0.bandState == 2 },
            .walk: spans { $0.bandState != 2 && ($0.activity ?? 0) >= 1 },
            .workout: Self.merged(sessions.filter(\.isActive).compactMap { session in
                let from = max(session.startTs, start), to = min(session.endTs, limit)
                return to > from ? DateInterval(start: from, end: to) : nil
            })
        ]
    }

    func points(for metric: Metric) -> [Point] { metric == .heartRate ? heartRate : metric == .temperature ? temperature : [] }
    func point(at time: Date, metric: Metric) -> Point? {
        guard time <= cutoff, let point = points(for: metric).min(by: { abs($0.date.timeIntervalSince(time)) < abs($1.date.timeIntervalSince(time)) }),
              abs(point.date.timeIntervalSince(time)) <= 60 else { return nil }
        return point
    }
    func hour(at time: Date) -> Hour? { hours.first { $0.start <= time && time < $0.end } }
    var ticks: [Date] {
        [domain.lowerBound] + [6, 12, 18].compactMap { calendar.date(bySettingHour: $0, minute: 0, second: 0, of: domain.lowerBound) } + [domain.upperBound]
    }
    func timeLabel(_ date: Date) -> String {
        if date == domain.upperBound { return "24:00" }
        return SleepChartTime.label(date, timezone: calendar.timeZone)
    }
    static func points(_ readings: [(Date, Double)]) -> [Point] {
        var result: [Point] = [], group = 0
        for (date, value) in readings where value.isFinite {
            if let last = result.last, date.timeIntervalSince(last.date) > 90 { group += 1 }
            result.append(Point(date: date, value: value, group: group))
        }
        for i in result.indices {
            result[i].isolated = (i == 0 || result[i - 1].group != result[i].group) && (i == result.count - 1 || result[i + 1].group != result[i].group)
        }
        return result
    }
    /// Three useful ticks without forcing a physiological signal down to zero.
    static func scale(values: [Double], includesZero: Bool) -> (domain: ClosedRange<Double>, ticks: [Double]) {
        let finite = values.filter(\.isFinite)
        let low = includesZero ? min(0, finite.min() ?? 0) : finite.min() ?? 0
        let high = max(low + 1, finite.max() ?? 1)
        let raw = (high - low) / 2
        let magnitude = pow(10, floor(log10(raw)))
        let step = ([1.0, 2, 2.5, 5, 10].first { $0 * magnitude >= raw } ?? 10) * magnitude
        let top = ceil(high / step) * step
        let ticks = [top - 2 * step, top - step, top]
        let bottom = min(ticks[0], includesZero ? low : low - (high - low) * 0.05)
        return (bottom...top, ticks)
    }
    static func merged(_ intervals: [DateInterval]) -> [DateInterval] {
        var result: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, interval.start <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else { result.append(interval) }
        }
        return result
    }
}
