import SwiftUI

struct GoalPeriodView: View {
    let id: Int64
    let store: WeeklyWeightStore
    let unit: String
    @Environment(\.dismiss) private var dismiss
    @State private var period: ZoopAPI.GoalPeriod?
    @State private var error: String?
    @State private var loading = false
    @State private var selectedWeek: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let period {
                        let end = period.endedAt.addingTimeInterval(-0.001)
                        let data = CutProgressData(
                            goal: period.goal, summary: period.summary, now: end)
                        HStack {
                            Text(period.outcome).foregroundStyle(
                                period.outcome == "Target reached"
                                    ? ZoopStyle.favourable : ZoopStyle.secondary)
                        }.font(ZoopType.caption)
                        GoalWeightChart(
                            readings: period.summary.progress?.weighIns ?? [],
                            timezone: period.goal.timezone, unit: unit,
                            target: period.summary.progress?.targetWeightKg, lower: period.summary.maintenanceLowerKg, upper: period.summary.maintenanceUpperKg)
                        GoalProgressCard(data: data, unit: unit, endedAt: period.endedAt)
                        DisclosureGroup("Weekly pace") {
                            CutWeeklyChart(data: data, unit: unit, selection: $selectedWeek)
                        }.font(ZoopType.subheadline)
                    }
                    if loading { ProgressView().frame(maxWidth: .infinity) }
                    if let error {
                        Text(error).foregroundStyle(ZoopStyle.unfavourable)
                        Button("Retry") { Task { await load() } }.frame(minHeight: 44)
                    }
                }.padding(ZoopStyle.gutter)
            }.zoopScreen().navigationTitle(period?.goal.title ?? "Goal").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
                .task { await load() }
        }
    }
    private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do { period = try await store.period(id) } catch is CancellationError {} catch {
            self.error = "Couldn’t load this goal."
        }
    }
}
