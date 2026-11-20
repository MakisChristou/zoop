import Charts
import SwiftUI

/// One selectable signal with time-aligned context tracks; all values remain server-owned.
struct DayTimeline: View {
    private let data: DayTimelineData
    private let isToday: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var metric: DayTimelineData.Metric = .heartRate
    @State private var scrub: Date?
    @State private var plotBounds: CGRect = .zero

    init(minutes: [ZoopAPI.Minute], day: Date, now: Date? = nil, sessions: [ZoopAPI.Workout] = [], walkingHours: [Int]? = nil) {
        data = DayTimelineData(minutes: minutes, day: day, now: now, sessions: sessions, walkingHours: walkingHours)
        isToday = now != nil
    }
    private var points: [DayTimelineData.Point] { data.points(for: metric) }
    private var selected: DayTimelineData.Point? { scrub.flatMap { data.point(at: $0, metric: metric) } }
    private var hour: DayTimelineData.Hour? { scrub.flatMap { data.hour(at: $0) } }
    private var hasReadings: Bool { metric == .steps ? !data.hours.isEmpty : !points.isEmpty }
    private var color: Color { metric == .steps ? ZoopStyle.steps : ZoopStyle.text }
    private var scale: (domain: ClosedRange<Double>, ticks: [Double]) {
        DayTimelineData.scale(values: metric == .steps ? data.hours.map { Double($0.steps) } : points.map(\.value), includesZero: metric == .steps)
    }
    private var ticks: [Date] { typeSize.isAccessibilitySize ? [data.ticks[0], data.ticks[2], data.ticks[4]] : data.ticks }
    private var reading: Double? {
        if metric == .steps { return scrub == nil ? (data.hours.isEmpty ? nil : Double(data.hours.reduce(0) { $0 + $1.steps })) : hour.map { Double($0.steps) } }
        return scrub == nil ? points.last?.value : selected?.value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            chart
            ForEach(DayTimelineData.Event.allCases, id: \.self) { event in
                if let intervals = data.events[event], !intervals.isEmpty { contextTrack(event, intervals: intervals) }
            }
        }.zoopCard()
            .onChange(of: data.domain.lowerBound) { _, _ in scrub = nil }
    }

    private var header: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            Menu {
                ForEach(DayTimelineData.Metric.allCases, id: \.self) { item in
                    Button { metric = item; scrub = nil } label: {
                        if metric == item { Label(item.title, systemImage: "checkmark") } else { Text(item.title) }
                    }.accessibilityIdentifier("timelineMetric-\(item.rawValue)")
                }
            } label: {
                HStack(spacing: 8) {
                    Text(metric.title).font(ZoopStyle.sectionTitle)
                    Image(systemName: "chevron.down").font(ZoopType.caption2)
                }.frame(minHeight: 44)
            }.accessibilityLabel("Timeline metric").accessibilityValue(metric.title)
                .accessibilityIdentifier("timelineMetricPicker")
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            HStack(spacing: 6) {
                DayTimelineReadout(value: reading, unit: metric.unit,
                                   date: scrub.map { metric == .steps ? hour?.start ?? $0 : selected?.date ?? $0 } ?? (metric == .steps ? nil : points.last?.date),
                                   liveHeartRate: isToday && metric == .heartRate && scrub == nil,
                                   decimals: metric == .temperature ? 1 : 0)
                    .accessibilityIdentifier("timelineReadout")
                if scrub != nil {
                    Button { scrub = nil } label: { Image(systemName: "xmark").font(ZoopType.caption).frame(width: 44, height: 44) }
                        .accessibilityLabel("Return to latest reading")
                }
            }
        }
    }

    private var chart: some View {
        Chart {
            if metric == .steps {
                ForEach(data.hours) { hour in
                    RectangleMark(xStart: .value("From", hour.start), xEnd: .value("To", hour.end), yStart: .value("Steps", 0), yEnd: .value("Steps", hour.steps))
                        .foregroundStyle(color).cornerRadius(2)
                }
            } else {
                ForEach(points) { point in
                    LineMark(x: .value("Time", point.date), y: .value(metric.title, point.value), series: .value("Recording", point.group))
                        .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.linear)
                    if point.isolated { PointMark(x: .value("Time", point.date), y: .value(metric.title, point.value)).foregroundStyle(color).symbolSize(8) }
                }
                if let point = scrub == nil ? points.last : selected {
                    PointMark(x: .value("Time", point.date), y: .value(metric.title, point.value)).foregroundStyle(color).symbolSize(24)
                }
            }
            if let scrub { RuleMark(x: .value("Time", scrub)).foregroundStyle(ZoopStyle.secondary.opacity(0.6)) }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: data.domain, range: .plotDimension(padding: 0))
        .chartYScale(domain: scale.domain)
        .chartXAxis {
            AxisMarks(values: ticks) { mark in
                AxisValueLabel(anchor: mark.index == 0 ? .topLeading : mark.index == ticks.count - 1 ? .topTrailing : .top) {
                    if let date = mark.as(Date.self) { Text(data.timeLabel(date).replacingOccurrences(of: ":00", with: "")).font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: scale.ticks) { mark in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(ZoopStyle.chartGrid)
                AxisValueLabel {
                    if let value = mark.as(Double.self) {
                        Text(value.formatted(.number.notation(metric == .steps ? .compactName : .automatic).precision(.fractionLength(0...1))))
                            .font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary)
                            .frame(minWidth: 44, alignment: .leading)
                    }
                }
            }
        }
        .frame(height: typeSize.isAccessibilitySize ? 220 : 180)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let anchor = proxy.plotFrame {
                    let plot = geometry[anchor]
                    Color.clear.preference(key: PlotBoundsKey.self, value: plot)
                    CalendarChartGesture(select: { location in
                        guard plot.contains(location), let time: Date = proxy.value(atX: location.x - plot.minX) else { return }
                        scrub = min(max(time, data.domain.lowerBound), data.domain.upperBound)
                    }, page: { _ in }, allowsPaging: false)
                }
            }
        }
        .onPreferenceChange(PlotBoundsKey.self) { if $0.width > 0 && $0 != plotBounds { plotBounds = $0 } }
        .overlay { if !hasReadings { Text("No readings").font(ZoopType.footnote).foregroundStyle(ZoopStyle.secondary).padding(8).background(ZoopStyle.surface) } }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.title) timeline")
        .accessibilityValue((reading.map { "\($0.formatted()) \(metric.unit)" } ?? "No reading") + (scrub.map { ", \(data.timeLabel($0))" } ?? ""))
        .accessibilityAdjustableAction { direction in adjustSelection(direction) }
        .accessibilityIdentifier("todayTimelineChart")
    }

    private func contextTrack(_ event: DayTimelineData.Event, intervals: [DateInterval]) -> some View {
        let tint = event == .sleep ? ZoopStyle.sleep : ZoopStyle.steps
        return VStack(alignment: .leading, spacing: 6) {
            if typeSize.isAccessibilitySize { Text(event.rawValue).font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary) }
            ZStack(alignment: .leading) {
                if !typeSize.isAccessibilitySize { Text(event.rawValue).font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary) }
                Canvas { context, _ in
                    guard plotBounds.width > 0 else { return }
                    let origin = plotBounds.minX, width = plotBounds.width
                    var baseline = Path(); baseline.move(to: CGPoint(x: origin, y: 9)); baseline.addLine(to: CGPoint(x: origin + width, y: 9))
                    context.stroke(baseline, with: .color(ZoopStyle.chartGrid), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    for interval in intervals {
                        let x = origin + width * interval.start.timeIntervalSince(data.domain.lowerBound) / data.domain.upperBound.timeIntervalSince(data.domain.lowerBound)
                        let w = width * interval.duration / data.domain.upperBound.timeIntervalSince(data.domain.lowerBound)
                        context.fill(Path(roundedRect: CGRect(x: x, y: 6, width: max(1, w), height: 6), cornerRadius: 3), with: .color(tint))
                    }
                }.frame(height: 18)
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel(event.rawValue)
            .accessibilityValue(intervals.map { "\(data.timeLabel($0.start)) to \(data.timeLabel($0.end))" }.joined(separator: ", "))
            .accessibilityIdentifier("timelineTrack-\(event.rawValue)")
    }

    private func adjustSelection(_ direction: AccessibilityAdjustmentDirection) {
        let dates = metric == .steps ? data.hours.map(\.middle) : points.map(\.date)
        guard !dates.isEmpty else { return }
        let current = scrub ?? dates.last!
        let index = dates.indices.min { abs(dates[$0].timeIntervalSince(current)) < abs(dates[$1].timeIntervalSince(current)) } ?? 0
        scrub = dates[min(max(index + (direction == .increment ? 1 : -1), 0), dates.count - 1)]
    }
    private struct PlotBoundsKey: PreferenceKey {
        static var defaultValue: CGRect { .zero }
        static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
            let next = nextValue(); if next.width > 0 { value = next }
        }
    }
}
