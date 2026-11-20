import Foundation

/// Shared clock labels for a single recorded night, always in that session's timezone.
enum SleepChartTime {
    static func ticks(from onset: Date, to offset: Date, timezone: TimeZone) -> [Date] {
        guard offset > onset else { return [] }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timezone
        let step = max(1, Int(ceil(offset.timeIntervalSince(onset) / 10800)))
        guard var tick = calendar.nextDate(after: onset.addingTimeInterval(-1), matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime) else { return [] }
        var result: [Date] = []
        while tick <= offset && result.count < 4 {
            result.append(tick)
            guard let next = calendar.date(byAdding: .hour, value: step, to: tick), next > tick else { break }
            tick = next
        }
        return result
    }
    static func label(_ date: Date, timezone: TimeZone) -> String {
        let formatter = DateFormatter(); formatter.timeZone = timezone; formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
