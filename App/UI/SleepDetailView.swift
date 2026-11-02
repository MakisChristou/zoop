import Charts
import SwiftUI

/// The night, full screen: stages on top, then heart rate, HRV and motion drawn on the
/// same time axis so the staging can be judged against the physiology by eye.
struct SleepDetailView: View {
    let night: SnoopAPI.Night
    var sessionID: Int64? = nil
    @Environment(AppModel.self) private var model
    @State private var epochs: [SnoopAPI.Epoch] = []
    @State private var scrub: Date?
    @State private var error: String?

    private var onset: Date { night.metrics.window.onset }
    private var offset: Date { night.metrics.window.offset }

    private var selected: SnoopAPI.Epoch? {
        guard let scrub else { return nil }
        return epochs.min { abs($0.start.timeIntervalSince(scrub)) < abs($1.start.timeIntervalSince(scrub)) }
    }

    private var selectedStage: SnoopAPI.Night.Stage? {
        guard let scrub else { return nil }
        return night.stages.first { $0.start <= scrub && scrub < $0.end }?.stage
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                readout
                stageChart
                track("Heart rate", unit: "bpm", color: SnoopStyle.heartRate, values: epochs.compactMap { e in e.hr.map { (e.start, $0) } })
                track("HRV", unit: "ms", color: SnoopStyle.sleep, values: epochs.compactMap { e in e.rmssd.map { (e.start, $0) } })
                track("Breathing", unit: "/min", color: SnoopStyle.steps, values: epochs.compactMap { e in e.respRate.map { (e.start, $0) } })
                motionTrack
                MetricInformation(title: "About these signals", text: "Sleep stages are estimated from motion, heart rate, HRV and breathing. The charts show the signals used in that estimate; they do not confirm sleep stages on their own.")
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .padding()
        }
        .snoopScreen()
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(sessionID ?? 0)-\(night.startTs)-\(night.endTs)-\(model.sleep.changeToken)-\(model.analysisRevision)") { await load() }
    }

    private var title: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: night.nightOf).map { "Night of " + $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) } ?? night.nightOf
    }

    private var readout: some View {
        HStack(alignment: .firstTextBaseline) {
            if let e = selected {
                Text(e.start.formatted(date: .omitted, time: .shortened)).font(.headline).monospacedDigit()
                if let stage = selectedStage { Text(stageName(stage)).foregroundStyle(Hypnogram.color(stage)).font(.headline) }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(e.hr.map { "\(Int($0.rounded())) bpm" } ?? "—")
                    Text(e.rmssd.map { "\(Int($0.rounded())) ms" } ?? "—").foregroundStyle(SnoopStyle.secondary)
                }
                .font(.subheadline).monospacedDigit()
            } else {
                Text("\(onset.formatted(date: .omitted, time: .shortened)) – \(offset.formatted(date: .omitted, time: .shortened))").font(.headline)
                Spacer()
                Text("Sleep detail").font(.caption).foregroundStyle(SnoopStyle.secondary)
            }
        }
        .frame(minHeight: 36)
    }

    private var stageChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Stages").font(.caption.weight(.semibold)).foregroundStyle(SnoopStyle.secondary).textCase(.uppercase)
            Chart {
                ForEach(Array(night.stages.enumerated()), id: \.offset) { _, seg in
                    RectangleMark(
                        xStart: .value("from", seg.start), xEnd: .value("to", seg.end),
                        yStart: .value("level", level(seg.stage)), yEnd: .value("level", level(seg.stage) + 0.9)
                    )
                    .foregroundStyle(Hypnogram.color(seg.stage))
                }
                if let scrub { RuleMark(x: .value("scrub", scrub)).foregroundStyle(.primary.opacity(0.6)) }
            }
            .chartXScale(domain: onset...offset)
            .chartYScale(domain: 0...4)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0.45, 1.45, 2.45, 3.45]) { v in
                    AxisValueLabel { Text(axisLabel(v.as(Double.self) ?? 0)).font(.caption2) }
                }
            }
            .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 2)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.hour()) } }
            .frame(height: 110)
            .chartOverlay { proxy in scrubOverlay(proxy) }
        }
        .padding().background(SnoopStyle.surface, in: RoundedRectangle(cornerRadius: SnoopStyle.radius))
    }

    private func track(_ name: String, unit: String, color: Color, values: [(Date, Double)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).font(.caption.weight(.semibold)).foregroundStyle(SnoopStyle.secondary).textCase(.uppercase)
                Spacer()
                Text(unit).font(.caption2).foregroundStyle(SnoopStyle.secondary)
            }
            Chart {
                ForEach(night.stages.filter { $0.stage == .deep || $0.stage == .rem }, id: \.start) { seg in
                    RectangleMark(xStart: .value("from", seg.start), xEnd: .value("to", seg.end))
                        .foregroundStyle(Hypnogram.color(seg.stage).opacity(0.14))
                }
                ForEach(grouped(values), id: \.date) { point in
                    LineMark(x: .value("Time", point.date), y: .value(name, point.value), series: .value("Recorded interval", point.group))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.2))
                        .interpolationMethod(.linear)
                }
                if let scrub { RuleMark(x: .value("scrub", scrub)).foregroundStyle(.primary.opacity(0.6)) }
            }
            .chartXScale(domain: onset...offset)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
            .frame(height: 90)
            .chartOverlay { proxy in scrubOverlay(proxy) }
        }
        .padding().background(SnoopStyle.surface, in: RoundedRectangle(cornerRadius: SnoopStyle.radius))
    }

    private var motionTrack: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Motion").font(.caption.weight(.semibold)).foregroundStyle(SnoopStyle.secondary).textCase(.uppercase)
                Spacer()
                Text("share of seconds moving").font(.caption2).foregroundStyle(SnoopStyle.secondary)
            }
            Chart {
                ForEach(epochs) { e in
                    BarMark(x: .value("Time", e.start), y: .value("moving", e.moveFrac), width: 2)
                        .foregroundStyle(e.strapAwake ? Color.orange : Color.secondary.opacity(0.6))
                }
                if let scrub { RuleMark(x: .value("scrub", scrub)).foregroundStyle(.primary.opacity(0.6)) }
            }
            .chartXScale(domain: onset...offset)
            .chartYScale(domain: 0...1)
            .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 2)) { _ in AxisValueLabel(format: .dateTime.hour()) } }
            .chartYAxis(.hidden)
            .frame(height: 60)
            .chartOverlay { proxy in scrubOverlay(proxy) }
        }
        .padding().background(SnoopStyle.surface, in: RoundedRectangle(cornerRadius: SnoopStyle.radius))
    }

    private func scrubOverlay(_ proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let x = value.location.x - geo[proxy.plotFrame!].origin.x
                            scrub = proxy.value(atX: x, as: Date.self)
                        }
                        .onEnded { _ in scrub = nil }
                )
        }
    }

    private func level(_ stage: SnoopAPI.Night.Stage) -> Double {
        switch stage {
        case .deep: 0
        case .light: 1
        case .rem: 2
        case .wake: 3
        }
    }

    private func axisLabel(_ v: Double) -> String {
        switch v {
        case ..<1: "Deep"
        case ..<2: "Light"
        case ..<3: "REM"
        default: "Awake"
        }
    }

    private func stageName(_ s: SnoopAPI.Night.Stage) -> String {
        switch s {
        case .wake: "Awake"
        case .light: "Light"
        case .deep: "Deep"
        case .rem: "REM"
        }
    }

    private struct SignalPoint { let date: Date; let value: Double; let group: Int }
    private func grouped(_ values: [(Date, Double)]) -> [SignalPoint] {
        var group = 0
        return values.enumerated().map { i, point in
            if i > 0, point.0.timeIntervalSince(values[i - 1].0) > 30 { group += 1 }
            return SignalPoint(date: point.0, value: point.1, group: group)
        }
    }

    private func load() async {
        do {
            if let sessionID { epochs = try await SnoopAPI.sleepEpochs(deviceId: model.strap.serial, id: sessionID) }
            else { epochs = try await SnoopAPI.epochs(deviceId: model.strap.serial, nightOf: night.nightOf) }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
