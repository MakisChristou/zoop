import Charts
import SwiftUI

/// Raw, canonical goal readings. A gap remains a gap, never an invented weigh-in.
struct GoalWeightChart: View {
    let readings: [ZoopAPI.CutWeighIn]
    let timezone: String
    let unit: String
    var target: Double? = nil
    @State private var selected: Date?
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var height = 164.0
    private var calendar: Calendar { CutPlan.calendar(timezone: timezone) }
    private struct Point: Identifiable {
        let date: Date
        let kg: Double
        let segment: Int
        var id: Date { date }
    }
    private var points: [Point] {
        var result: [Point] = []
        var segment = 0
        for r in readings.sorted(by: { $0.day < $1.day }) {
            guard let date = CutPlan.date(r.day, calendar: calendar), r.kg.isFinite,
                (20...400).contains(r.kg), result.last?.date != date
            else { continue }
            if let last = result.last,
                (calendar.dateComponents([.day], from: last.date, to: date).day ?? 0) > 1
            {
                segment += 1
            }
            result.append(Point(date: date, kg: r.kg, segment: segment))
        }
        return result
    }
    private var picked: Point? { points.first { $0.date == selected } }
    private var displayed: Point? { picked ?? points.last }
    private func value(_ kg: Double) -> Double { unit == "lb" ? kg * 2.2046226218 : kg }
    private var range: ClosedRange<Double> {
        let values = points.map { value($0.kg) } + (target.map { [value($0)] } ?? [])
        let low = values.min() ?? 60
        let high = values.max() ?? low
        let padding = max(0.5, (high - low) * 0.15)
        return floor((low - padding) * 2) / 2...ceil((high + padding) * 2) / 2
    }
    private var domain: ClosedRange<Date> {
        let first = points.first?.date ?? Date()
        let last = points.last?.date ?? first
        return first.addingTimeInterval(-43200)...last.addingTimeInterval(43200)
    }
    private var ticks: [Date] {
        guard let first = points.first?.date, let last = points.last?.date else { return [] }
        if first == last { return [first] }
        let days = calendar.dateComponents([.day], from: first, to: last).day ?? 0
        if days < 3 { return [first, last] }
        return [first, calendar.date(byAdding: .day, value: days / 2, to: first) ?? first, last]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            let headerLayout =
                typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
            headerLayout {
                Text(picked.map { label($0.date) } ?? "Weight").font(ZoopStyle.sectionTitle)
                if !typeSize.isAccessibilitySize { Spacer() }
                Text(
                    WeeklyWeightPresentation.weight(displayed?.kg, unit: unit)
                        + (displayed == nil ? "" : " \(unit)")
                )
                .font(ZoopType.font(size: 16, weight: .medium, relativeTo: .body)).monospacedDigit()
            }
            if points.isEmpty {
                Text("No weigh-ins").font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary)
                    .frame(maxWidth: .infinity, minHeight: 144)
            } else {
                chart.frame(height: min(height, 280)).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .accessibilityElement(children: .ignore).accessibilityLabel("Goal weight chart")
                    .accessibilityValue(
                        displayed.map {
                            "\(label($0.date)), \(WeeklyWeightPresentation.weight($0.kg, unit: unit)) \(unit)"
                        } ?? ""
                    )
                    .accessibilityAdjustableAction { direction in
                        inspect(direction == .increment ? 1 : -1)
                    }
                    .accessibilityAction(named: "Clear selection") { selected = nil }
            }
        }.zoopCard().accessibilityIdentifier("goalWeightChart")
    }
    private func label(_ d: Date) -> String {
        var f = Date.FormatStyle().day().month(.abbreviated)
        f.timeZone = calendar.timeZone
        return d.formatted(f)
    }
    private func inspect(_ direction: Int) {
        guard !points.isEmpty else { return }
        let index = points.firstIndex { $0.date == selected } ?? points.count - 1
        selected = points[max(0, min(points.count - 1, index + direction))].date
    }
    private var chart: some View {
        let all = points
        let counts = Dictionary(grouping: all, by: \.segment).mapValues(\.count)
        return Chart {
            if let target {
                RuleMark(y: .value("Target", value(target))).foregroundStyle(ZoopStyle.secondary)
                    .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Target").font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary)
                    }
            }
            ForEach(all) { p in
                LineMark(
                    x: .value("Date", p.date), y: .value("Weight", value(p.kg)),
                    series: .value("Segment", p.segment)
                )
                .foregroundStyle(ZoopStyle.text).lineStyle(.init(lineWidth: 2, lineCap: .round))
                PointMark(x: .value("Date", p.date), y: .value("Weight", value(p.kg)))
                    .foregroundStyle(ZoopStyle.text).symbolSize(counts[p.segment] == 1 ? 22 : 0)
            }
            if let p = displayed {
                PointMark(x: .value("Date", p.date), y: .value("Weight", value(p.kg)))
                    .foregroundStyle(ZoopStyle.text.opacity(0.16)).symbolSize(140)
                PointMark(x: .value("Date", p.date), y: .value("Weight", value(p.kg)))
                    .foregroundStyle(ZoopStyle.text).symbolSize(35)
                if picked != nil {
                    RuleMark(x: .value("Selected", p.date)).foregroundStyle(
                        ZoopStyle.secondary.opacity(0.6))
                }
            }
        }.chartLegend(.hidden).chartXScale(domain: domain).chartYScale(domain: range)
            .chartXAxis {
                AxisMarks(values: ticks) { mark in
                    AxisValueLabel(
                        anchor: mark.index == 0
                            ? .topLeading : mark.index == ticks.count - 1 ? .topTrailing : .top
                    ) {
                        if let date = mark.as(Date.self) {
                            Text(label(date)).font(ZoopType.caption2).foregroundStyle(
                                ZoopStyle.secondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(
                    position: .leading,
                    values: [
                        range.lowerBound, (range.lowerBound + range.upperBound) / 2,
                        range.upperBound,
                    ]
                ) { _ in
                    AxisGridLine(stroke: .init(lineWidth: 1, dash: [3, 4])).foregroundStyle(
                        ZoopStyle.chartGrid)
                    AxisValueLabel(
                        format: FloatingPointFormatStyle<Double>.number.precision(
                            .fractionLength(0...1))
                    ).font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary)
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let frame = proxy.plotFrame {
                        let plot = geometry[frame]
                        CalendarChartGesture(
                            select: { location in
                                guard plot.contains(location),
                                    let date: Date = proxy.value(atX: location.x - plot.minX)
                                else { return }
                                selected =
                                    points.min {
                                        abs($0.date.timeIntervalSince(date))
                                            < abs($1.date.timeIntervalSince(date))
                                    }?.date
                            }, page: { _ in }, endInspection: { selected = nil }
                        ).accessibilityHidden(true)
                    }
                }
            }
    }
}
