import SwiftUI

struct WeeklyWeightView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("weightUnit") private var unit = "kg"
    @State private var editing = false
    @State private var about = false
    @State private var selectedWeek: String?
    private var store: WeeklyWeightStore { model.weeklyWeight }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let summary = store.summary, let goal = store.goal, goal.active {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        let data = CutProgressData(goal: goal, summary: summary, now: context.date)
                        VStack(alignment: .leading, spacing: 28) {
                            CutProgressView(data: data, unit: unit)
                            CutWeeklyChart(data: data, unit: unit, selection: $selectedWeek)
                        }
                    }
                } else if store.loading { ProgressView().frame(maxWidth: .infinity).padding(30) }
                else if store.loaded {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(store.goal == nil ? "Start your cut" : store.goal?.active == true ? "Your cut is set" : "Cut paused").font(.title2.weight(.semibold))
                        Button(store.goal?.active == true ? "Edit goal" : store.goal == nil ? "Start a cut" : "Start a new cut") { editing = true }.buttonStyle(.borderedProminent).foregroundStyle(colorScheme == .dark ? Color.black : Color.white).accessibilityIdentifier("startWeightGoal")
                    }.frame(maxWidth: .infinity, alignment: .leading).snoopCard()
                }
                if let error = store.error {
                    VStack(alignment: .leading, spacing: 8) { Text(error).font(.footnote).foregroundStyle(SnoopStyle.unfavourable); Button("Retry") { Task { await store.reload() } }.foregroundStyle(SnoopStyle.load).frame(minHeight: 44) }
                }
                if store.goal?.reminderEnabled == true && store.goal?.active == true && model.battery.authorization == .denied {
                    Button("Allow weekly notifications in Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }.font(.footnote)
                }
                if let error = store.reminder.error { VStack(alignment: .leading) { Text(error).foregroundStyle(SnoopStyle.unfavourable); Button("Retry") { model.refreshReminders() }.foregroundStyle(SnoopStyle.load).frame(minHeight: 44) }.font(.footnote) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(SnoopStyle.gutter)
        }.frame(maxWidth: .infinity).snoopScreen().tint(SnoopStyle.load).navigationTitle("Cut progress").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Edit goal") { editing = true }.accessibilityIdentifier("editWeightGoal")
                        Button("About cut progress") { about = true }
                    } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("Cut options").accessibilityIdentifier("cutOptions")
                }
            }
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
            Text(detail).font(.subheadline).foregroundStyle(SnoopStyle.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var aboutView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    aboutItem("Weekly weight", "Weekly median. Comparisons need 4 weigh-ins across 5 days.")
                    aboutItem("Your pace", "A single slow week isn’t a stall.")
                    aboutItem("Target weight", "Based on your rate and finish date. A goal, not a prediction.")
                }.padding(SnoopStyle.gutter)
            }.snoopScreen().navigationTitle("About").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { about = false } } }
        }
    }
}

struct WeeklyWeightCard: View {
    let summary: SnoopAPI.WeeklyWeightSummary
    let unit: String
    var showsHeading = true
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 38.0
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if showsHeading {
                HStack { Text("Weight outlook").font(.subheadline.weight(.semibold)); Spacer(); if !typeSize.isAccessibilitySize { Image(systemName: "scalemass") } }.foregroundStyle(SnoopStyle.secondary)
            }
            Text(summary.progress?.completed == true ? "Cut finished" : WeeklyWeightPresentation.title(summary.state)).font(.system(size: titleSize, weight: .bold)).foregroundStyle(summary.progress?.completed == true ? SnoopStyle.secondary : WeeklyWeightPresentation.color(summary.state))
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("weeklyWeightStatus")
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 20))
            layout {
                metric("Weekly median", value: summary.medianKg, delta: false)
                if summary.changeKg != nil { metric("This week", value: summary.changeKg, delta: true) }
            }
            Divider()
            HStack { Text("Weekly target"); Spacer(); Text(WeeklyWeightPresentation.weight(-summary.weeklyLossKg, unit: unit, signed: true) + " " + unit) }.font(.subheadline).foregroundStyle(SnoopStyle.secondary)
        }.snoopCard(padding: 20)
    }
    private func metric(_ label: String, value: Double?, delta: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(SnoopStyle.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(WeeklyWeightPresentation.weight(value, unit: unit, signed: delta)).font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(delta ? WeeklyWeightPresentation.color(summary.state) : SnoopStyle.text)
                if value != nil { Text(unit).font(.subheadline).foregroundStyle(SnoopStyle.secondary) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum WeeklyWeightPresentation {
    static func title(_ state: String) -> String {
        switch state { case "on_pace": "On pace"; case "slower_week": "Slower week"; case "faster_week": "Faster week"; case "below_pace": "Below target pace"; case "faster": "Faster than planned"; case "possible_stall": "Possible stall"; case "starting": "Starting"; case "unclear": "Trend unclear"; default: "More weigh-ins needed" }
    }
    static func color(_ state: String) -> Color {
        state == "on_pace" ? SnoopStyle.favourable : ["starting", "insufficient", "unclear"].contains(state) ? SnoopStyle.secondary : SnoopStyle.typical
    }
    static func reason(_ s: SnoopAPI.WeeklyWeightSummary) -> String {
        switch s.reason { case "within_target": "This week matches your target."; case "first_week": "Your first week is taking shape."; case "three_flat_weeks": "Your weekly median has held steady for three weeks."; case "two_slow_weeks": "Two weeks below your target pace."; case "two_fast_weeks": "Two weeks faster than your target pace."; case "one_slow_week": "A slower week. One week doesn’t make a stall."; case "one_fast_week": "A faster week. Watch the longer trend."; case "conflicting_weeks": "Recent weeks are moving in different directions."; default: "Keep logging to build your weekly comparison." }
    }
    static func weight(_ kg: Double?, unit: String, signed: Bool = false) -> String {
        guard let kg else { return "—" }
        let value = ((unit == "lb" ? kg * 2.2046226218 : kg) * 10).rounded() / 10
        return (signed && value > 0 ? "+" : value < 0 ? "−" : "") + abs(value).formatted(.number.precision(.fractionLength(1)))
    }
    static func date(_ key: String) -> Date? {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }
}
