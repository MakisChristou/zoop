import Foundation

struct SleepEditorMode: Identifiable {
    let action: String
    var record: SnoopAPI.SleepSession?
    var day = Date()
    var id: String { "\(action)-\(record?.id ?? 0)" }
    var title: String { action == "merge" ? "Merge sleep" : action == "add" ? "Add sleep" : "Edit sleep" }
}

