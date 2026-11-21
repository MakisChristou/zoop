import ZoopData
import Charts
import SwiftUI

struct RecoveryHistoryChart: View {
    let snapshot: RecoveryHistoryStore.Snapshot
    let initialDay: String
    var detail = false
    var insights: MorningInsights?
    var onSelection: (Date, String) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var range: TrendRange = .month
    @State private var anchor: Date?
    @State private var selected: Date?
    private var calendar: Calendar { snapshot.calendar }
    private var initialFocus: Date { DayKey.date(initialDay, timeZone: calendar.timeZone) ?? calendar.startOfDay(for: snapshot.now) }
    private var focus: Date { selected ?? initialFocus }
    private var interval: DateInterval { range.interval(containing: anchor ?? initialFocus, calendar: calendar) }
    private var points: [RecoveryHistoryStore.Point] {
        snapshot.points.filter { $0.date >= interval.start && $0.date < interval.end }
    }
    private var reading: RecoveryDay? { snapshot.byDay[DayKey.string(focus, timeZone: calendar.timeZone)] }
    private var dateStyle: Date.FormatStyle { .init(calendar: calendar, timeZone: calendar.timeZone) }

    var body: some View {
        VStack(spacing: 12) {
            if detail { selectionSummary.padding(.vertical, 8) }
            Picker("Period", selection: $range) {
                ForEach(TrendRange.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("recoveryRange")
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack { title; Spacer(); counts }
                    VStack(alignment: .leading, spacing: 8) { title; counts }
                }
                paging
                if !detail { selectionSummary }
                chart
                if !detail {
                    Divider().overlay(ZoopStyle.separator)
                    measurements
                }
            }.zoopCard()
            if detail {
                VStack(alignment: .leading, spacing: 16) {
                    measurements
                    if let insights, insights.day == DayKey.string(focus, timeZone: calendar.timeZone), insights.recovery?.displayedScore != nil {
                        ForEach(insights.metrics.filter { $0.key == "sleep" }) { metric in
                            Divider().overlay(ZoopStyle.separator)
                            metricRow("Time asleep", text: metric.formatted(metric.value))
                        }
                        if let limiting = insights.recovery?.limitingText {
                            Divider().overlay(ZoopStyle.separator)
                            metricRow("Main influence", text: limiting)
                        }
                        if insights.recovery?.conflict == true {
                            Text("Heart readings differ").font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                        }
                    }
                }.zoopCard()
            }
        }
        .onAppear { notifySelection() }
        .onChange(of: snapshot.timezone) { _, _ in notifySelection() }
        .onChange(of: focus) { _, _ in notifySelection() }
        .onChange(of: initialDay) { _, _ in selected = nil; anchor = nil }
        .onChange(of: range) { _, _ in anchor = focus }
    }

    private var title: some View { Text("Daily recovery").font(ZoopStyle.sectionTitle) }
    private var counts: some View {
        HStack(spacing: 12) {
            count("high", color: ZoopStyle.favourable, label: "High")
            count("moderate", color: ZoopStyle.typical, label: "Moderate")
            count("low", color: ZoopStyle.unfavourable, label: "Low")
        }
    }
    private func count(_ band: String, color: Color, label: String) -> some View {
        let number = points.filter { $0.row.recovery.displayedScore != nil && $0.row.recovery.band == band }.count
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(number)").font(ZoopType.caption).monospacedDigit().foregroundStyle(ZoopStyle.secondary)
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(label): \(number) days")
    }
    private var selectionSummary: some View {
        VStack(alignment: detail ? .center : .leading, spacing: 6) {
            Text(focus.formatted(dateStyle.weekday(.abbreviated).day().month(.abbreviated)))
                .font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                .accessibilityIdentifier("recoverySelectedDate")
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: detail ? .center : .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            layout {
                Text(reading?.recovery.displayedScore.map { "\($0)%" } ?? "—")
                    .font(ZoopType.font(size: detail ? 36 : 22, weight: .medium, relativeTo: .title)).monospacedDigit()
                    .accessibilityIdentifier("recoveryHistoryScore")
                Text(reading?.recovery.status ?? "No reading")
                    .font(ZoopType.subheadline).foregroundStyle(RecoveryTone.color(reading?.recovery))
                    .accessibilityIdentifier("recoveryStatus")
            }
        }.frame(maxWidth: .infinity, alignment: detail ? .center : .leading)
    }
    private var measurements: some View {
        VStack(spacing: 12) {
            metricRow("HRV", text: reading?.hrvMs.map { String(format: "%.0f ms", $0) } ?? "—")
            metricRow("Resting HR", text: reading?.restingHr.map { String(format: "%.0f bpm", $0) } ?? "—")
        }
    }
    private func metricRow(_ title: String, text: String) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        return layout {
            Text(title).font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 12) }
            Text(text).font(ZoopType.subheadline).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
    private var chart: some View {
        Chart {
            ForEach(points, id: \.row.day) { point in
                if let score = point.row.recovery.displayedScore {
                    RectangleMark(xStart: .value("Day start", point.start),
                            xEnd: .value("Day end", point.end),
                            yStart: .value("Baseline", 0), yEnd: .value("Recovery", score))
                        .foregroundStyle(RecoveryTone.color(point.row.recovery)).cornerRadius(2)
                    if score == 0 {
                        PointMark(x: .value("Day", point.date), y: .value("Recovery", 0))
                            .foregroundStyle(RecoveryTone.color(point.row.recovery)).symbolSize(12)
                    }
                }
            }
            RuleMark(x: .value("Selected day", calendar.date(bySettingHour: 12, minute: 0, second: 0, of: focus)!))
                .foregroundStyle(ZoopStyle.secondary.opacity(0.45)).lineStyle(StrokeStyle(lineWidth: 1))
        }
        .chartXScale(domain: interval.start...interval.end)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 33, 67, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4])).foregroundStyle(ZoopStyle.separator)
                AxisValueLabel { if let n = value.as(Int.self) { Text("\(n)%").font(ZoopType.fixed(size: 11)).foregroundStyle(ZoopStyle.secondary) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                AxisValueLabel(anchor: value.index == 0 ? .topLeading : value.index == 2 ? .topTrailing : .top, collisionResolution: .disabled) {
                    if let date = value.as(Date.self) { Text(date.formatted(dateStyle.day().month(.abbreviated))).font(ZoopType.fixed(size: 11)).foregroundStyle(ZoopStyle.secondary) }
                }
            }
        }
        .frame(height: 180)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                CalendarChartGesture(select: { location in
                    guard let frame = proxy.plotFrame else { return }
                    let plot = geometry[frame], x = min(max(location.x - plot.minX, 0), plot.width)
                    guard let date: Date = proxy.value(atX: x), date <= snapshot.now else { return }
                    selected = calendar.startOfDay(for: date)
                }, page: move)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily recovery chart")
        .accessibilityValue("\(focus.formatted(dateStyle.day().month(.wide))), \(reading?.recovery.displayedScore.map { "\($0) percent" } ?? "No reading")")
        .accessibilityIdentifier("recoveryHistoryChart")
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? 1 : -1
            guard let date = calendar.date(byAdding: .day, value: delta, to: focus), date <= snapshot.now,
                  date >= calendar.date(byAdding: .day, value: -365, to: snapshot.now)! else { return }
            selected = date; anchor = date
        }
        .accessibilityAction(named: "Previous period") { move(-1) }
        .accessibilityAction(named: "Next period") { move(1) }
    }
    private var ticks: [Date] {
        let last = calendar.date(byAdding: .day, value: -1, to: interval.end)!
        return [interval.start, interval.start.addingTimeInterval(last.timeIntervalSince(interval.start) / 2), last]
    }
    private var paging: some View {
        HStack {
            Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .disabled(destination(-1) == nil).accessibilityLabel("Previous recovery period")
            Spacer(minLength: 0)
            Text(range.title(interval, calendar: calendar)).font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                .multilineTextAlignment(.center).accessibilityIdentifier("recoveryPeriod")
            Spacer(minLength: 0)
            Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .disabled(destination(1) == nil).accessibilityLabel("Next recovery period")
        }.buttonStyle(.plain)
    }
    private func destination(_ direction: Int) -> DateInterval? {
        let next = range.moved(interval, by: direction, calendar: calendar)
        let first = snapshot.points.first?.date ?? snapshot.now
        return next.start <= snapshot.now && next.end > first ? next : nil
    }
    private func move(_ direction: Int) {
        guard let next = destination(direction) else { return }
        anchor = next.start
        selected = calendar.startOfDay(for: min(next.end.addingTimeInterval(-1), snapshot.now))
    }
    private func notifySelection() { onSelection(focus, snapshot.timezone) }
}
