import Charts
import SwiftUI

struct WeeklyWeightView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("weightUnit") private var unit = "kg"
    @State private var editing = false
    @State private var about = false
    private var store: WeeklyWeightStore { model.weeklyWeight }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let summary = store.summary, store.goal?.active == true {
                    ViewThatFits(in: .horizontal) {
                        HStack { Text(period(summary)).font(.headline); Spacer(); Text("Cut · Week \(summary.weekNumber)").font(.subheadline).foregroundStyle(SnoopStyle.secondary) }
                        VStack(alignment: .leading) { Text(period(summary)).font(.headline); Text("Cut · Week \(summary.weekNumber)").foregroundStyle(SnoopStyle.secondary) }
                    }
                    WeeklyWeightCard(summary: summary, unit: unit)
                    let points = chartPoints(summary)
                    if points.count >= 2 {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Weekly medians").font(.headline)
                            Chart(points) { point in
                                LineMark(x: .value("Week", point.date), y: .value("Weight", point.value), series: .value("Segment", point.segment))
                                    .foregroundStyle(SnoopStyle.load).lineStyle(.init(lineWidth: 2))
                                PointMark(x: .value("Week", point.date), y: .value("Weight", point.value)).foregroundStyle(SnoopStyle.load)
                            }.chartYScale(domain: .automatic(includesZero: false))
                                .chartXAxis { AxisMarks(values: points.map(\.date)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)); AxisTick() } }
                                .frame(height: 170).accessibilityLabel("Weekly median weight in \(unit)")
                        }
                    }
                    Text(WeeklyWeightPresentation.reason(summary)).font(.subheadline)
                    HStack {
                        Text("\(summary.count) weigh-ins this week").font(.caption).foregroundStyle(SnoopStyle.secondary)
                        Spacer()
                        Button("Edit goal") { editing = true }.font(.subheadline).frame(minHeight: 44).accessibilityIdentifier("editWeightGoal")
                    }
                } else if store.loading { ProgressView().frame(maxWidth: .infinity).padding(30) }
                else if store.loaded {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(store.goal == nil ? "Weekly weight outlook" : "Cut paused").font(.title2.weight(.semibold))
                        Button(store.goal == nil ? "Start a cut" : "Start a new cut") { editing = true }.buttonStyle(.borderedProminent).accessibilityIdentifier("startWeightGoal")
                    }.frame(maxWidth: .infinity, alignment: .leading).snoopCard()
                }
                if let error = store.error {
                    VStack(alignment: .leading, spacing: 8) { Text(error).font(.footnote); Button("Retry") { Task { await store.reload() } } }.foregroundStyle(SnoopStyle.unfavourable)
                }
                if store.goal?.reminderEnabled == true && store.goal?.active == true && model.battery.authorization == .denied {
                    Button("Allow weekly notifications in Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }.font(.footnote)
                }
                if let error = store.reminder.error { Text(error).font(.footnote).foregroundStyle(SnoopStyle.unfavourable) }
            }.padding(SnoopStyle.gutter)
        }.snoopScreen().tint(SnoopStyle.load).navigationTitle("Weekly outlook").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { about = true } label: { Image(systemName: "info.circle") }.accessibilityLabel("About weekly outlook") } }
            .sheet(isPresented: $editing) { WeightGoalSetupView() }
            .sheet(isPresented: $about) { aboutView }
            .task { await store.reload(); await model.battery.refreshAuthorization() }
            .refreshable { await store.reload() }
    }
    private func period(_ s: SnoopAPI.WeeklyWeightSummary) -> String {
        guard let start = WeeklyWeightPresentation.date(s.start), let end = WeeklyWeightPresentation.date(s.end) else { return s.start + " – " + s.end }
        return start.formatted(.dateTime.day().month(.abbreviated)) + " – " + end.formatted(.dateTime.day().month(.abbreviated))
    }
    private struct Point: Identifiable { let date: Date; let value: Double; let segment: Int; var id: Date { date } }
    private func chartPoints(_ summary: SnoopAPI.WeeklyWeightSummary) -> [Point] {
        var result: [Point] = [], segment = 0
        for week in summary.weeks {
            guard week.eligible, let value = week.medianKg, let date = WeeklyWeightPresentation.date(week.end) else { segment += 1; continue }
            result.append(.init(date: date, value: unit == "lb" ? value * 2.2046226218 : value, segment: segment))
        }
        return result
    }
    private var aboutView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Each Monday–Sunday week uses the median of one actual reading per day. Apple Health takes priority when both sources have a reading.")
                    Text("Comparisons need at least four weigh-ins spread across five days in both weeks. Missing days stay missing. The first week and incomplete weeks are not judged.")
                    Text("Your target allows a margin of 0.1 kg per week or 25%, whichever is larger, capped at half your target. A possible stall needs three adequately recorded weeks with little change. These are descriptive rules, not a diagnosis or an estimate of fat loss.")
                    Text("Sunday’s outlook includes readings synced so far. Late imports and corrections update it. Changing your rate starts a fresh comparison period; pausing stops the weekly reminder.")
                    Text("Faster loss is not automatically better. Your target never changes your calories or recorded weights.")
                    if let zone = store.goal?.timezone { Text("Goal calendar and reminder: \(zone)").font(.footnote).foregroundStyle(SnoopStyle.secondary) }
                }.padding(SnoopStyle.gutter)
            }.snoopScreen().navigationTitle("About weekly outlook").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { about = false } } }
        }
    }
}

struct WeeklyWeightCard: View {
    let summary: SnoopAPI.WeeklyWeightSummary
    let unit: String
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 38.0
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Weight outlook").font(.subheadline.weight(.semibold)); Spacer(); if !typeSize.isAccessibilitySize { Image(systemName: "scalemass") } }.foregroundStyle(SnoopStyle.secondary)
            Text(WeeklyWeightPresentation.title(summary.state)).font(.system(size: titleSize, weight: .bold)).foregroundStyle(WeeklyWeightPresentation.color(summary.state))
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
