import Foundation

extension ZoopAPI {
    struct WeightGoal: Codable, Equatable, Sendable {
        var phase: String? = nil
        var maintenanceReferenceKg: Double? = nil
        var maintenanceRangePct: Double? = nil
        var kind: String { phase ?? "cut" }
        var title: String { kind == "bulk" ? "Bulk" : kind == "maintenance" ? "Maintenance" : "Cut" }
        var signedRate: Double { kind == "bulk" ? weeklyLossKg : kind == "maintenance" ? 0 : -weeklyLossKg }
        var id: Int64? = nil
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
        var clearMaintenanceReference = false
        var phase: String? = nil
        var maintenanceReferenceKg: Double? = nil
        var maintenanceRangePct: Double? = nil
        let revision: Int64
        let active: Bool
        let timezone: String
        let weeklyLossKg: Double
        let reminderEnabled: Bool
        let reminderWeekday: Int
        let reminderMinute: Int
        var dailyStepsGoal: Int? = nil
        var finishDate: String? = nil
        enum CodingKeys: String, CodingKey { case phase, maintenanceReferenceKg, maintenanceRangePct, revision, active, timezone, weeklyLossKg, reminderEnabled, reminderWeekday, reminderMinute, finishDate, dailyStepsGoal }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(phase, forKey: .phase)
            if clearMaintenanceReference { try c.encodeNil(forKey: .maintenanceReferenceKg) } else { try c.encodeIfPresent(maintenanceReferenceKg, forKey: .maintenanceReferenceKg) }
            try c.encodeIfPresent(maintenanceRangePct, forKey: .maintenanceRangePct)
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
        var trendKgPerWeek: Double? = nil
        var maintenanceLowerKg: Double? = nil
        var maintenanceUpperKg: Double? = nil
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
    struct GoalPeriod: Codable, Identifiable, Sendable {
        let id: Int64
        let goal: WeightGoal
        let endedAt: Date
        let endReason: String
        let summary: WeeklyWeightSummary
        var outcome: String {
            guard let progress = summary.progress, let current = progress.currentWeightKg else { return "No weigh-ins" }
            if let target = progress.targetWeightKg, (goal.kind == "bulk" ? current >= target : current <= target) { return "Target reached" }
            return endReason == "manual" ? (goal.finishDate == nil ? "Ended" : "Ended early") : endReason == "legacy" ? "Ended" : "Finished"
        }
    }
    struct GoalHistory: Codable, Sendable {
        let items: [GoalPeriod]
        let nextCursor: Int64?
    }
    static func goalHistory(_ device: String, before: Int64? = nil) async throws -> GoalHistory {
        let suffix = before.map { "?before=\($0)" } ?? ""
        return try await get("v1/devices/\(device)/weight-goals" + suffix)
    }
    static func goalPeriod(_ device: String, id: Int64) async throws -> GoalPeriod {
        try await get("v1/devices/\(device)/weight-goals/\(id)")
    }
    static func weeklyWeight(_ device: String) async throws -> WeeklyWeightResponse {
        try await get("v1/devices/\(device)/weight-goal")
    }
    static func saveWeightGoal(_ device: String, input: WeightGoalInput) async throws -> WeightGoal {
        try await send("v1/devices/\(device)/weight-goal", method: "PUT", body: input)
    }
}
