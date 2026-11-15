import Foundation

extension SnoopAPI {
    struct WeightGoal: Codable, Equatable, Sendable {
        let revision: Int64
        var active: Bool
        let startedAt: Date
        let paceStartedAt: Date
        let timezone: String
        var weeklyLossKg: Double
        var reminderEnabled: Bool
        var reminderWeekday: Int
        var reminderMinute: Int
        let updatedAt: Date
    }
    struct WeightGoalInput: Encodable, Sendable {
        let revision: Int64
        let active: Bool
        let timezone: String
        let weeklyLossKg: Double
        let reminderEnabled: Bool
        let reminderWeekday: Int
        let reminderMinute: Int
    }
    struct WeightWeek: Codable, Equatable, Identifiable, Sendable {
        let start: String
        let end: String
        let medianKg: Double?
        let count: Int
        let eligible: Bool
        var id: String { start }
    }
    struct WeeklyWeightSummary: Codable, Equatable, Sendable {
        let algorithmVersion: Int
        let start: String
        let end: String
        let provisional: Bool
        let state: String
        let reason: String
        let medianKg: Double?
        let changeKg: Double?
        let weeklyLossKg: Double
        let count: Int
        let weekNumber: Int
        let weeks: [WeightWeek]
    }
    struct WeeklyWeightResponse: Codable, Sendable {
        let goal: WeightGoal?
        let summary: WeeklyWeightSummary?
    }
    static func weeklyWeight(_ device: String) async throws -> WeeklyWeightResponse {
        try await get("v1/devices/\(device)/weight-goal")
    }
    static func saveWeightGoal(_ device: String, input: WeightGoalInput) async throws -> WeightGoal {
        try await send("v1/devices/\(device)/weight-goal", method: "PUT", body: input)
    }
}
