import Foundation

enum WorkoutEditorMode: Identifiable {
    case add(Date), edit(SnoopAPI.Workout), merge(SnoopAPI.Workout), split(SnoopAPI.Workout)

    var id: String { "\(action)-\(workout?.id ?? 0)" }
    var action: String {
        switch self { case .add: "add"; case .edit: "edit"; case .merge: "merge"; case .split: "split" }
    }
    var title: String {
        switch self { case .add: "Add workout"; case .edit: "Edit workout"; case .merge: "Merge workouts"; case .split: "Split workout" }
    }
    var workout: SnoopAPI.Workout? {
        switch self { case .add: nil; case let .edit(w), let .merge(w), let .split(w): w }
    }
}
