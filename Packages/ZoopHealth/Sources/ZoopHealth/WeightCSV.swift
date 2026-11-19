import Foundation

/// Actual observations, not chart averages or daily source selection.
public enum WeightCSV {
    public static func encode(_ readings: [WeightReading], timeZone: TimeZone = .current) -> String {
        let timestamp = ISO8601DateFormatter()
        timestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.calendar = Calendar(identifier: .gregorian)
        day.timeZone = timeZone
        day.dateFormat = "yyyy-MM-dd"
        let rows = readings.filter { !$0.removed && $0.kg.isFinite }
            .sorted { $0.measuredAt == $1.measuredAt ? $0.id < $1.id : $0.measuredAt < $1.measuredAt }
        let header = "measured_at_utc,local_date,time_zone,weight_kg,source,source_name,reading_id"
        return ([header] + rows.map { row in
            [timestamp.string(from: row.measuredAt), day.string(from: row.measuredAt), timeZone.identifier,
             String(row.kg), row.source, row.sourceName, row.id].map(field).joined(separator: ",")
        }).joined(separator: "\r\n") + "\r\n"
    }

    private static func field(_ value: String) -> String {
        // Treat source names as text even when opened by spreadsheet software.
        let unsafe = value.trimmingCharacters(in: .whitespacesAndNewlines).first.map { "=+-@".contains($0) } ?? false
        let text = unsafe || value.hasPrefix("\t") || value.hasPrefix("\r") ? "'" + value : value
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
