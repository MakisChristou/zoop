import Foundation
import SnoopData

extension SnoopAPI {
    struct SleepSession: Decodable, Identifiable, Hashable, Sendable {
        struct Payload: Decodable, Sendable {
            let window: Night.Window
            let physiology: Night.Physiology
            let stages: Night.StageSummary?
            let segments: [Night.Segment]
            let algoVersion: Int
            let efficiency: Double?
            let unknownS: Int?
            let unclassifiedS: Int?
        }
        let id: Int64
        let startTs: Date
        let endTs: Date
        let durationS: Int
        let kind: String
        let edited: Bool
        let autoDetected: Bool
        let revision: Int64
        let status: String
        let lastEdit: String?
        let replacements: [Int64]
        let metricsPending: Bool
        let timezone: String
        let sleep: Payload?
        var isActive: Bool { status == "active" }
        var day: String { Self.day(endTs, timezone: timezone) }
        var name: String { kind == "nap" ? "Nap" : "Main sleep" }
        var night: Night? {
            guard let sleep else { return nil }
            return Night(nightOf: day, algoVersion: sleep.algoVersion, startTs: startTs, endTs: endTs,
                         stages: sleep.segments, metrics: .init(window: sleep.window, physiology: sleep.physiology, stages: sleep.stages, naps: []))
        }
        static func day(_ date: Date, timezone: String) -> String {
            DayKey.string(date, timeZone: TimeZone(identifier: timezone) ?? .current)
        }
        static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.revision == b.revision }
        func hash(into h: inout Hasher) { h.combine(id); h.combine(revision) }
    }
    static func sleepSessions(deviceId: String, limit: Int = 1000, from: Date? = nil, to: Date? = nil, status: String = "active") async throws -> [SleepSession] {
        var q = ["limit": String(limit), "status": status]
        if let from { q["from"] = from.ISO8601Format() }; if let to { q["to"] = to.ISO8601Format() }
        return try await get("v1/devices/\(deviceId)/sleep-sessions", query: q)
    }
    static func sleepSession(deviceId: String, id: Int64) async throws -> SleepSession { try await get("v1/devices/\(deviceId)/sleep-sessions/\(id)") }
    static func sleepEpochs(deviceId: String, id: Int64) async throws -> [Epoch] { try await get("v1/devices/\(deviceId)/sleep-sessions/\(id)/epochs") }
    static func correctSleep(deviceId: String, command: WorkoutCorrection) async throws -> WorkoutCorrection.Receipt {
        try await send("v1/devices/\(deviceId)/sleep-sessions/corrections", method: "POST", body: command)
    }
    struct ResetScope: Encodable, Equatable, Sendable {
        let domains: [String]
        var from: Date?
        var to: Date?
        var targetId: Int64?
    }
    struct ResetPreview: Decodable, Sendable {
        let from: Date
        let to: Date
        let manualChanges: Int
        let token: String
        let expanded: Bool
    }
    struct ResetCommand: Encodable, Sendable {
        var operationId = UUID().uuidString
        let scope: ResetScope
        let token: String
    }
    struct ResetReceipt: Decodable, Sendable { let operationId: String; let from: Date; let to: Date }
    struct ResetHistory: Decodable, Identifiable, Sendable {
        let operationId: String; let from: Date; let to: Date; let domains: [String]
        var id: String { operationId }
    }
    struct ResetUndo: Encodable, Sendable { var operationId = UUID().uuidString; let resetId: String }
    static func resetPreview(deviceId: String, scope: ResetScope) async throws -> ResetPreview {
        try await send("v1/devices/\(deviceId)/analysis/reset-preview", method: "POST", body: scope)
    }
    static func resetAnalysis(deviceId: String, command: ResetCommand) async throws -> ResetReceipt {
        try await send("v1/devices/\(deviceId)/analysis/reset", method: "POST", body: command)
    }
    static func undoReset(deviceId: String, command: ResetUndo) async throws -> ResetReceipt {
        try await send("v1/devices/\(deviceId)/analysis/reset-undo", method: "POST", body: command)
    }
    static func resetHistory(deviceId: String) async throws -> [ResetHistory] { try await get("v1/devices/\(deviceId)/analysis/resets") }
}

extension WorkoutCorrection.Target {
    init(_ sleep: SnoopAPI.SleepSession) { id = sleep.id; revision = sleep.revision }
}
