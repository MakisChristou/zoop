import Charts
import SwiftUI
import ZoopHealth

/// The same footprint for the next action and its completed state.
struct WeightCheckIn: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("weightUnit") private var unit = "kg"
    @State private var adding = false
    @State private var summary = WeightCheckInSummary([])
    @State private var points: [WeightTrend.Point] = []
    private func display(_ kg: Double) -> String {
        (unit == "lb" ? kg * 2.2046226218 : kg).formatted(.number.precision(.fractionLength(1)))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 16))
            layout {
                NavigationLink { WeightView() } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let today = summary.today {
                            Text("\(display(today.kg)) \(unit)").font(.title3.weight(.semibold)).monospacedDigit()
                            Label(today.source == "health" ? "Added from Apple Health" : "You’re all set for today", systemImage: "checkmark")
                                .font(.caption).foregroundStyle(ZoopStyle.favourable)
                        } else {
                            Text("Morning check-in").font(.subheadline.weight(.semibold))
                            Text(summary.latest.map { "\(display($0.kg)) \(unit) · \(dateLabel($0.measuredAt))" } ?? "Log your first weight")
                                .font(.caption).foregroundStyle(ZoopStyle.secondary)
                        }
                    }.frame(maxWidth: .infinity, minHeight: 50, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("todayWeight").accessibilityHint("Opens your weight chart and history")
                if summary.today == nil {
                    Button("Log") { adding = true }
                        .font(.subheadline.weight(.semibold)).buttonStyle(.bordered).buttonBorderShape(.capsule)
                        .frame(minWidth: 62, minHeight: 44).accessibilityLabel("Log today’s weight").accessibilityIdentifier("todayLogWeight")
                } else if !typeSize.isAccessibilitySize {
                    NavigationLink { WeightView() } label: {
                        Chart(points) { point in
                            LineMark(x: .value("Date", point.date), y: .value("Weight", point.kg), series: .value("Segment", point.segment))
                                .foregroundStyle(ZoopStyle.load).lineStyle(StrokeStyle(lineWidth: 2))
                        }.chartYScale(domain: .automatic(includesZero: false)).chartXAxis(.hidden).chartYAxis(.hidden)
                            .frame(width: 100, height: 44).accessibilityHidden(true)
                    }.buttonStyle(.plain).accessibilityLabel("View weight chart")
                }
            }
            WeightWeekView(summary: summary, showsCount: false)
        }.zoopCard()
        .tint(ZoopStyle.load)
        .sheet(isPresented: $adding) { WeightEntryView() }
        .onChange(of: model.health.rows, initial: true) { _, _ in prepare() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { prepare() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in prepare() }
    }
    private func dateLabel(_ date: Date) -> String {
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
    private func prepare() {
        let now = Date()
        summary = WeightCheckInSummary(model.health.rows, now: now)
        let start = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        points = WeightTrend(model.health.rows.filter { $0.measuredAt >= start }, through: now).points
    }
}
