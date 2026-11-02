import Foundation

protocol SessionRecord: Identifiable, Sendable where ID == Int64 {
    var startTs: Date { get }
    var endTs: Date { get }
    var isActive: Bool { get }
    var needsMetrics: Bool { get }
}
extension SnoopAPI.Workout: SessionRecord { var needsMetrics: Bool { metricsPending == true } }
extension SnoopAPI.SleepSession: SessionRecord { var needsMetrics: Bool { metricsPending } }

protocol SessionEndpoint: Sendable {
    associatedtype Record: SessionRecord
    static var limit: Int { get }
    static var noun: String { get }
    static var refreshMessage: String { get }
    static func list(device: String, from: Date?, to: Date?) async throws -> [Record]
    static func get(device: String, id: Int64) async throws -> Record
    static func save(device: String, command: WorkoutCorrection) async throws -> WorkoutCorrection.Receipt
}
enum SleepEndpoint: SessionEndpoint {
    static let limit = 1000
    static let noun = "Sleep"
    static let refreshMessage = "Saved. Reconnect to refresh sleep."
    static func list(device: String, from: Date?, to: Date?) async throws -> [SnoopAPI.SleepSession] { try await SnoopAPI.sleepSessions(deviceId: device, limit: limit, from: from, to: to) }
    static func get(device: String, id: Int64) async throws -> SnoopAPI.SleepSession { try await SnoopAPI.sleepSession(deviceId: device, id: id) }
    static func save(device: String, command: WorkoutCorrection) async throws -> WorkoutCorrection.Receipt { try await SnoopAPI.correctSleep(deviceId: device, command: command) }
}
enum WorkoutEndpoint: SessionEndpoint {
    static let limit = 500
    static let noun = "Workout"
    static let refreshMessage = "Saved. Reconnect to refresh workouts."
    static func list(device: String, from: Date?, to: Date?) async throws -> [SnoopAPI.Workout] { try await SnoopAPI.workouts(deviceId: device, limit: limit, from: from, to: to) }
    static func get(device: String, id: Int64) async throws -> SnoopAPI.Workout { try await SnoopAPI.workout(deviceId: device, id: id) }
    static func save(device: String, command: WorkoutCorrection) async throws -> WorkoutCorrection.Receipt { try await SnoopAPI.correctWorkout(deviceId: device, command: command) }
}
