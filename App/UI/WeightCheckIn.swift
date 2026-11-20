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
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 16) {
                let headerLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                headerLayout {
                    NavigationLink { WeightView() } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            MetricValue(summary.latest.map { display($0.kg) } ?? "—", unit: unit, size: 20)
                            if summary.today == nil {
                                Text(summary.latest.map { dateLabel($0.measuredAt) } ?? "No weigh-ins yet")
                                    .font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                            }
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("todayWeight")
                    if summary.today == nil {
                        Button("Log weight") { adding = true }.font(ZoopType.font(size: 14, weight: .medium, relativeTo: .subheadline))
                            .buttonStyle(.bordered).frame(minHeight: 44)
                            .accessibilityLabel("Log today’s weight").accessibilityIdentifier("todayLogWeight")
                    } else { Text("30 days").font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary) }
                }
                if !points.isEmpty {
                    NavigationLink { WeightView() } label: {
                        Chart(points) { point in
                            LineMark(x: .value("Date", point.date), y: .value("Weight", point.kg), series: .value("Segment", point.segment))
                                .foregroundStyle(ZoopStyle.text).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                            PointMark(x: .value("Date", point.date), y: .value("Weight", point.kg))
                                .foregroundStyle(ZoopStyle.text).symbolSize(point.id == points.last?.id ? 50 : points.count == 1 ? 20 : 0)
                        }.chartYScale(domain: .automatic(includesZero: false)).chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary) } }
                            .chartYAxis { zoopChartYAxis() }
                            .frame(height: 164).accessibilityHidden(true)
                    }.buttonStyle(.plain).accessibilityLabel("View weight chart")
                }
                WeightWeekView(summary: summary, showsCount: false)
            }.zoopCard()
        }
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
