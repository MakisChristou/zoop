import Foundation

/// A correction always starts from an existing recording.
enum WorkoutEditorMode: Identifiable {
    case edit(SnoopAPI.Workout), merge(SnoopAPI.Workout), split(SnoopAPI.Workout)

    var id: String { "\(action)-\(workout.id)" }
    var action: String {
        switch self { case .edit: "edit"; case .merge: "merge"; case .split: "split" }
    }
    var title: String {
        switch self { case .edit: "Edit workout"; case .merge: "Merge workouts"; case .split: "Split workout" }
    }
    var workout: SnoopAPI.Workout {
        switch self { case let .edit(w), let .merge(w), let .split(w): w }
    }
}
