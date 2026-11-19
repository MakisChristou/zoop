import Foundation

/// A correction always starts from an existing recording.
enum SleepEditorMode: Identifiable {
    case edit(ZoopAPI.SleepSession), merge(ZoopAPI.SleepSession)

    var id: String { "\(action)-\(record.id)" }
    var action: String {
        switch self { case .edit: "edit"; case .merge: "merge" }
    }
    var title: String {
        switch self { case .edit: "Edit sleep"; case .merge: "Merge sleep" }
    }
    var record: ZoopAPI.SleepSession {
        switch self { case let .edit(record), let .merge(record): record }
    }
}
