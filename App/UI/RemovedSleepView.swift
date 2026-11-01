import SwiftUI

struct RemovedSleepView: View {
    @EnvironmentObject private var model: AppModel
    @State private var rows: [SnoopAPI.SleepSession] = []
    @State private var error: String?
    var body: some View {
        List {
            if rows.isEmpty { Text(error ?? "No removed sleep").foregroundStyle(SnoopStyle.secondary).listRowBackground(SnoopStyle.surface) }
            ForEach(rows) { row in
                NavigationLink { SleepSessionDetailView(initial: row) } label: {
                    VStack(alignment: .leading, spacing: 4) { Text(row.name); Text(row.startTs.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(SnoopStyle.secondary) }
                }.listRowBackground(SnoopStyle.surface)
            }
        }.scrollContentBackground(.hidden).snoopScreen().navigationTitle("Removed sleep").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .task(id: model.sleep.changeToken) { await load() }.refreshable { await load() }
    }
    private func load() async {
        do { rows = try await SnoopAPI.sleepSessions(deviceId: model.strap.serial, status: "removed"); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
