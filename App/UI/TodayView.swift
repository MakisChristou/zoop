import SnoopProtocol
import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @State private var now = Date()
    @State private var minutes: [SnoopAPI.Minute] = []
    @State private var days: [SnoopAPI.Day] = []
    @State private var nights: [SnoopAPI.Night] = []
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heartRateHero
                    if !minutes.isEmpty {
                        DayTimeline(minutes: minutes, now: now).padding(.horizontal)
                    }
                    tiles
                    if model.strap.state != .ready {
                        Text(hint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .navigationBarTitleDisplayMode(.large)
        }
        .onReceive(clock) { now = $0 }
        .task { await loadHistory() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                await loadHistory()
            }
        }
        .refreshable { await loadHistory() }
        .onAppear { model.strap.setRealtimeHeartRate(true) }
        .onDisappear { model.strap.setRealtimeHeartRate(false) }
        .onChange(of: model.strap.state) { _, state in
            if state == .ready { model.strap.setRealtimeHeartRate(true) }
        }
    }

    private var heartRateHero: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Heart rate", systemImage: "heart.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(model.strap.smoothedHeartRate.map(String.init) ?? "—")
                    .font(.system(size: 72, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("bpm").font(.title3).foregroundStyle(.secondary)
            }
            Text(freshness)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var tiles: some View {
        let b = model.strap.lastBiometric
        let lastNight = nights.first
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            Tile(title: "Sleep", value: lastNight.map { hours($0.metrics.window.asleepS) } ?? "—", unit: "h",
                 caption: lastNight.map { "last night · \(Int(($0.metrics.window.efficiency * 100).rounded())) % efficient" } ?? "no night yet",
                 history: nights.reversed().map { Double($0.metrics.window.asleepS) / 3600 })
            Tile(title: "Resting HR", value: lastNight?.metrics.physiology.restingHr.map { "\(Int($0.rounded()))" } ?? "—", unit: "bpm",
                 caption: "lowest 5 min of sleep", history: nights.reversed().compactMap { $0.metrics.physiology.restingHr })
            Tile(title: "HRV", value: lastNight?.metrics.physiology.hrvRmssdMs.map { "\(Int($0.rounded()))" } ?? rmssdText, unit: "ms",
                 caption: lastNight == nil ? "RMSSD, last 10 s live" : "RMSSD, last night", history: nights.reversed().compactMap { $0.metrics.physiology.hrvRmssdMs })
            Tile(title: "Steps", value: days.last?.stepsWalking.map(String.init) ?? b.map { "\($0.steps)" } ?? "—", unit: "",
                 caption: stepsCaption, history: days.compactMap { $0.stepsWalking.map(Double.init) })
            Tile(title: "Skin temp", value: b?.skinTemperatureC.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—", unit: "°C",
                 caption: "now", history: days.compactMap { $0.skinTempAvg })
            Tile(title: "Strap says", value: b.map { bandStateText($0.bandState) } ?? "—", unit: "", caption: "its own rest flag", history: [])
        }
        .padding(.horizontal)
    }

    /// Walking-filtered count as the headline, raw counter and walking time as context.
    private var stepsCaption: String {
        guard let today = days.last, let walking = today.stepsWalking else { return "today, strap counter" }
        var parts = ["while walking"]
        if let s = today.walkingS { parts.append("\(s / 60) min on foot") }
        if let raw = today.steps, raw > walking { parts.append("\(raw) raw") }
        return parts.joined(separator: " · ")
    }

    private func hours(_ seconds: Int) -> String {
        String(format: "%.1f", Double(seconds) / 3600)
    }

    private func loadHistory() async {
        guard !model.strap.serial.isEmpty, Settings.isConfigured else { return }
        async let d = SnoopAPI.days(deviceId: model.strap.serial, limit: 14)
        async let n = SnoopAPI.nights(deviceId: model.strap.serial, limit: 14)
        async let m = SnoopAPI.minutes(deviceId: model.strap.serial, day: Date())
        if let d = try? await d { days = d }
        if let n = try? await n { nights = n }
        if let m = try? await m { minutes = m }
    }

    private var freshness: String {
        guard let at = model.strap.liveUpdatedAt else { return "Waiting for the first reading" }
        let age = Int(now.timeIntervalSince(at))
        if model.strap.realtimeStreaming, age < 5 { return "Live" }
        return age < 60 ? "\(age) s ago" : "\(age / 60) min ago"
    }

    private var hint: String {
        switch model.strap.state {
        case .scanning: "Make sure the strap is on your wrist, nearby, and the official WHOOP app is fully closed."
        case .bluetoothOff: "Turn Bluetooth on to connect to the strap."
        case .failed: "Connection failed. The Device tab has details."
        default: "Connecting to the strap…"
        }
    }

    private var rmssdText: String {
        let rr = model.strap.liveRR.map(Double.init)
        guard rr.count >= 2 else { return "—" }
        let diffs = zip(rr.dropFirst(), rr).map { $0 - $1 }
        let value = (diffs.map { $0 * $0 }.reduce(0, +) / Double(diffs.count)).squareRoot()
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    private func bandStateText(_ state: BandState) -> String {
        switch state {
        case .wake: "awake"
        case .still: "still"
        case .sleep: "asleep"
        case .up: "up"
        }
    }
}

private struct Tile: View {
    let title: String
    let value: String
    let unit: String
    let caption: String
    let history: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(.title, design: .rounded).weight(.semibold)).monospacedDigit()
                if !unit.isEmpty { Text(unit).font(.subheadline).foregroundStyle(.secondary) }
            }
            Text(caption).font(.caption2).foregroundStyle(.tertiary)
            Sparkline(values: history)
                .frame(height: 22)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }
}


/// Fourteen-day context under a tile. Draws nothing until there are two points.
private struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            if values.count >= 2, let lo = values.min(), let hi = values.max() {
                let span = max(hi - lo, 0.0001)
                Path { path in
                    for (i, v) in values.enumerated() {
                        let x = geo.size.width * CGFloat(i) / CGFloat(values.count - 1)
                        let y = geo.size.height * (1 - CGFloat((v - lo) / span))
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(.secondary.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            } else {
                Text(values.isEmpty ? " " : "1 day").font(.caption2).foregroundStyle(.quaternary)
            }
        }
    }
}
