import Foundation
import SnoopData

extension SnoopAPI {
    struct ProgressSummary: Decodable, Sendable {
        struct Period: Decodable, Sendable {
            let start: String
            let end: String
            func label(timeZone: TimeZone) -> String {
                guard let first = DayKey.date(start, timeZone: timeZone), let last = DayKey.date(end, timeZone: timeZone) else { return "\(start) – \(end)" }
                var format = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
                format.timeZone = timeZone
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
                var startFormat = Date.FormatStyle.dateTime.day().month(.abbreviated)
                startFormat.timeZone = timeZone
                let startLabel = calendar.component(.year, from: first) == calendar.component(.year, from: last) ? first.formatted(startFormat) : first.formatted(format)
                return "\(startLabel) – \(last.formatted(format))"
            }
        }
        struct Metric: Decodable, Sendable, Identifiable {
            let key: String
            let current: Double?
            let previous: Double?
            let change: Double?
            let currentCount: Int
            let previousCount: Int
            let requiredCount: Int
            let weeks: [Double?]
            var id: String { key }
        }
        let timezone: String
        let current: Period
        let previous: Period
        let metrics: [Metric]
        var timeZone: TimeZone { TimeZone(identifier: timezone) ?? .gmt }
        func metric(_ key: String) -> Metric? { metrics.first { $0.key == key } }
    }

    static func progress(deviceId: String) async throws -> ProgressSummary {
        try await get("v1/devices/\(deviceId)/progress", query: ["tz": TimeZone.current.identifier], maxAge: 10)
    }
}
