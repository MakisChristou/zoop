import Combine
import SnoopProtocol
import SwiftUI

struct TodayView: View {
    let openSleep: () -> Void
    let openActivity: () -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var now = Date()
    @State private var minutes: [SnoopAPI.Minute] = []
    @State private var days: [SnoopAPI.Day] = []
    @State private var nights: [SnoopAPI.Night] = []
    @State private var workouts: [SnoopAPI.Workout] = []
    @State private var steps: SnoopAPI.StepsDay?
    @State private var path = NavigationPath()
    @State private var historyFailed = false
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    overview
                    stepsCard
                    liveHeartRate
                    if historyFailed {
                        Button { Task { await loadHistory() } } label: {
                            Label("Couldn’t update your day. Retry", systemImage: "arrow.clockwise")
                                .font(.footnote).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                    }
                    if !todaysWorkouts.isEmpty { sessions.padding(.top, 8) }
                    if !minutes.isEmpty {
                        sectionHeading("Daily timeline").padding(.top, 14)
                        DayTimeline(minutes: minutes, now: now, sessions: todaysWorkouts, walkingHours: currentSteps?.walkingHours)
                    }
                    sectionHeading("Health metrics").padding(.top, 16)
                    healthMetrics
                }
                .padding(.horizontal, SnoopStyle.gutter)
                .padding(.bottom, 24)
            }
            .mainScreenChrome("Today", subtitle: now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .navigationDestination(for: SnoopAPI.Workout.self) { WorkoutDetailView(workout: $0) }
            .navigationDestination(for: StepsView.Scope.self) { StepsView(initialScope: $0) }
            .onAppear(perform: applyDemoRoute)
            .refreshable { await loadHistory() }
        }
        .onReceive(clock) { now = $0 }
        .task(id: model.strap.serial) { await loadHistory() }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(300)) } catch { return }
                await loadHistory()
            }
        }
        .onAppear { model.strap.setRealtimeHeartRate(true) }
        .onDisappear { model.strap.setRealtimeHeartRate(false) }
        .onChange(of: model.strap.state) { _, state in
            if state == .ready { model.strap.setRealtimeHeartRate(true) }
        }
    }

    private var overview: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            Button(action: openSleep) {
                VStack(alignment: .leading, spacing: 8) {
                    metricLabel("Sleep", icon: "moon")
                    SleepDuration(seconds: nights.first?.metrics.window.asleepS)
                    Text(nights.first.map { Calendar.current.isDateInToday($0.endTs) ? "Last night" : $0.endTs.formatted(.dateTime.day().month(.abbreviated)) } ?? "No night recorded")
                        .font(.caption).foregroundStyle(SnoopStyle.secondary)
                    if let night = nights.first, !night.stages.isEmpty {
                        Hypnogram(segments: night.stages, onset: night.metrics.window.onset, offset: night.metrics.window.offset)
                            .frame(height: 22).accessibilityHidden(true)
                    } else {
                        Sparkline(values: nights.reversed().map { Double($0.metrics.window.asleepS) }, color: SnoopStyle.sleep)
                            .frame(height: 22).accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                .snoopCard(padding: 14)
            }
            .buttonStyle(PressableCardStyle()).accessibilityHint("Opens Sleep")
            Button(action: openActivity) {
                VStack(alignment: .leading, spacing: 8) {
                    metricLabel("Day load", icon: "waveform.path")
                    HStack(spacing: 6) {
                        MetricValue(today?.load.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—", size: 34)
                        Spacer(minLength: 0)
                        if let load = today?.load, !typeSize.isAccessibilitySize {
                            LoadRing(load: load, lineWidth: 4).frame(width: 42, height: 42).accessibilityHidden(true)
                        }
                    }
                    Text("0–21 scale").font(.caption).foregroundStyle(SnoopStyle.secondary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                .snoopCard(padding: 14)
            }
            .buttonStyle(PressableCardStyle()).accessibilityHint("Opens Activity")
        }
    }

    private var stepsCard: some View {
        NavigationLink(value: StepsView.Scope.day) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    metricLabel("Steps", icon: "shoeprints.fill")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.medium)).foregroundStyle(SnoopStyle.secondary)
                }
                MetricValue((currentSteps?.walking ?? today?.stepsWalking).map { $0.formatted() } ?? "—")
                    .padding(.top, 4)
                Text(today?.walkingS.map { "\($0 / 60) min walking" } ?? "Today")
                    .font(.caption).foregroundStyle(SnoopStyle.secondary)
                if let steps = currentSteps {
                    HourlyStepsChart(hours: steps.walkingHours, day: now, compact: true)
                        .frame(height: 72).padding(.top, 8).accessibilityHidden(true)
                } else {
                    Sparkline(values: days.compactMap { $0.stepsWalking.map(Double.init) }, color: SnoopStyle.steps)
                        .frame(height: 40).padding(.top, 8).accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .snoopCard()
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("openSteps")
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens steps by hour and by day")
    }

    private var liveHeartRate: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Label("Heart rate", systemImage: "heart")
                .font(.subheadline).foregroundStyle(SnoopStyle.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(model.strap.smoothedHeartRate.map(String.init) ?? "—").font(.title3.weight(.semibold)).monospacedDigit()
                Text("bpm").font(.caption).foregroundStyle(SnoopStyle.secondary)
                Text(freshness).font(.caption).foregroundStyle(SnoopStyle.secondary).padding(.leading, 4)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var sessions: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionHeading("Activity")
                Spacer()
                Button("See all", action: openActivity).font(.caption).frame(minHeight: 44)
            }
            ForEach(todaysWorkouts) { workout in
                NavigationLink(value: workout) { WorkoutRow(workout: workout) }.buttonStyle(PressableCardStyle())
            }
        }
    }

    private var healthMetrics: some View {
        let night = nights.first
        let columns = typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 12) {
            Tile(title: "Resting heart rate", value: night?.metrics.physiology.restingHr.map { "\(Int($0.rounded()))" } ?? "—", unit: "bpm",
                 caption: "During sleep", history: nights.reversed().compactMap { $0.metrics.physiology.restingHr }, color: SnoopStyle.heartRate)
            Tile(title: "HRV", value: night?.metrics.physiology.hrvRmssdMs.map { "\(Int($0.rounded()))" } ?? "—", unit: "ms",
                 caption: "During sleep", history: nights.reversed().compactMap { $0.metrics.physiology.hrvRmssdMs }, color: SnoopStyle.sleep)
            Tile(title: "Skin temperature", value: model.strap.lastBiometric?.skinTemperatureC.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—", unit: "°C",
                 caption: freshness, history: days.compactMap { $0.skinTempAvg }, color: SnoopStyle.temperature)
        }
    }

    private func metricLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.caption.weight(.medium)).foregroundStyle(SnoopStyle.secondary)
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title).font(.headline).accessibilityAddTraits(.isHeader)
    }

    private var todaysWorkouts: [SnoopAPI.Workout] {
        workouts.filter { Calendar.current.isDate($0.startTs, inSameDayAs: now) }.sorted { $0.startTs > $1.startTs }
    }

    private var today: SnoopAPI.Day? {
        days.last { StepsView.day($0.day).map { Calendar.current.isDate($0, inSameDayAs: now) } == true }
    }

    private var currentSteps: SnoopAPI.StepsDay? {
        guard let steps, let day = StepsView.day(steps.day), Calendar.current.isDate(day, inSameDayAs: now) else { return nil }
        guard steps.walking > 0 || today != nil else { return nil }
        return steps
    }

    private func applyDemoRoute() {
        #if targetEnvironment(simulator)
        switch UserDefaults.standard.string(forKey: "demoScreen") {
        case "steps": path.append(StepsView.Scope.day)
        case "steps7d", "stepsday": path.append(StepsView.Scope.week)
        case "steps30d": path.append(StepsView.Scope.month)
        default: break
        }
        #endif
    }

    private func loadHistory() async {
        guard !model.strap.serial.isEmpty, Settings.isConfigured else { return }
        let day = Date()
        async let d = SnoopAPI.days(deviceId: model.strap.serial, limit: 14)
        async let n = SnoopAPI.nights(deviceId: model.strap.serial, limit: 14)
        async let m = SnoopAPI.minutes(deviceId: model.strap.serial, day: day)
        async let w = SnoopAPI.workouts(deviceId: model.strap.serial, limit: 20)
        async let s = SnoopAPI.steps(deviceId: model.strap.serial, day: day)
        var failed = false
        do { days = try await d } catch { failed = true }
        if let n = try? await n { nights = n }
        if let m = try? await m { minutes = m }
        if let w = try? await w { workouts = w }
        do { steps = try await s } catch { failed = true }
        historyFailed = failed
    }

    private var freshness: String {
        guard let at = model.strap.liveUpdatedAt else { return "No reading" }
        let age = Int(now.timeIntervalSince(at))
        if model.strap.state == .ready, model.strap.realtimeStreaming, age < 5 { return "Live" }
        return age < 60 ? "\(max(0, age))s ago" : "\(age / 60)m ago"
    }
}
