import SwiftUI

struct GoalsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("weightUnit") private var unit = "kg"
    @State private var editing = false
    @State private var about = false
    @State private var selectedWeek: String?
    private var store: WeeklyWeightStore { model.weeklyWeight }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if store.goal?.active == true {
                    HStack {
                        Text("Cut").font(ZoopStyle.sectionTitle).foregroundStyle(ZoopStyle.secondary)
                        Spacer()
                        Menu {
                            Button("Edit goal") { editing = true }.accessibilityIdentifier("editWeightGoal")
                            Button("About cut progress") { about = true }
                        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                            .accessibilityLabel("Cut options").accessibilityIdentifier("cutOptions")
                    }
                }
                if let summary = store.summary, let goal = store.goal, goal.active {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        let data = CutProgressData(goal: goal, summary: summary, now: context.date)
                        VStack(alignment: .leading, spacing: 24) {
                            CutProgressView(data: data, unit: unit)
                            Divider().overlay(ZoopStyle.separator)
                            CutWeeklyChart(data: data, unit: unit, selection: $selectedWeek)
                        }
                    }
                } else if store.loading { ProgressView().frame(maxWidth: .infinity).padding(30) }
                else if store.loaded {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(store.goal == nil ? "Start your cut" : store.goal?.active == true ? "Your cut is set" : "Cut paused").font(.title2.weight(.semibold))
                        Button(store.goal?.active == true ? "Edit goal" : store.goal == nil ? "Start a cut" : "Start a new cut") { editing = true }.buttonStyle(.borderedProminent).foregroundStyle(colorScheme == .dark ? Color.black : Color.white).accessibilityIdentifier("startWeightGoal")
                    }.frame(maxWidth: .infinity, alignment: .leading).zoopCard()
                }
                if let error = store.error {
                    VStack(alignment: .leading, spacing: 8) { Text(error).font(.footnote).foregroundStyle(ZoopStyle.unfavourable); Button("Retry") { Task { await store.reload() } }.foregroundStyle(ZoopStyle.load).frame(minHeight: 44) }
                }
                if store.goal?.reminderEnabled == true && store.goal?.active == true && model.battery.authorization == .denied {
                    Button("Allow weekly notifications in Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }.font(.footnote)
                }
                if let error = store.reminder.error { VStack(alignment: .leading) { Text(error).foregroundStyle(ZoopStyle.unfavourable); Button("Retry") { model.refreshReminders() }.foregroundStyle(ZoopStyle.load).frame(minHeight: 44) }.font(.footnote) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(ZoopStyle.gutter)
        }.frame(maxWidth: .infinity).zoopScreen().tint(ZoopStyle.text).mainScreenChrome("Goals")
            .sheet(isPresented: $editing) { WeightGoalSetupView() }
            .sheet(isPresented: $about) { aboutView }
            .task { await store.reload(); await model.battery.refreshAuthorization() }
            .refreshable { await store.reload() }
            .onChange(of: store.goal?.startedAt) { _, _ in selectedWeek = nil }
            .onChange(of: store.goal?.paceStartedAt) { _, _ in selectedWeek = nil }
    }
    private func aboutItem(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            Text(detail).font(.subheadline).foregroundStyle(ZoopStyle.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var aboutView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    aboutItem("Weekly weight", "Weekly median. Comparisons need 4 weigh-ins across 5 days.")
                    aboutItem("Your pace", "A single slow week isn’t a stall.")
                    aboutItem("Target weight", "Based on your rate and finish date. A goal, not a prediction.")
                }.padding(ZoopStyle.gutter)
            }.zoopScreen().navigationTitle("About").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { about = false } } }
        }
    }
}
