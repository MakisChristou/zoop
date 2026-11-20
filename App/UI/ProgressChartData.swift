import Foundation
import ZoopData

/// Calendar positions only. Values and comparison eligibility belong to the API.
struct ProgressChartData {
    struct Week: Identifiable {
        let id: Int
        let start: Date?
        let value: Double?
    }
    let weeks: [Week]
    let timezone: TimeZone

    init(metric: ZoopAPI.ProgressSummary.Metric, summary: ZoopAPI.ProgressSummary) {
        timezone = summary.timeZone
        let values = Array((metric.weeks + Array(repeating: nil, count: 8)).prefix(8))
            .map { $0.flatMap { $0.isFinite ? $0 : nil } }
        // Remove an entirely unavailable comparison period, not gaps within a period.
        let first = values.prefix(4).allSatisfy { $0 == nil } ? 4 : 0
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = summary.timeZone
        let anchor = DayKey.date(summary.current.start, timeZone: summary.timeZone)
        weeks = (first..<8).map { index in
            Week(id: index, start: anchor.flatMap { calendar.date(byAdding: .day, value: (index - 4) * 7, to: $0) }, value: values[index])
        }
    }
    func label(_ week: Week) -> String {
        guard let date = week.start else { return "—" }
        var format = Date.FormatStyle.dateTime.day().month(.abbreviated)
        format.timeZone = timezone
        return date.formatted(format)
    }
    var tickIDs: [Int] {
        weeks.count <= 4 ? weeks.map(\.id) : [weeks[0].id, weeks[2].id, weeks[4].id, weeks[7].id]
    }
}
