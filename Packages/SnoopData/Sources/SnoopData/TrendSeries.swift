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
    public init(_ values: [TrendPoint], calendar: Calendar = .current) {
        points = values.sorted { $0.date < $1.date }
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
}
