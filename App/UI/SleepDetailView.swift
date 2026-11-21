import Charts
import SwiftUI

/// Server-recorded sleep signals, with one shared time selection across the night.
struct SleepDetailView: View {
    let night: ZoopAPI.Night
    var sessionID: Int64? = nil
    var timezone: TimeZone = .current
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var epochs: [ZoopAPI.Epoch] = []
    @State private var scrub: Date?
    @State private var error: String?
    @State private var loading = true

    private var onset: Date { night.metrics.window.onset }
    private var offset: Date { night.metrics.window.offset }
    private var domain: ClosedRange<Date> { onset...max(offset, onset.addingTimeInterval(1)) }
    private var ticks: [Date] { SleepChartTime.ticks(from: onset, to: offset, timezone: timezone) }
    private var selectedStage: ZoopAPI.Night.Stage? {
        guard let scrub else { return nil }
        return night.stages.first { $0.start <= scrub && scrub < $0.end }?.stage
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                stageCard
                if loading {
                    ProgressView("Loading signals").font(ZoopType.footnote)
                        .frame(maxWidth: .infinity, minHeight: 144).zoopCard()
                } else if let error {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Couldn’t load signals").font(ZoopStyle.sectionTitle)
                        Text(error).font(ZoopType.footnote).foregroundStyle(ZoopStyle.secondary)
                        Button("Try again") { Task { await load() } }.frame(minHeight: 44)
                    }.frame(maxWidth: .infinity, alignment: .leading).zoopCard()
                } else {
                    track("Heart rate", unit: "bpm", values: epochs.compactMap { e in e.hr.map { (e.start, $0) } })
                    track("HRV", unit: "ms", values: epochs.compactMap { e in e.rmssd.map { (e.start, $0) } })
                    track("Breathing", unit: "/min", values: epochs.compactMap { e in e.respRate.map { (e.start, $0) } })
                    motionTrack
                }
                MetricInformation(title: "About these signals", text: "Sleep stages are estimated from motion, heart rate, HRV and breathing. The charts show the signals used in that estimate; they do not confirm sleep stages on their own. Motion is the share of each interval spent moving; yellow marks intervals the strap recorded as awake.")
            }
            .padding(ZoopStyle.gutter)
        }
        .zoopScreen()
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(sessionID ?? 0)-\(night.startTs)-\(night.endTs)-\(model.sleep.changeToken)-\(model.analysisRevision)") { await load() }
    }

    private var title: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = timezone
        guard let date = f.date(from: night.nightOf) else { return night.nightOf }
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return "Night of " + f.string(from: date)
    }
    private func time(_ date: Date) -> String { SleepChartTime.label(date, timezone: timezone) }

    private var stageCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Time asleep").font(ZoopStyle.sectionTitle)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    SleepDuration(seconds: night.metrics.window.asleepS, size: 24)
                    stageReadout
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    SleepDuration(seconds: night.metrics.window.asleepS, size: 24)
                    Spacer(minLength: 16)
                    stageReadout
                }
            }
            if night.stages.isEmpty {
                Text("Stages unavailable").font(ZoopType.footnote).foregroundStyle(ZoopStyle.secondary)
            } else {
                Hypnogram(segments: night.stages, onset: onset, offset: offset, timezone: timezone, selection: $scrub)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).zoopCard()
    }

    private var stageReadout: some View {
        Text(scrub.map { "\(time($0)) · \(stageName(selectedStage))" } ?? "\(time(onset)) – \(time(offset))")
            .font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary).monospacedDigit()
            .accessibilityIdentifier("sleepDetailSelection")
    }

    private func track(_ name: String, unit: String, values: [(Date, Double)]) -> some View {
        let points = grouped(values)
        let selected = scrub.flatMap { date in points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) } }
        // Do not present a nearby sample as a reading inside a missing interval.
        let reading = selected.flatMap { point in scrub.map { abs(point.date.timeIntervalSince($0)) <= 30 } == true ? point : nil }
        return VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(ZoopStyle.sectionTitle)
                Spacer(minLength: 12)
                Text(reading.map { "\($0.value.formatted(.number.precision(.fractionLength(name == "Breathing" ? 1 : 0)))) \(unit)" } ?? (scrub == nil ? unit : "— \(unit)"))
                    .font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary).monospacedDigit()
            }
            if points.isEmpty {
                Text("No readings").font(ZoopType.footnote).foregroundStyle(ZoopStyle.secondary)
                    .frame(maxWidth: .infinity, minHeight: 144)
            } else {
                Chart {
                    ForEach(points, id: \.date) { point in
                        LineMark(x: .value("Time", point.date), y: .value(name, point.value), series: .value("Recorded interval", point.group))
                            .foregroundStyle(ZoopStyle.text)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.linear)
                        if point.isIsolated {
                            PointMark(x: .value("Time", point.date), y: .value(name, point.value))
                                .foregroundStyle(ZoopStyle.text).symbolSize(12)
                        }
                    }
                    if let scrub {
                        RuleMark(x: .value("Time", scrub)).foregroundStyle(ZoopStyle.secondary.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1))
                    }
                    if let marker = scrub == nil ? points.last : reading {
                        PointMark(x: .value("Time", marker.date), y: .value(name, marker.value))
                            .foregroundStyle(ZoopStyle.text.opacity(0.12)).symbolSize(130)
                        PointMark(x: .value("Time", marker.date), y: .value(name, marker.value))
                            .foregroundStyle(ZoopStyle.text).symbolSize(25)
                    }
                }
                .chartXScale(domain: domain)
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis { timeAxis }
                .chartYAxis { zoopChartYAxis() }
                .font(ZoopType.caption2).frame(height: 164)
                .chartOverlay { proxy in scrubOverlay(proxy) }
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityLabel("\(name) during sleep")
                .accessibilityIdentifier("sleepSignal-\(name)")
            }
        }.zoopCard()
    }

    private var motionTrack: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Motion").font(ZoopStyle.sectionTitle)
                Spacer()
                Text("%").font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
            }
            if epochs.isEmpty {
                Text("No readings").font(ZoopType.footnote).foregroundStyle(ZoopStyle.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Chart {
                    ForEach(epochs) { e in
                        BarMark(x: .value("Time", e.start), y: .value("Moving (%)", e.moveFrac * 100), width: 2)
                            .foregroundStyle(e.strapAwake ? ZoopStyle.typical : ZoopStyle.secondary.opacity(0.6))
                    }
                    if let scrub { RuleMark(x: .value("Time", scrub)).foregroundStyle(ZoopStyle.secondary.opacity(0.5)) }
                }
                .chartXScale(domain: domain)
                .chartYScale(domain: 0...100)
                .chartXAxis { timeAxis }
                .chartYAxis { zoopChartYAxis() }
                .frame(height: 110)
                .chartOverlay { proxy in scrubOverlay(proxy) }
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityLabel("Motion during sleep")
            }
        }.zoopCard()
    }

    private var timeAxis: some AxisContent {
        AxisMarks(values: ticks) { mark in
            AxisValueLabel {
                if let date = mark.as(Date.self) { Text(time(date)).font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary) }
            }
        }
    }
    private func scrubOverlay(_ proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            CalendarChartGesture(select: { point in
                guard let anchor = proxy.plotFrame else { return }
                let frame = geo[anchor]
                let x = min(max(0, point.x - frame.minX), frame.width)
                scrub = proxy.value(atX: x, as: Date.self)
            }, page: { _ in }, endInspection: { scrub = nil }, allowsPaging: false)
                .accessibilityHidden(true)
        }
    }
    private func stageName(_ stage: ZoopAPI.Night.Stage?) -> String {
        switch stage { case .wake: "Awake"; case .light: "Light"; case .deep: "Deep"; case .rem: "REM"; case nil: "No stage" }
    }

    private struct SignalPoint { let date: Date; let value: Double; let group: Int; let isIsolated: Bool }
    private func grouped(_ values: [(Date, Double)]) -> [SignalPoint] {
        let values = values.filter { $0.1.isFinite && domain.contains($0.0) }
        var group = 0
        return values.enumerated().map { i, point in
            let gapBefore = i == 0 || point.0.timeIntervalSince(values[i - 1].0) > 30
            let gapAfter = i == values.count - 1 || values[i + 1].0.timeIntervalSince(point.0) > 30
            if gapBefore { group += 1 }
            return SignalPoint(date: point.0, value: point.1, group: group, isIsolated: gapBefore && gapAfter)
        }
    }
    private func load() async {
        loading = true; error = nil; scrub = nil
        do {
            let readings: [ZoopAPI.Epoch]
            if let sessionID { readings = try await ZoopAPI.sleepEpochs(deviceId: model.dataDevice, id: sessionID) }
            else { readings = try await ZoopAPI.epochs(deviceId: model.dataDevice, nightOf: night.nightOf) }
            guard !Task.isCancelled else { return }
            epochs = readings.filter { domain.contains($0.start) }.sorted { $0.start < $1.start }
            loading = false
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription; loading = false
        }
    }
}
