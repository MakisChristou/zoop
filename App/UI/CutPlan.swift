import Foundation
import ZoopHealth

/// Setup preview uses the same calendar arithmetic as the authoritative server summary.
enum CutPlan {
    static func calendar(timezone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone) ?? .current
        return calendar
    }
    static func key(_ date: Date, calendar: Calendar) -> String {
        let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    static func date(_ key: String?, calendar: Calendar) -> Date? {
        guard let key else { return nil }
        let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }
    static func target(starting: Double?, rate: Double, start: Date, finish: Date, calendar: Calendar) -> Double? {
        guard let starting, rate.isFinite, rate != 0, let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: finish)).day, days > 0 else { return nil }
        let result = starting - rate * Double(days) / 7
        return (20...400).contains(result) ? result : nil
    }
    static func baseline(_ rows: [WeightReading], start: Date, calendar: Calendar, now: Date = Date()) -> Double? {
        let valid = rows.filter { !$0.removed && $0.measuredAt <= now && $0.kg.isFinite && (20...400).contains($0.kg) }
        let values = (0..<7).compactMap { offset -> Double? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: start) else { return nil }
            return WeightReading.preferred(valid, on: day, calendar: calendar)?.kg
        }.sorted()
        guard !values.isEmpty else { return nil }
        return (values[(values.count-1)/2] + values[values.count/2]) / 2
    }
}
