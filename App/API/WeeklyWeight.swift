import Foundation

extension ZoopAPI {
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
        var dailyStepsGoal: Int? = nil
        var finishDate: String? = nil
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
        var dailyStepsGoal: Int? = nil
        var finishDate: String? = nil
        enum CodingKeys: String, CodingKey { case revision, active, timezone, weeklyLossKg, reminderEnabled, reminderWeekday, reminderMinute, finishDate, dailyStepsGoal }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(revision, forKey: .revision); try c.encode(active, forKey: .active)
            try c.encode(timezone, forKey: .timezone); try c.encode(weeklyLossKg, forKey: .weeklyLossKg)
            try c.encode(reminderEnabled, forKey: .reminderEnabled); try c.encode(reminderWeekday, forKey: .reminderWeekday); try c.encode(reminderMinute, forKey: .reminderMinute)
            try c.encode(finishDate, forKey: .finishDate)
            try c.encode(dailyStepsGoal, forKey: .dailyStepsGoal)
        }
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
        var progress: CutProgress? = nil
    }
    struct CutWeighIn: Codable, Equatable, Sendable {
        let day: String
        let kg: Double
    }
    struct CutProgress: Codable, Equatable, Sendable {
        let finishDate: String?
        let weeksRemaining: Int?
        let completed: Bool
        let startingWeightKg: Double?
        let currentWeightKg: Double?
        let totalLostKg: Double?
        let targetWeightKg: Double?
        var weighIns: [CutWeighIn]? = nil
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
