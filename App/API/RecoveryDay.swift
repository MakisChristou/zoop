import ZoopData
import Foundation

/// The same daily projection used by the web Recovery chart.
struct RecoveryDay: Decodable, Sendable, Identifiable {
    let day: String
    let recovery: RecoveryReading
    let hrvMs: Double?
    let restingHr: Double?
    var id: String { day }
}

extension ZoopAPI {
    static func recoveryHistory(deviceId: String, from: Date, to: Date, timezone: String) async throws -> [RecoveryDay] {
        let zone = TimeZone(identifier: timezone) ?? .current
        return try await get("v1/devices/\(deviceId)/recovery", query: [
            "from": DayKey.string(from, timeZone: zone), "to": DayKey.string(to, timeZone: zone), "tz": timezone
        ])
    }
}
