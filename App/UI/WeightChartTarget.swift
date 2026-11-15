import Foundation

struct WeightChartTarget {
    let kg: Double
    let period: DateInterval
    func segment(in range: DateInterval) -> DateInterval? {
        let start = max(period.start, range.start), end = min(period.end, range.end)
        return end > start ? DateInterval(start: start, end: end) : nil
    }
}
