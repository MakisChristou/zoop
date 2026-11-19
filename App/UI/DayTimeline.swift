import Charts
import SwiftUI

/// The day as a scrubbable strip: heart rate per minute with the strap's own states
/// shaded behind it (asleep, walking), skin temperature below, and steps per hour.
struct DayTimeline: View {
    let minutes: [ZoopAPI.Minute]
    let day: Date
    var now: Date?
    /// Detected sessions, shaded in their kind's colour behind the heart rate.
    var sessions: [ZoopAPI.Workout] = []
    var walkingHours: [Int]?
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var scrub: Date?
    @GestureState private var horizontalDrag: Bool?

    private var dayStart: Date { Calendar.current.startOfDay(for: day) }
    private var dayEnd: Date { Calendar.current.date(byAdding: .day, value: 1, to: dayStart)! }

    private struct Span: Identifiable {
        let start: Date
        let end: Date
        let kind: Kind
        enum Kind { case asleep, walking }
        var id: Date { start }
    }

    /// Consecutive minutes with the same label, merged into spans for shading.
    private var spans: [Span] {
        var out: [Span] = []
        for m in minutes {
            let kind: Span.Kind? = m.bandState == 2 ? .asleep : ((m.activity ?? 0) >= 1 ? .walking : nil)
            guard let kind else { continue }
            let end = m.ts.addingTimeInterval(60)
            if let last = out.last, last.kind == kind, last.end >= m.ts {
                out[out.count - 1] = Span(start: last.start, end: end, kind: kind)
            } else {
                out.append(Span(start: m.ts, end: end, kind: kind))
            }
        }
        return out
    }

    private var selected: ZoopAPI.Minute? {
        guard let scrub else { return nil }
        return minutes.min { abs($0.ts.timeIntervalSince(scrub)) < abs($1.ts.timeIntervalSince(scrub)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            heartRateChart
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 16)) : AnyLayout(HStackLayout(spacing: 16))
            layout {
                skinTemperatureChart
                stepsChart
            }
            legend
        }
        .padding()
        .background(ZoopStyle.surface, in: RoundedRectangle(cornerRadius: ZoopStyle.radius))
    }

    private var header: some View {
        Group {
            if let m = selected {
                HStack(alignment: .firstTextBaseline) {
                    Text("Heart rate").font(.subheadline).foregroundStyle(ZoopStyle.secondary)
                    Spacer()
                    Text(m.hr.map { "\($0) bpm" } ?? "—").font(.title3.weight(.semibold)).monospacedDigit()
                    Text(m.ts.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(ZoopStyle.secondary)
                }.accessibilityElement(children: .combine)
            } else if now != nil {
                TodayLiveMetric(kind: .heartRate, isViewingToday: true, summary: nil, history: [])
            } else {
                HStack {
                    Text("Heart rate").font(.subheadline).foregroundStyle(ZoopStyle.secondary)
                    Spacer()
                    if let range = hrRange { Text("\(range.lowerBound)–\(range.upperBound) bpm").font(.caption).foregroundStyle(ZoopStyle.secondary) }
                }
            }
        }.frame(minHeight: 44)
    }

    private var hrRange: ClosedRange<Int>? {
        let values = minutes.compactMap(\.hr)
        guard let lo = values.min(), let hi = values.max() else { return nil }
        return lo...hi
    }

    private var heartRateChart: some View {
        Chart {
            ForEach(spans) { span in
                RectangleMark(xStart: .value("from", span.start), xEnd: .value("to", span.end))
                    .foregroundStyle(span.kind == .asleep ? ZoopStyle.sleep.opacity(0.22) : ZoopStyle.steps.opacity(0.18))
            }
            ForEach(sessions) { w in
                RectangleMark(xStart: .value("from", w.startTs), xEnd: .value("to", w.endTs))
                    .foregroundStyle(ActivityKind.named(w.kind).color.opacity(0.22))
            }
            ForEach(minutes.filter { $0.hr != nil }) { m in
                AreaMark(x: .value("Time", m.ts), yStart: .value("min", m.hrMin ?? m.hr!), yEnd: .value("max", m.hrMax ?? m.hr!))
                    .foregroundStyle(ZoopStyle.heartRate.opacity(0.18))
                LineMark(x: .value("Time", m.ts), y: .value("HR", m.hr!))
                    .foregroundStyle(ZoopStyle.heartRate)
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
            }
            if let m = selected {
                RuleMark(x: .value("Scrub", m.ts)).foregroundStyle(.primary.opacity(0.6))
                if let hr = m.hr {
                    PointMark(x: .value("Scrub", m.ts), y: .value("HR", hr)).foregroundStyle(.primary)
                }
            }
        }
        .chartXScale(domain: dayStart...dayEnd)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 6)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.hour()) } }
        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
        .frame(height: 150)
        .chartOverlay { proxy in
            GeometryReader { geo in
                if now != nil, let plot = proxy.plotFrame {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if let x = proxy.position(forX: context.date) {
                            Path { path in
                                path.move(to: CGPoint(x: geo[plot].minX + x, y: geo[plot].minY))
                                path.addLine(to: CGPoint(x: geo[plot].minX + x, y: geo[plot].maxY))
                            }.stroke(.secondary.opacity(0.4), style: StrokeStyle(dash: [3, 3]))
                        }
                    }.allowsHitTesting(false)
                }
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 16)
                            .updating($horizontalDrag) { value, horizontal, _ in
                                if horizontal == nil { horizontal = abs(value.translation.width) > abs(value.translation.height) }
                            }
                            .onChanged { value in
                                guard horizontalDrag ?? (abs(value.translation.width) > abs(value.translation.height)),
                                      let plot = proxy.plotFrame, geo[plot].contains(value.startLocation) else { return }
                                let x = min(max(value.location.x - geo[plot].minX, 0), geo[plot].width)
                                scrub = proxy.value(atX: x, as: Date.self)
                            }
                            .onEnded { _ in scrub = nil }
                    )
            }
        }
        .accessibilityIdentifier("todayHeartRateChart")
    }

    private var skinTemperatureChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Skin temp").font(.caption2.weight(.semibold)).foregroundStyle(ZoopStyle.secondary).textCase(.uppercase)
            Chart(minutes.filter { $0.skinTempC != nil }) { m in
                LineMark(x: .value("Time", m.ts), y: .value("°C", m.skinTempC!))
                    .foregroundStyle(ZoopStyle.temperature)
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            .chartXScale(domain: dayStart...dayEnd)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 2)) }
            .frame(height: 56)
        }
    }

    private var stepsChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Steps").font(.caption.weight(.medium)).foregroundStyle(ZoopStyle.secondary)
            if let walkingHours {
                Chart(Array(walkingHours.prefix(24).enumerated()), id: \.offset) { hour, steps in
                    BarMark(x: .value("Hour", Double(hour) + 0.5), y: .value("Steps", steps))
                        .foregroundStyle(ZoopStyle.steps).cornerRadius(2)
                }
                .chartXScale(domain: 0...24)
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 2)) }
                .frame(height: 56)
            } else {
                Text("Not available").font(.caption).foregroundStyle(ZoopStyle.secondary).frame(height: 56)
            }
        }
    }

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), alignment: .leading)], alignment: .leading, spacing: 8) {
            Label { Text("asleep") } icon: { RoundedRectangle(cornerRadius: 2).fill(ZoopStyle.sleep.opacity(0.4)).frame(width: 12, height: 8) }
            Label { Text("walking") } icon: { RoundedRectangle(cornerRadius: 2).fill(ZoopStyle.steps.opacity(0.4)).frame(width: 12, height: 8) }
            if !sessions.isEmpty {
                Label { Text("session") } icon: { RoundedRectangle(cornerRadius: 2).fill(ZoopStyle.load.opacity(0.5)).frame(width: 12, height: 8) }
            }
            Label { Text("heart rate") } icon: { RoundedRectangle(cornerRadius: 2).fill(ZoopStyle.heartRate.opacity(0.5)).frame(width: 12, height: 8) }
        }
        .font(.caption2).foregroundStyle(ZoopStyle.secondary)
    }
}
