import Charts
import SwiftUI

/// The day as a scrubbable strip: heart rate per minute with the strap's own states
/// shaded behind it (asleep, walking), skin temperature below, and steps per hour.
struct DayTimeline: View {
    let minutes: [SnoopAPI.Minute]
    let day: Date
    var now: Date?
    /// Detected sessions, shaded in their kind's colour behind the heart rate.
    var sessions: [SnoopAPI.Workout] = []
    var walkingHours: [Int]?
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var scrub: Date?

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

    private var selected: SnoopAPI.Minute? {
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
        .background(SnoopStyle.surface, in: RoundedRectangle(cornerRadius: SnoopStyle.radius))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Heart rate").font(.caption.weight(.semibold)).foregroundStyle(SnoopStyle.secondary).textCase(.uppercase)
            Spacer()
            if let m = selected {
                Text(m.ts.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(SnoopStyle.secondary)
                Text(m.hr.map { "\($0) bpm" } ?? "—").font(.caption.weight(.semibold)).monospacedDigit()
                if let t = m.skinTempC { Text(String(format: "%.1f °C", t)).font(.caption).foregroundStyle(SnoopStyle.secondary) }
            } else if let range = hrRange {
                Text("\(range.lowerBound)–\(range.upperBound) bpm").font(.caption).foregroundStyle(SnoopStyle.secondary)
            }
        }
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
                    .foregroundStyle(span.kind == .asleep ? SnoopStyle.sleep.opacity(0.22) : SnoopStyle.steps.opacity(0.18))
            }
            ForEach(sessions) { w in
                RectangleMark(xStart: .value("from", w.startTs), xEnd: .value("to", w.endTs))
                    .foregroundStyle(ActivityKind.named(w.kind).color.opacity(0.22))
            }
            ForEach(minutes.filter { $0.hr != nil }) { m in
                AreaMark(x: .value("Time", m.ts), yStart: .value("min", m.hrMin ?? m.hr!), yEnd: .value("max", m.hrMax ?? m.hr!))
                    .foregroundStyle(SnoopStyle.heartRate.opacity(0.18))
                LineMark(x: .value("Time", m.ts), y: .value("HR", m.hr!))
                    .foregroundStyle(SnoopStyle.heartRate)
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
            }
            if let now {
                RuleMark(x: .value("Now", now)).foregroundStyle(.secondary.opacity(0.4)).lineStyle(StrokeStyle(dash: [3, 3]))
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
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let plot = proxy.plotFrame else { return }
                                let x = value.location.x - geo[plot].origin.x
                                scrub = proxy.value(atX: x, as: Date.self)
                            }
                            .onEnded { _ in scrub = nil }
                    )
            }
        }
    }

    private var skinTemperatureChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Skin temp").font(.caption2.weight(.semibold)).foregroundStyle(SnoopStyle.secondary).textCase(.uppercase)
            Chart(minutes.filter { $0.skinTempC != nil }) { m in
                LineMark(x: .value("Time", m.ts), y: .value("°C", m.skinTempC!))
                    .foregroundStyle(SnoopStyle.temperature)
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
            Text("Steps").font(.caption.weight(.medium)).foregroundStyle(SnoopStyle.secondary)
            if let walkingHours {
                Chart(Array(walkingHours.prefix(24).enumerated()), id: \.offset) { hour, steps in
                    BarMark(x: .value("Hour", Double(hour) + 0.5), y: .value("Steps", steps))
                        .foregroundStyle(SnoopStyle.steps).cornerRadius(2)
                }
                .chartXScale(domain: 0...24)
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 2)) }
                .frame(height: 56)
            } else {
                Text("Not available").font(.caption).foregroundStyle(SnoopStyle.secondary).frame(height: 56)
            }
        }
    }

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), alignment: .leading)], alignment: .leading, spacing: 8) {
            Label { Text("asleep") } icon: { RoundedRectangle(cornerRadius: 2).fill(SnoopStyle.sleep.opacity(0.4)).frame(width: 12, height: 8) }
            Label { Text("walking") } icon: { RoundedRectangle(cornerRadius: 2).fill(SnoopStyle.steps.opacity(0.4)).frame(width: 12, height: 8) }
            if !sessions.isEmpty {
                Label { Text("session") } icon: { RoundedRectangle(cornerRadius: 2).fill(SnoopStyle.load.opacity(0.5)).frame(width: 12, height: 8) }
            }
            Label { Text("heart rate") } icon: { RoundedRectangle(cornerRadius: 2).fill(SnoopStyle.heartRate.opacity(0.5)).frame(width: 12, height: 8) }
        }
        .font(.caption2).foregroundStyle(SnoopStyle.secondary)
    }
}
