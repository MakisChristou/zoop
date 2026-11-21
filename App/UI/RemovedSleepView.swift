import SwiftUI

struct RemovedSleepView: View {
    @Environment(AppModel.self) private var model
    @State private var rows: [ZoopAPI.SleepSession] = []
    @State private var error: String?
    var body: some View {
        List {
            if rows.isEmpty { Text(error ?? "No removed sleep").foregroundStyle(ZoopStyle.secondary).listRowBackground(ZoopStyle.surface) }
            ForEach(rows) { row in
                NavigationLink { SleepSessionDetailView(initial: row) } label: {
                    VStack(alignment: .leading, spacing: 4) { Text(row.name); Text(row.startTs.formatted(date: .abbreviated, time: .shortened)).font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary) }
                }.listRowBackground(ZoopStyle.surface)
            }
        }.scrollContentBackground(.hidden).zoopScreen().navigationTitle("Removed sleep").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .task(id: model.sleep.changeToken) { await load() }.refreshable { await load() }
    }
    private func load() async {
        do { rows = try await ZoopAPI.sleepSessions(deviceId: model.dataDevice, status: "removed"); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
