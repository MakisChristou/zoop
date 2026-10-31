import SnoopProtocol
import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @State private var now = Date()
    @State private var minutes: [SnoopAPI.Minute] = []
    @State private var days: [SnoopAPI.Day] = []
    @State private var nights: [SnoopAPI.Night] = []
    @State private var workouts: [SnoopAPI.Workout] = []
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heartRateHero
                    if !minutes.isEmpty {
                        DayTimeline(minutes: minutes, now: now, sessions: todaysWorkouts).padding(.horizontal)
                    }
                    if !todaysWorkouts.isEmpty { sessions }
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
            .navigationDestination(for: SnoopAPI.Workout.self) { WorkoutDetailView(workout: $0) }
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
            NavigationLink {
                StepsDetailView()
            } label: {
                Tile(title: "Steps", value: days.last?.stepsWalking.map { $0.formatted() } ?? b.map { "\($0.steps)" } ?? "—", unit: "",
                     caption: stepsCaption, history: days.compactMap { $0.stepsWalking.map(Double.init) }, linked: true)
            }
            .buttonStyle(PressableCardStyle())
            Tile(title: "Load", value: days.last?.load.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—", unit: "",
                 caption: loadCaption, history: days.compactMap(\.load))
            Tile(title: "Skin temp", value: b?.skinTemperatureC.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—", unit: "°C",
                 caption: "now", history: days.compactMap { $0.skinTempAvg })
            Tile(title: "Strap says", value: b.map { bandStateText($0.bandState) } ?? "—", unit: "", caption: "its own rest flag", history: [])
        }
        .padding(.horizontal)
    }

    /// Today's sessions as cards, newest first; each opens its detail.
    private var sessions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's activity").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            ForEach(todaysWorkouts) { workout in
                NavigationLink(value: workout) { WorkoutRow(workout: workout) }.buttonStyle(PressableCardStyle())
            }
        }
        .padding(.horizontal)
    }

    private var todaysWorkouts: [SnoopAPI.Workout] {
        workouts.filter { Calendar.current.isDateInToday($0.startTs) }.sorted { $0.startTs > $1.startTs }
    }

    /// Hard minutes and calories once the day has been analysed; the scale otherwise.
    private var loadCaption: String {
        guard let today = days.last, today.load != nil else { return "0–21, builds through the day" }
        var parts: [String] = []
        if let zones = today.zonesMin, zones.count == 5 {
            let hard = zones[2] + zones[3] + zones[4]
            parts.append(hard > 0 ? "\(hard) min hard" : "nothing hard yet")
        }
        if let kcal = today.kcal, kcal > 0 { parts.append("\(Int(kcal.rounded())) kcal in sessions") }
        return parts.isEmpty ? "0–21 scale" : parts.joined(separator: " · ")
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
        async let w = SnoopAPI.workouts(deviceId: model.strap.serial, limit: 20)
        if let d = try? await d { days = d }
        if let n = try? await n { nights = n }
        if let m = try? await m { minutes = m }
        if let w = try? await w { workouts = w }
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
