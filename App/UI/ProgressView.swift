import Charts
import SwiftUI
import SnoopData

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
                    ProgressDates(summary: summary)
                    ForEach(ProgressKind.allCases) { kind in
                        NavigationLink {
                            ProgressDetailView(summary: summary, kind: kind)
                        } label: {
                            ProgressCard(metric: summary.metric(kind.key), kind: kind)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("progressCard-\(kind.key)")
                    }
                } else if store.loading {
                    SwiftUI.ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                }
                if let error = store.error {
                    Text(error).font(.subheadline).foregroundStyle(SnoopStyle.secondary)
                    if store.summary == nil { Button("Try again") { Task { await load() } }.buttonStyle(.bordered) }
                }
            }
            .padding(.horizontal, SnoopStyle.gutter).padding(.vertical, 20)
        }
        .navigationTitle("Your progress").navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button { showAbout = true } label: { Image(systemName: "info.circle") }.accessibilityLabel("About your progress")
        } }
        .snoopScreen()
        .sheet(isPresented: $showAbout) { ProgressAboutView() }
        .refreshable { await SnoopAPI.invalidateReads(); await load() }
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
    var color: Color { self == .sleep ? SnoopStyle.sleep : SnoopStyle.steps }
    var caption: String { self == .sleep ? "Average per night" : "Steps per day" }
    var keys: [String] { self == .sleep ? ["sleep", "wake_variation"] : ["steps", "walking", "strength"] }
}

private struct ProgressDates: View {
    let summary: SnoopAPI.ProgressSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(summary.current.label(timeZone: summary.timeZone)).font(.subheadline.weight(.medium))
            Text("Compared with \(summary.previous.label(timeZone: summary.timeZone))")
                .font(.caption).foregroundStyle(SnoopStyle.secondary)
        }.fixedSize(horizontal: false, vertical: true)
    }
}

private struct ProgressCard: View {
    let metric: SnoopAPI.ProgressSummary.Metric?
    let kind: ProgressKind
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(kind.title, systemImage: kind.symbol).font(.headline)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(SnoopStyle.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) { headline; delta }
                    VStack(alignment: .leading, spacing: 6) { headline; delta }
                }
                Text(kind.caption).font(.subheadline).foregroundStyle(SnoopStyle.secondary)
            }
            if let metric {
                ProgressBars(metric: metric, kind: kind)
                if metric.change == nil {
                    Text(metric.currentCount == 0 ? "Waiting for recorded \(kind == .sleep ? "nights" : "days")" : "\(metric.currentCount) recorded \(kind == .sleep ? "nights" : "days")")
                        .font(.caption).foregroundStyle(SnoopStyle.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).snoopCard(padding: 20)
    }
    private var headline: some View {
        Text(ProgressFormat.value(metric?.current, key: kind.key))
            .font(.largeTitle.weight(.semibold)).monospacedDigit().foregroundStyle(SnoopStyle.text)
    }
    @ViewBuilder private var delta: some View {
        if let change = metric?.change {
            Text(ProgressFormat.delta(change, key: kind.key)).font(.subheadline.weight(.semibold))
                .foregroundStyle(ProgressFormat.color(change, key: kind.key))
                .accessibilityLabel("Change: \(ProgressFormat.delta(change, key: kind.key))")
        }
    }
}

private struct ProgressBars: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let metric: SnoopAPI.ProgressSummary.Metric
    let kind: ProgressKind
    private var values: [Double?] { Array((metric.weeks + Array(repeating: nil, count: 8)).prefix(8)) }
    private var ceiling: Double {
        let peak = values.compactMap { $0 }.max() ?? 0
        let step = kind == .sleep ? 3600.0 : 2000.0
        return max(step, ceil(peak / step) * step)
    }
    var body: some View {
        VStack(spacing: 8) {
            Chart {
                ForEach(0..<8, id: \.self) { index in
                    if let value = values[index] {
                        BarMark(x: .value("Week", String(index)), y: .value(kind.title, value), width: .ratio(0.68))
                            .foregroundStyle(kind.color.opacity(index < 4 ? 0.38 : 1))
                            .cornerRadius(4)
                            .accessibilityLabel("\(index < 4 ? "Previous" : "Recent") week \(index % 4 + 1)")
                            .accessibilityValue(ProgressFormat.value(value, key: kind.key))
                    }
                }
            }
            .chartXScale(domain: (0..<8).map(String.init)).chartYScale(domain: 0...ceiling)
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(position: .trailing, values: [0, ceiling]) { axis in
                AxisGridLine().foregroundStyle(SnoopStyle.separator)
                AxisValueLabel { if let v = axis.as(Double.self) {
                    Text(kind == .sleep ? "\(Int(v / 3600))h" : v.formatted(.number.notation(.compactName)))
                        .font(.caption2).foregroundStyle(SnoopStyle.secondary)
                } }
            } }
            .frame(height: 110)
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) { legend }
                } else {
                    HStack(alignment: .top) { legend }
                }
            }.font(.caption2).foregroundStyle(SnoopStyle.secondary)
                .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("progressBars-\(kind.key)")
    }
    @ViewBuilder private var legend: some View {
        Text("Previous 4 weeks").frame(maxWidth: .infinity, alignment: .leading)
        Text("Last 4 weeks").frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProgressDetailView: View {
    let summary: SnoopAPI.ProgressSummary
    let kind: ProgressKind
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ProgressDates(summary: summary)
                ForEach(kind.keys, id: \.self) { key in
                    if let metric = summary.metric(key) { ProgressMetricRow(metric: metric) }
                }
            }.padding(SnoopStyle.gutter)
        }
        .navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar).snoopScreen()
    }
}

private struct ProgressMetricRow: View {
    let metric: SnoopAPI.ProgressSummary.Metric
    private var weekly: Bool { ["walking", "strength"].contains(metric.key) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(ProgressFormat.title(metric.key)).font(.headline)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) { period(previous: true); period(previous: false) }
                VStack(alignment: .leading, spacing: 16) { period(previous: true); period(previous: false) }
            }
            if let change = metric.change {
                Text(ProgressFormat.delta(change, key: metric.key)).font(.headline)
                    .foregroundStyle(ProgressFormat.color(change, key: metric.key))
            }
            Text(ProgressFormat.definition(metric.key)).font(.footnote).foregroundStyle(SnoopStyle.secondary)
            Text("\(metric.previousCount) → \(metric.currentCount) \(weekly ? "complete weeks" : metric.key == "steps" ? "recorded days" : "recorded nights")")
                .font(.caption).foregroundStyle(SnoopStyle.secondary)
            if metric.change == nil {
                Text("Comparison needs \(metric.requiredCount) \(weekly ? "complete weeks" : "recordings") in each period.")
                    .font(.caption).foregroundStyle(SnoopStyle.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).snoopCard(padding: 20)
    }
    private func period(previous: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(previous ? "Previous" : "Latest").font(.caption).foregroundStyle(SnoopStyle.secondary)
            Text(ProgressFormat.value(previous ? metric.previous : metric.current, key: metric.key))
                .font(.title2.weight(.semibold)).monospacedDigit().fixedSize()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProgressAboutView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("The last 28 complete days, compared with the 28 before them.")
                    Text("Each bar is one week. Gaps mean there isn’t enough recording; they don’t mean zero. Today is left out.")
                    Text("Comparisons need at least 21 recorded days or nights in each period. Activity days need at least 75% recording coverage. Weekly walking and strength totals use complete recorded weeks only.")
                    Text("Your sleep and workout corrections are included. These are changes in your recorded habits, not a health score. More sleep or activity isn’t always better.")
                }.font(.body).padding(SnoopStyle.gutter)
            }.navigationTitle("About your progress").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }.snoopScreen()
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
        if key == "wake_variation", abs(value) >= 0.5 { return value < 0 ? SnoopStyle.favourable : SnoopStyle.typical }
        if key == "steps", value >= 0.5 { return SnoopStyle.favourable }
        return SnoopStyle.secondary
    }
    static func title(_ key: String) -> String {
        switch key { case "sleep": "Time asleep"; case "wake_variation": "Wake-time consistency"; case "steps": "Steps per day"; case "walking": "Walking per week"; default: "Strength days per week" }
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
