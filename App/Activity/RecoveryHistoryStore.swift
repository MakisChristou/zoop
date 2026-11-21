import ZoopData
import Foundation
import Observation

@MainActor @Observable final class RecoveryHistoryStore {
    struct Point: Sendable {
        let date: Date
        let start: Date
        let end: Date
        let row: RecoveryDay
    }
    struct Snapshot: Sendable {
        let timezone: String
        let rows: [RecoveryDay]
        let now: Date
        let calendar: Calendar
        let points: [Point]
        let byDay: [String: RecoveryDay]

        init(timezone: String, rows: [RecoveryDay], now: Date) {
            self.timezone = timezone; self.rows = rows; self.now = now
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: timezone) ?? .current
            calendar.firstWeekday = Calendar.current.firstWeekday
            self.calendar = calendar
            // Parse each server day once, not for each drag event or chart mark.
            self.points = rows.compactMap { row in
                guard let date = DayKey.date(row.day, timeZone: calendar.timeZone),
                      let day = calendar.dateInterval(of: .day, for: date) else { return nil }
                let center = day.start.addingTimeInterval(day.duration / 2)
                return Point(date: center, start: day.start.addingTimeInterval(day.duration * 0.14),
                             end: day.end.addingTimeInterval(-day.duration * 0.14), row: row)
            }.sorted { $0.date < $1.date }
            self.byDay = Dictionary(rows.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
        }
    }
    private(set) var snapshot: Snapshot?
    private(set) var loading = false
    private(set) var failed = false
    private var device = ""
    private var connection = ""
    @ObservationIgnored private var request = UUID()
    @ObservationIgnored private let fetch: (String) async throws -> Snapshot

    init(fetch: @escaping (String) async throws -> Snapshot = { device in
        let profile = try await ZoopAPI.profile(deviceId: device)
        let timezone = profile?.tz ?? TimeZone.current.identifier
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone) ?? .current
        let now = Date(), today = calendar.startOfDay(for: now)
        let from = calendar.date(byAdding: .day, value: -365, to: today)!
        let rows = try await ZoopAPI.recoveryHistory(deviceId: device, from: from, to: today, timezone: timezone)
        return Snapshot(timezone: timezone, rows: rows, now: now)
    }) { self.fetch = fetch }

    func value(device: String, connection: String) -> Snapshot? {
        self.device == device && self.connection == connection ? snapshot : nil
    }

    func reload(device: String, connection: String, isCurrent: () -> Bool = { true }) async {
        guard !Task.isCancelled, isCurrent() else { return }
        if self.device != device || self.connection != connection {
            snapshot = nil; failed = false
            self.device = device; self.connection = connection
        }
        let id = UUID(); request = id
        guard !device.isEmpty, !connection.isEmpty else { snapshot = nil; loading = false; return }
        loading = true
        defer { if request == id { loading = false } }
        do {
            let result = try await fetch(device)
            guard !Task.isCancelled, request == id, isCurrent() else { return }
            snapshot = result; failed = false
        } catch {
            guard !Task.isCancelled, request == id, isCurrent() else { return }
            failed = true
        }
    }
}
