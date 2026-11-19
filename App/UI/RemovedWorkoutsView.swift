import SwiftUI

struct RemovedWorkoutsView: View {
    @Environment(AppModel.self) private var model
    @State private var rows: [ZoopAPI.Workout] = []
    @State private var loading = true
    @State private var restoring: Int64?
    @State private var error: String?

    var body: some View {
        List {
            if loading { ProgressView("Loading workouts") }
            if !loading && rows.isEmpty { Text("No removed workouts").foregroundStyle(ZoopStyle.secondary) }
            ForEach(rows) { workout in
                VStack(alignment: .leading, spacing: 8) {
                    Text(ActivityKind.named(workout.kind).name).font(ZoopType.headline)
                    Text(workout.startTs.formatted(date: .abbreviated, time: .shortened))
                        .font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary)
                    if let id = workout.lastEdit {
                        Button("Restore workout") {
                            Task {
                                restoring = workout.id
                                defer { restoring = nil }
                                do { try await model.activity.undo(device: model.strap.serial, id: id); await load() }
                                catch { self.error = error.localizedDescription }
                            }
                        }.disabled(restoring != nil).frame(minHeight: 44)
                    }
                }.padding(.vertical, 4)
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .scrollContentBackground(.hidden).zoopScreen()
        .navigationTitle("Removed workouts").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        defer { loading = false }
        do { rows = try await ZoopAPI.workouts(deviceId: model.strap.serial, limit: 500, status: "removed"); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
