import Charts
import SnoopData
import SwiftUI

/// Selection stays local to this card; scrubbing does not rebuild the other trends.
struct TrendChartCard: View {
    let metric: TrendMetric
    let range: TrendRange
    let series: TrendSeries
    let open: (TrendPoint) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedDate: Date?
    @GestureState private var horizontalDrag: Bool?
    private var points: [TrendPoint] { series.points }
    private var rolling: [TrendPoint] { series.rolling }
    @State private var selectedMetric: TrendMetric?
    @State private var selectedRange: TrendRange?
    private var selected: TrendPoint? {
        guard selectedMetric == metric, selectedRange == range, let date = selectedDate, let index = series.nearestIndex(to: date), points[index].date == date else { return nil }
        return points[index]
    }
    private var displayed: TrendPoint? { selected ?? points.last }
    private var selectionDescription: String {
        guard let point = displayed else { return "No readings" }
        return "\(format(point.value)) \(metric.unit), \(point.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))"
    }
    private var readout: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(metric.rawValue)
                if selected != nil { Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).accessibilityHidden(true) }
            }
            .font(.caption.weight(.semibold)).foregroundStyle(SnoopStyle.secondary)
            MetricValue(displayed.map { format($0.value) } ?? "—", unit: metric.unit, size: 40)
                .foregroundStyle(metric.color).accessibilityIdentifier("trendReadingValue")
            if let point = displayed {
                Text(selected == nil
                     ? "as of " + point.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                     : point.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
                    .font(.caption).foregroundStyle(SnoopStyle.secondary)
                    .accessibilityIdentifier("trendReadingDate")
            }
        }
        .frame(minHeight: 44, alignment: .leading)
    }

    var body: some View {
        let pts = points
        let avg = series.average
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        return VStack(alignment: .leading, spacing: 10) {
            layout {
                readout
                    .accessibilityHidden(selected != nil)
                    .overlay {
                        if selected != nil {
                            Button { openReading() } label: { Color.clear.contentShape(Rectangle()) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("View \(metric == .steps ? "steps" : "sleep") details")
                                .accessibilityValue(selectionDescription)
                                .accessibilityIdentifier("trendOpenDetail")
                        }
                    }
                if !typeSize.isAccessibilitySize { Spacer() }
                Group {
                    if let last = pts.last, let avg, pts.count >= 3 {
                        delta(last.value - avg)
                            .opacity(selected == nil ? 1 : 0).accessibilityHidden(selected != nil)
                    } else { Color.clear.frame(width: 0, height: 0) }
                }
                .overlay(alignment: .topTrailing) {
                    if selected != nil {
                        Button("Latest") { selectedDate = nil }
                            .font(.subheadline.weight(.medium))
                            .buttonStyle(.bordered).buttonBorderShape(.capsule)
                            .frame(minHeight: 44).fixedSize()
                            .accessibilityIdentifier("trendLatest")
                    }
                }
            }

            if pts.count >= 2 {
                chart
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: typeSize.isAccessibilitySize ? 2 : 4), alignment: .leading, spacing: 12) {
                    stat("min", series.minimum)
                    stat("avg", avg)
                    stat("max", series.maximum)
                    stat("days", Double(pts.count), decimals: 0)
                }
            } else {
                unlock(pts.isEmpty ? "No values in this range yet." : "One value so far. The chart appears with the second \(metric == .steps ? "day" : "night").")
                    .frame(height: 120)
            }
        }
        .padding()
        .background(SnoopStyle.surface, in: RoundedRectangle(cornerRadius: SnoopStyle.radius))
        .onChange(of: metric) { _, _ in selectedDate = nil }
        .onChange(of: range) { _, _ in selectedDate = nil }
        .onChange(of: points) { _, new in
            if let selectedDate, !new.contains(where: { $0.date == selectedDate }) { self.selectedDate = nil }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(rolling) { p in
                AreaMark(x: .value("Date", p.date), y: .value("7-day", p.value))
                    .foregroundStyle(metric.color.opacity(0.12))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Date", p.date), y: .value("7-day", p.value))
                    .foregroundStyle(metric.color.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .interpolationMethod(.monotone)
            }
            ForEach(points) { p in
                LineMark(x: .value("Date", p.date), y: .value(metric.rawValue, p.value), series: .value("s", "daily"))
                    .foregroundStyle(metric.color)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Date", p.date), y: .value(metric.rawValue, p.value))
                    .foregroundStyle(metric.color)
                    .symbolSize(28)
            }
            if let selected {
                RuleMark(x: .value("Selected date", selected.date))
                    .foregroundStyle(SnoopStyle.secondary.opacity(0.45))
                PointMark(x: .value("Date", selected.date), y: .value(metric.rawValue, selected.value))
                    .foregroundStyle(metric.color).symbolSize(90)
            }
            if let avg = series.average {
                RuleMark(y: .value("avg", avg))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("avg \(format(avg))").font(.caption2).foregroundStyle(SnoopStyle.secondary)
                    }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
        .frame(height: 180)
        .chartOverlay { proxy in selectionOverlay(proxy) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.rawValue) trend chart")
        .accessibilityValue(selectionDescription)
        .accessibilityHint("Swipe up or down to inspect readings. Use the view details action to open the selected day.")
        .accessibilityAdjustableAction { direction in moveSelection(direction == .increment ? 1 : -1) }
        .accessibilityAction(named: metric == .steps ? "View steps details" : "View sleep details") { openReading() }
        .accessibilityAction(named: "Latest reading") { selectedDate = nil }
        .accessibilityIdentifier("trendsChart")
    }

    private func delta(_ d: Double) -> some View {
        let good: Bool? = metric.higherIsBetter.map { $0 ? d >= 0 : d <= 0 }
        return VStack(alignment: .trailing, spacing: 2) {
            Text((d >= 0 ? "+" : "") + format(d)).font(.headline).monospacedDigit()
                .foregroundStyle(deltaColor(good))
            Text("vs period average").font(.caption2).foregroundStyle(SnoopStyle.secondary)
        }
    }

    private func deltaColor(_ good: Bool?) -> Color {
        switch good {
        case nil: .secondary
        case true?: .green
        case false?: .orange
        }
    }

    private func selectionOverlay(_ proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            if let anchor = proxy.plotFrame {
                let plot = geometry[anchor]
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { location in select(location, plot: plot, proxy: proxy) }
                    // Simultaneous recognition leaves vertical page scrolling intact.
                    // Lock the direction at the start so a scroll cannot become a scrub.
                    .simultaneousGesture(DragGesture(minimumDistance: 16)
                        .updating($horizontalDrag) { value, horizontal, _ in
                            if horizontal == nil { horizontal = abs(value.translation.width) > abs(value.translation.height) }
                        }
                        .onChanged { value in
                            guard horizontalDrag ?? (abs(value.translation.width) > abs(value.translation.height)),
                                  plot.contains(value.startLocation) else { return }
                            select(CGPoint(x: min(max(value.location.x, plot.minX), plot.maxX), y: plot.midY), plot: plot, proxy: proxy)
                        })
            }
        }
    }
    private func select(_ location: CGPoint, plot: CGRect, proxy: ChartProxy) {
        guard plot.contains(location), let date: Date = proxy.value(atX: location.x - plot.minX),
              let index = series.nearestIndex(to: date) else { return }
        selectedMetric = metric; selectedRange = range
        selectedDate = points[index].date
    }
    private func moveSelection(_ step: Int) {
        guard !points.isEmpty else { return }
        let index = selectedDate.flatMap { series.nearestIndex(to: $0) } ?? points.count - 1
        selectedMetric = metric; selectedRange = range
        selectedDate = points[min(max(index + step, 0), points.count - 1)].date
    }
    private func openReading() { if let point = displayed { open(point) } }

    private func unlock(_ text: String) -> some View {
        HStack {
            Image(systemName: "lock.open").foregroundStyle(SnoopStyle.secondary)
            Text(text).font(.footnote).foregroundStyle(SnoopStyle.secondary)
            Spacer()
        }
    }

    private func stat(_ label: String, _ value: Double?, decimals: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(SnoopStyle.secondary)
            Text(value.map { String(format: "%.\(decimals ?? metric.decimals)f", $0) } ?? "—").font(.subheadline.weight(.medium)).monospacedDigit()
        }
    }

    private func format(_ v: Double) -> String {
        String(format: "%.\(metric.decimals)f", v)
    }

}
