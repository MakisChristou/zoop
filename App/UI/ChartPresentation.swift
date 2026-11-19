import Foundation

/// Presentation bounds only: calendar navigation and source readings are unchanged.
enum ChartPresentation {
    static func dateDomain(_ interval: DateInterval, now: Date) -> ClosedRange<Date> {
        interval.start...max(interval.start.addingTimeInterval(1), min(interval.end.addingTimeInterval(-1), now))
    }
    static func dateTicks(_ domain: ClosedRange<Date>) -> [Date] {
        [domain.lowerBound, domain.lowerBound.addingTimeInterval(domain.upperBound.timeIntervalSince(domain.lowerBound) / 2), domain.upperBound]
    }
    static func ticks(_ range: ClosedRange<Double>) -> [Double] {
        let span = max(range.upperBound - range.lowerBound, 0.0001)
        let magnitude = pow(10, floor(log10(span / 2)))
        for factor in [1.0, 2, 2.5, 5, 10, 20] {
            let step = factor * magnitude
            let low = floor(range.lowerBound / step) * step
            if low + step * 2 >= range.upperBound - 0.0000001 { return [low, low + step, low + step * 2] }
        }
        return [range.lowerBound, (range.lowerBound + range.upperBound) / 2, range.upperBound]
    }
}
