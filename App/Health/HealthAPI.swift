import Foundation
import SnoopHealth

extension SnoopAPI {
    struct HealthInfo: Decodable { let namespace: String; let cursor: Int64; let earliest: Date?; let wakeAt: Date? }
    struct HealthPage: Decodable { let namespace: String; let watermark: Int64; let nextCursor: Int64; let done: Bool; let records: [HealthRecord] }
    struct HealthPreparation: Decodable { let nextDay: String?; let done: Bool }
    static func healthInfo(_ device: String) async throws -> HealthInfo { try await get("v1/devices/\(device)/health") }
    static func healthPage(_ device: String, cursor: Int64, watermark: Int64?, snapshot: Bool) async throws -> HealthPage {
        var q = ["cursor": String(cursor), "snapshot": String(snapshot), "limit": "200"]
        if let watermark { q["watermark"] = String(watermark) }
        return try await get("v1/devices/\(device)/health/exports", query: q)
    }
    static func prepareHealth(_ device: String, from: Date, to: Date) async throws -> HealthPreparation {
        struct Body: Encodable { let from: String; let to: String }
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyy-MM-dd"
        return try await send("v1/devices/\(device)/health/prepare", method: "POST", body: Body(from: f.string(from: from), to: f.string(from: to)))
    }
    static func weights(_ device: String, from: Date, to: Date, after: String = "") async throws -> [WeightReading] {
        try await get("v1/devices/\(device)/weights", query: ["from": from.ISO8601Format(), "to": to.ISO8601Format(), "after": after])
    }
    struct WeightChanges: Decodable {
        let rows: [WeightReading]
        let nextCursor: Int64
        let watermark: Int64
        let done: Bool
    }
    static func weightChanges(_ device: String, cursor: Int64, watermark: Int64?) async throws -> WeightChanges {
        var query = ["cursor": String(cursor)]
        if let watermark { query["watermark"] = String(watermark) }
        return try await get("v1/devices/\(device)/weight-changes", query: query)
    }
    static func saveWeight(_ device: String, _ row: WeightReading) async throws -> WeightReading {
        try await send("v1/devices/\(device)/weights", method: "PUT", body: row)
    }
    static func removeImportedWeights(_ device: String, ids: [String]) async throws {
        struct Body: Encodable { let ids: [String] }
        let _: Bool = try await send("v1/devices/\(device)/weights/remove-imports", method: "POST", body: Body(ids: ids))
    }
}
