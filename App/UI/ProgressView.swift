import Charts
import SwiftUI
import ZoopData

/// Two quiet summaries; definitions and secondary measurements are one tap away.
struct HealthProgressView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = ProgressStore()
    @State private var showAbout = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let summary = store.summary {
                    ProgressDates(summary: summary, showComparison: false, compact: true)
                        .frame(maxWidth: .infinity)
                    ForEach(ProgressKind.allCases) { kind in
                        NavigationLink {
                            ProgressDetailView(summary: summary, kind: kind)
                        } label: {
                            ProgressCard(metric: summary.metric(kind.key), kind: kind, summary: summary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("progressCard-\(kind.key)")
                    }
                } else if store.loading {
                    SwiftUI.ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                }
                if let error = store.error {
                    Text(error).font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary)
                    if store.summary == nil { Button("Try again") { Task { await load() } }.buttonStyle(.bordered) }
                }
            }
            .padding(.horizontal, ZoopStyle.gutter).padding(.vertical, 20)
        }
        .navigationTitle("Progress").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button { showAbout = true } label: { Image(systemName: "info.circle") }.accessibilityLabel("About your progress")
        } }
        .zoopScreen()
        .zoopLoading(store.loading, label: "Loading progress")
        .sheet(isPresented: $showAbout) { ProgressAboutView(summary: store.summary) }
        .refreshable { await ZoopAPI.invalidateReads(); await load() }
        .task(id: "\(model.strap.serial)-\(Settings.connectionID.hashValue)-\(model.sleep.changeToken)-\(model.analysisRevision)-\(scenePhase)") {
            if scenePhase == .active { await load() }
        }
    }
    private func load() async {
        let device = model.strap.serial, connection = Settings.connectionID
        await store.reload(device: device, connection: connection) { model.strap.serial == device && Settings.connectionID == connection }
    }
}

private enum ProgressKind: String, CaseIterable, Identifiable {
    case sleep, activity
    var id: String { rawValue }
    var key: String { self == .sleep ? "sleep" : "steps" }
    var title: String { self == .sleep ? "Sleep" : "Activity" }
    var symbol: String { self == .sleep ? "moon.fill" : "figure.walk" }
    var color: Color { self == .sleep ? ZoopStyle.sleep : ZoopStyle.steps }
    var keys: [String] { self == .sleep ? ["sleep", "wake_variation"] : ["steps", "walking", "strength"] }
}

private struct ProgressDates: View {
    let summary: ZoopAPI.ProgressSummary
    var showComparison = true
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(summary.current.label(timeZone: summary.timeZone, includeYear: !compact))
                .font(ZoopType.font(size: 14, weight: compact ? .regular : .medium, relativeTo: .subheadline))
                .foregroundStyle(compact ? ZoopStyle.secondary : ZoopStyle.text)
            if showComparison {
                Text("Compared with \(summary.previous.label(timeZone: summary.timeZone))")
                    .font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
}

private struct ProgressCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let metric: ZoopAPI.ProgressSummary.Metric?
    let kind: ProgressKind
    let summary: ZoopAPI.ProgressSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) { title; reading }
                    Spacer(minLength: 0)
                } else {
                    title
                    Spacer(minLength: 8)
                    reading
                }
                Image(systemName: "chevron.right").font(ZoopType.font(size: 12, weight: .medium, relativeTo: .caption))
                    .foregroundStyle(ZoopStyle.secondary).padding(.top, 3)
            }
            if let metric, metric.weeks.contains(where: { $0?.isFinite == true }) {
                ProgressBars(metric: metric, kind: kind, summary: summary)
            } else {
                Text("No readings").font(ZoopType.footnote).foregroundStyle(ZoopStyle.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).zoopCard()
    }
    private var title: some View {
        Label(kind.title, systemImage: kind.symbol).font(ZoopStyle.sectionTitle)
    }
    private var reading: some View {
        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(ProgressFormat.value(metric?.current, key: kind.key))
                    .font(ZoopType.font(size: 18, weight: .medium, relativeTo: .title3)).monospacedDigit()
                if kind == .activity {
                    Text("steps").font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                }
            }.foregroundStyle(ZoopStyle.text)
            if let change = metric?.change {
                Text(ProgressFormat.delta(change, key: kind.key)).font(ZoopType.caption)
                    .foregroundStyle(ProgressFormat.color(change, key: kind.key))
                    .accessibilityLabel("Change: \(ProgressFormat.delta(change, key: kind.key))")
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
}

private struct ProgressBars: View {
    let metric: ZoopAPI.ProgressSummary.Metric
    let kind: ProgressKind
    let summary: ZoopAPI.ProgressSummary
    private var data: ProgressChartData { ProgressChartData(metric: metric, summary: summary) }
    private var ceiling: Double {
        let peak = data.weeks.compactMap(\.value).max() ?? 0
        let step = kind == .sleep ? 3600.0 : 2000.0
        return max(step, ceil(peak / step) * step)
    }
    var body: some View {
        let data = data
        Chart {
            ForEach(data.weeks) { week in
                if let value = week.value {
                    BarMark(x: .value("Week", String(week.id)), y: .value(kind.title, value), width: .ratio(0.68))
                        .foregroundStyle(kind.color.opacity(week.id < 4 ? 0.38 : 1))
                        .cornerRadius(4)
                        .accessibilityLabel("Week of \(data.label(week))")
                        .accessibilityValue(ProgressFormat.value(value, key: kind.key))
                }
            }
        }
        .chartXScale(domain: data.weeks.map { String($0.id) }).chartYScale(domain: 0...ceiling)
        .chartXAxis {
            AxisMarks(values: data.tickIDs.map(String.init)) { axis in
                AxisValueLabel {
                    if let id = axis.as(String.self), let week = data.weeks.first(where: { String($0.id) == id }) {
                        Text(data.label(week)).font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary)
                    }
                }
            }
        }
        .chartYAxis { AxisMarks(position: .leading, values: [0, ceiling / 2, ceiling]) { axis in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(ZoopStyle.chartGrid)
            AxisValueLabel { if let v = axis.as(Double.self) {
                Text(kind == .sleep ? "\(Int(v / 3600))h" : v.formatted(.number.notation(.compactName)))
                    .font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary)
            } }
        } }
        .frame(height: 164)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityIdentifier("progressBars-\(kind.key)")
    }
}

private struct ProgressDetailView: View {
    let summary: ZoopAPI.ProgressSummary
    let kind: ProgressKind
    @State private var showInfo = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ProgressDates(summary: summary, showComparison: kind.keys.contains { summary.metric($0)?.previous != nil })
                ForEach(kind.keys, id: \.self) { key in
                    if let metric = summary.metric(key) { ProgressMetricRow(metric: metric) }
                }
            }.padding(ZoopStyle.gutter)
        }
        .navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar).zoopScreen()
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button { showInfo = true } label: { Image(systemName: "info.circle") }
                .accessibilityLabel("About \(kind.title.lowercased()) progress")
        } }
        .sheet(isPresented: $showInfo) { ProgressDetailInfo(summary: summary, kind: kind) }
    }
}

private struct ProgressMetricRow: View {
    let metric: ZoopAPI.ProgressSummary.Metric
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(ProgressFormat.title(metric.key)).font(ZoopType.headline)
            if metric.previous != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) { period(previous: true); period(previous: false) }
                    VStack(alignment: .leading, spacing: 16) { period(previous: true); period(previous: false) }
                }
            } else {
                Text(ProgressFormat.value(metric.current, key: metric.key))
                    .font(ZoopType.font(size: 20, weight: .medium, relativeTo: .title2)).monospacedDigit()
            }
            if let change = metric.change {
                Text(ProgressFormat.delta(change, key: metric.key)).font(ZoopType.headline)
                    .foregroundStyle(ProgressFormat.color(change, key: metric.key))
            }
        }.frame(maxWidth: .infinity, alignment: .leading).zoopCard(padding: 20)
    }
    private func period(previous: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(previous ? "Previous" : "Latest").font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
            Text(ProgressFormat.value(previous ? metric.previous : metric.current, key: metric.key))
                .font(ZoopType.font(size: 20, weight: .semibold, relativeTo: .title2)).monospacedDigit().fixedSize()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Definitions and recording coverage are available on demand, once per screen.
private struct ProgressDetailInfo: View {
    let summary: ZoopAPI.ProgressSummary
    let kind: ProgressKind
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(kind.keys, id: \.self) { key in
                        if let metric = summary.metric(key) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(ProgressFormat.title(key)).font(ZoopType.headline)
                                Text(ProgressFormat.definition(key)).font(ZoopType.subheadline)
                                let unit = ["walking", "strength"].contains(key) ? "weeks" : key == "steps" ? "days" : "nights"
                                Text("Recorded \(unit): \(metric.previousCount) previous · \(metric.currentCount) latest")
                                    .font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                            }
                        }
                    }
                    Text(kind == .sleep ? "Comparisons need 21 nights in each period." : "Comparisons need 21 days in each period, or 3 complete weeks for weekly totals.")
                        .font(ZoopType.footnote).foregroundStyle(ZoopStyle.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(ZoopStyle.gutter)
            }
            .navigationTitle("About \(kind.title.lowercased()) progress").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .zoopScreen()
        }
    }
}

private struct ProgressAboutView: View {
    let summary: ZoopAPI.ProgressSummary?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let summary {
                        LabeledContent("Period", value: summary.current.label(timeZone: summary.timeZone))
                        LabeledContent("Comparison", value: summary.previous.label(timeZone: summary.timeZone))
                    }
                    Text("Weekly averages. Gaps mean missing recordings.")
                    DisclosureGroup("How comparisons work") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("The last 28 complete days versus the 28 before them. Today is excluded.")
                            Text("Comparisons need 21 recorded days or nights in each period. Activity days need 75% recording coverage. Walking and strength totals use complete weeks.")
                            Text("Your corrections are included. These are recorded habits, not a health score.")
                        }.font(ZoopType.footnote).foregroundStyle(ZoopStyle.secondary).padding(.top, 12)
                    }
                }.font(ZoopType.body).padding(ZoopStyle.gutter)
            }.navigationTitle("About your progress").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }.zoopScreen()
        }
    }
}

/// Formatting shared by cards, detail and VoiceOver; rounded zero has no minus sign.
enum ProgressFormat {
    static func value(_ value: Double?, key: String) -> String {
        guard let value, value.isFinite else { return "—" }
        if key == "sleep" { let minutes = Int((value / 60).rounded()); return "\(minutes / 60)h \(minutes % 60)m" }
        if key == "strength" { return "\(value.formatted(.number.precision(.fractionLength(0...1)))) days/wk" }
        if key == "walking" { return "\(Int(value.rounded())) min/wk" }
        if key == "wake_variation" { return "\(Int(value.rounded())) min" }
        return value.formatted(.number.precision(.fractionLength(0)))
    }
    static func delta(_ value: Double, key: String) -> String {
        let scaled = key == "sleep" ? value / 60 : value
        let rounded = key == "strength" ? (scaled * 10).rounded() / 10 : scaled.rounded()
        let sign = rounded > 0 ? "+" : rounded < 0 ? "−" : ""
        let unit = key == "steps" ? "" : key == "strength" ? " days/wk" : key == "walking" ? " min/wk" : " min"
        return sign + abs(rounded).formatted(.number.precision(.fractionLength(0...(key == "strength" ? 1 : 0)))) + unit
    }
    static func color(_ value: Double, key: String) -> Color {
        // Duration and exercise volume are descriptive, not health verdicts.
        if key == "wake_variation", abs(value) >= 0.5 { return value < 0 ? ZoopStyle.favourable : ZoopStyle.typical }
        if key == "steps", value >= 0.5 { return ZoopStyle.favourable }
        return ZoopStyle.secondary
    }
    static func title(_ key: String) -> String {
        switch key { case "sleep": "Average sleep"; case "wake_variation": "Wake-time variation"; case "steps": "Steps per day"; case "walking": "Walking per week"; default: "Strength days per week" }
    }
    static func definition(_ key: String) -> String {
        switch key {
        case "sleep": "Average time asleep in your main sleep. Naps are separate."
        case "wake_variation": "How much your wake-up time varies. A smaller number means more consistent timing."
        case "steps": "Average walking and running steps on recorded days."
        case "walking": "Time your strap recorded walking or running, averaged across complete weeks."
        default: "Days with a resistance workout, averaged across complete weeks. Multiple sessions on one day count once."
        }
    }
}
