import Charts
import SwiftUI

/// Uses the same axes, selection marker and gesture recognizer as WeightTrendChart.
struct CutWeeklyChart: View {
    let data: CutProgressData
    let unit: String
    @Binding var selection: String?
    @State private var inspectedDate: Date?
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var chartHeight = 164.0
    private var index: Int { data.weeks.firstIndex { $0.id == selection } ?? max(0, data.weeks.count - 1) }
    private var week: ZoopAPI.WeightWeek? { data.weeks.indices.contains(index) ? data.weeks[index] : nil }
    private func weight(_ kg: Double) -> Double { unit == "lb" ? kg * 2.2046226218 : kg }
    private var points: [CutProgressData.Point] { week.map { data.points(in: $0) } ?? [] }
    private var targetPath: [(date: Date, kg: Double)] { week.map { data.targetPath(in: $0) } ?? [] }
    private var inspected: CutProgressData.Point? { points.first { $0.date == inspectedDate } }
    private var scale: ClosedRange<Double> {
        let values = (points.map(\.kg) + targetPath.map(\.kg)).map(weight)
        let low = values.min() ?? 60, high = values.max() ?? low
        let padding = max((high - low) * 0.15, unit == "lb" ? 1 : 0.5)
        return (low - padding)...(high + padding)
    }
    var body: some View {
        if let week {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    arrow(-1)
                    Text("Week \(data.number(week))").font(ZoopType.font(size: 14, weight: .medium, relativeTo: .subheadline))
                        .frame(maxWidth: .infinity).accessibilityIdentifier("cutSelectedWeek")
                    arrow(1)
                }
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                layout {
                    VStack(alignment: .leading, spacing: 4) {
                        MetricValue(WeeklyWeightPresentation.weight(inspected?.kg ?? week.medianKg, unit: unit), unit: inspected == nil && week.medianKg == nil ? "" : unit, size: 20)
                            .accessibilityIdentifier("cutWeeklyMedian")
                        Text(inspected.map { readingDate($0.date) } ?? (week.medianKg == nil ? "No weigh-ins" : "Weekly median")).font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary).accessibilityIdentifier("cutReadingLabel")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 6) {
                        // Historical medians have no server classification; never reuse today's verdict.
                        if week.start == data.summary.start && data.summary.state != "starting" {
                            Text(WeeklyWeightPresentation.title(data.summary.state)).font(ZoopType.font(size: 14, weight: .medium, relativeTo: .subheadline))
                                .foregroundStyle(WeeklyWeightPresentation.color(data.summary.state)).accessibilityIdentifier("weeklyWeightStatus")
                        }
                        if let change = data.change(week) {
                            Text(WeeklyWeightPresentation.weight(change, unit: unit, signed: true) + " " + unit + " this week")
                                .font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary).accessibilityIdentifier("cutWeeklyChange")
                        }
                        paceLabel.font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                    }.multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                }
                chart(week).frame(height: min(chartHeight, 280)).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .accessibilityElement(children: .ignore).accessibilityLabel("Cut weight chart")
                    .accessibilityValue(inspected.map { "\(readingDate($0.date)), \(WeeklyWeightPresentation.weight($0.kg, unit: unit)) \(unit)" } ?? "\(points.count) weigh-ins. Week \(data.number(week)), weekly median \(WeeklyWeightPresentation.weight(week.medianKg, unit: unit)) \(unit)")
                    .accessibilityIdentifier("cutWeeklyChart")
                    .accessibilityHint("Swipe up or down to select a week.")
                    .accessibilityAdjustableAction { move($0 == .increment ? 1 : -1) }
                    .accessibilityAction(named: "Previous week") { move(-1) }
                    .accessibilityAction(named: "Next week") { move(1) }
                    .accessibilityAction(named: "Next weigh-in") { inspect(1) }
                    .accessibilityAction(named: "Previous weigh-in") { inspect(-1) }
                    .accessibilityAction(named: "Clear selection") { inspectedDate = nil }
                let legendLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 16))
                legendLayout {
                    legend("Weight", dashed: false)
                    if !targetPath.isEmpty { legend("Target", dashed: true) }
                }
            }.zoopCard(padding: 20)
                .onChange(of: week.id) { _, _ in inspectedDate = nil }
        }
    }
    private var paceLabel: some View { Text("Target " + WeeklyWeightPresentation.weight(-data.goal.weeklyLossKg, unit: unit, signed: true) + " " + unit + " / week") }
    private func legend(_ label: String, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            Path { p in p.move(to: .init(x: 0, y: 3)); p.addLine(to: .init(x: 20, y: 3)) }
                .stroke(dashed ? ZoopStyle.secondary : ZoopStyle.text, style: .init(lineWidth: 2, dash: dashed ? [3, 3] : []))
                .frame(width: 20, height: 6).accessibilityHidden(true)
            Text(label).fixedSize(horizontal: false, vertical: true)
        }.font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
    }
    private func readingDate(_ date: Date) -> String {
        var format = Date.FormatStyle().day().month(.abbreviated); format.timeZone = data.calendar.timeZone
        return date.formatted(format)
    }
    private func arrow(_ direction: Int) -> some View {
        let enabled = data.weeks.indices.contains(index + direction)
        return Button { move(direction) } label: { Image(systemName: direction < 0 ? "chevron.left" : "chevron.right").font(ZoopType.font(size: 12, weight: .semibold, relativeTo: .footnote)).frame(width: 44, height: 44) }
            .foregroundStyle(enabled ? ZoopStyle.text : ZoopStyle.secondary.opacity(0.35))
            .disabled(!enabled)
            .accessibilityLabel(direction < 0 ? "Previous week" : "Next week")
            .accessibilityIdentifier(direction < 0 ? "cutPreviousWeek" : "cutNextWeek")
    }
    private func inspect(_ direction: Int) {
        guard !points.isEmpty else { return }
        let current = points.firstIndex { $0.date == inspectedDate } ?? (direction > 0 ? -1 : points.count)
        inspectedDate = points[min(points.count - 1, max(0, current + direction))].date
    }
    private func move(_ direction: Int) {
        let next = index + direction
        guard data.weeks.indices.contains(next) else { return }
        inspectedDate = nil
        selection = data.weeks[next].id
    }
    private var axisDates: [Date] {
        guard let week else { return [] }
        let bounds = data.window(for: week)
        let count = data.days(bounds.lowerBound, bounds.upperBound)
        let offsets = count <= 2 ? Array(0...count) : [0, count / 2, count]
        return offsets.compactMap { data.calendar.date(byAdding: .day, value: $0, to: bounds.lowerBound) }
    }
    private func chart(_ week: ZoopAPI.WeightWeek) -> some View {
        Chart {
            ForEach(Array(targetPath.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Date", point.date), y: .value("Target", weight(point.kg)), series: .value("Series", "target"))
                    .foregroundStyle(ZoopStyle.secondary).lineStyle(.init(lineWidth: 1.5, dash: [4, 3]))
            }
            ForEach(points) { point in
                LineMark(x: .value("Date", point.date), y: .value("Weight", weight(point.kg)), series: .value("Series", "weight"))
                    .foregroundStyle(ZoopStyle.text).lineStyle(.init(lineWidth: 2, lineCap: .round))
                PointMark(x: .value("Date", point.date), y: .value("Weight", weight(point.kg))).foregroundStyle(ZoopStyle.text).symbolSize(points.count <= 2 ? 32 : 0)
            }
            if let point = inspected ?? points.last {
                PointMark(x: .value("Date", point.date), y: .value("Weight", weight(point.kg))).foregroundStyle(ZoopStyle.text.opacity(0.18)).symbolSize(170)
                PointMark(x: .value("Date", point.date), y: .value("Weight", weight(point.kg))).foregroundStyle(ZoopStyle.text).symbolSize(65)
            }
            if let point = inspected {
                RuleMark(x: .value("Selected reading", point.date)).foregroundStyle(ZoopStyle.secondary.opacity(0.6))
                PointMark(x: .value("Date", point.date), y: .value("Weight", weight(point.kg))).foregroundStyle(ZoopStyle.text).symbolSize(70)
            }
        }.chartXScale(domain: data.domain(for: week)).chartXScale(range: .plotDimension(startPadding: 12, endPadding: 12))
            .chartYScale(domain: scale).chartLegend(.hidden).font(ZoopType.caption2)
            .chartXAxis {
                AxisMarks(values: axisDates) { mark in
                    AxisValueLabel(anchor: mark.index == 0 ? .topLeading : mark.index == axisDates.count - 1 ? .topTrailing : .top) { if let date = mark.as(Date.self) { Text(date, format: .dateTime.day().month(.abbreviated)).foregroundStyle(ZoopStyle.secondary) } }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(stroke: .init(lineWidth: 1, dash: [3, 3])).foregroundStyle(ZoopStyle.chartGrid)
                    AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1))).foregroundStyle(ZoopStyle.secondary)
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let frame = proxy.plotFrame {
                        let plot = geometry[frame]
                        CalendarChartGesture(select: { location in
                            guard plot.contains(location), let date: Date = proxy.value(atX: location.x - plot.minX) else { return }
                            inspectedDate = points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }?.date
                        }, page: move, endInspection: { inspectedDate = nil }).accessibilityHidden(true)
                    }
                }
            }
    }
}
