import Foundation

public struct TrendPoint: Identifiable, Equatable, Sendable {
    public let date: Date
    public let value: Double
    public var id: Date { date }
    public init(date: Date, value: Double) { self.date = date; self.value = value }
}

/// The existing trailing-time mean, including all points at equal timestamps.
/// Preparation is linear after sorting and never runs inside a chart's mark builder.
public struct TrendSeries: Sendable {
    public let points: [TrendPoint]
    public let rolling: [TrendPoint]
    public let average: Double?
    public let minimum: Double?
    public let maximum: Double?
    public let weekdays: [Int: Double]
    /// Lines stop at missing calendar days instead of implying a measurement.
    public let segmentByDate: [Date: Int]
    public init(_ values: [TrendPoint], calendar: Calendar = .current) {
        points = values.sorted { $0.date < $1.date }
        var segments: [Date: Int] = [:]
        var previous: Date?
        var segment = 0
        for point in points {
            if let previous, calendar.dateComponents([.day], from: calendar.startOfDay(for: previous), to: calendar.startOfDay(for: point.date)).day ?? 0 <= 1 {
                segments[point.date] = segment
            } else { segment += 1; segments[point.date] = segment }
            previous = point.date
        }
        segmentByDate = segments
        var lower = 0, upper = 0, sum = 0.0
        var means: [TrendPoint] = []; means.reserveCapacity(points.count)
        for point in points {
            while upper < points.count, points[upper].date <= point.date { sum += points[upper].value; upper += 1 }
            while lower < upper, points[lower].date <= point.date.addingTimeInterval(-7 * 86400) { sum -= points[lower].value; lower += 1 }
            means.append(TrendPoint(date: point.date, value: sum / Double(upper - lower)))
        }
        rolling = means
        average = points.isEmpty ? nil : points.reduce(0) { $0 + $1.value } / Double(points.count)
        minimum = points.map(\.value).min(); maximum = points.map(\.value).max()
        weekdays = Dictionary(grouping: points) { calendar.component(.weekday, from: $0.date) }
            .mapValues { values in values.reduce(0) { $0 + $1.value } / Double(values.count) }
    }
    /// Nearest recorded point, clamped to the ends. Equal distances choose the earlier reading.
    public func nearestIndex(to date: Date) -> Int? {
        guard !points.isEmpty else { return nil }
        let right = SortedWindow.lowerBound(points, value: date.timeIntervalSince1970) { $0.date.timeIntervalSince1970 }
        if right == 0 { return 0 }
        if right == points.count { return points.count - 1 }
        return date.timeIntervalSince(points[right - 1].date) <= points[right].date.timeIntervalSince(date) ? right - 1 : right
    }

}
