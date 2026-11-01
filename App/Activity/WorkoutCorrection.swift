import Foundation

/// Reuse a request id after a lost response; a changed draft gets a new id.
struct WorkoutCorrection: Encodable, Equatable {
    struct Target: Encodable, Equatable {
        let id: Int64
        let revision: Int64
        init(_ workout: SnoopAPI.Workout) { id = workout.id; revision = workout.revision ?? 0 }
    }
    struct Interval: Encodable, Equatable {
        let startTs: Date
        let endTs: Date
        let kind: String
    }
    struct Receipt: Decodable {
        let operationId: String
        let workoutIds: [Int64]
    }
    var operationId = UUID().uuidString
    let action: String
    var targets: [Target] = []
    var intervals: [Interval] = []
    var undoId: String?

    func hasSameChange(as other: Self) -> Bool {
        action == other.action && targets == other.targets && intervals == other.intervals && undoId == other.undoId
    }
}
