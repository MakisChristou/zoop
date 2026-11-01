import Combine
import SnoopProtocol
import SwiftUI

struct TodayView: View {
    let openSleep: (SnoopAPI.Night?) -> Void
    let openActivity: () -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var now = Date()
    /// Nil follows today across midnight; a chosen past day stays fixed.
    @State private var selectedDay: Date?
    @State private var loadedDay: Date?
    @State private var loading = false
    @State private var loadID = UUID()
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
                    DateNavigation(title: dayLabel, canGoBack: canStepBack, canGoForward: !isViewingToday,
                                   previousLabel: "Previous day", nextLabel: "Next day",
                                   previous: { stepDay(-1) }, next: { stepDay(1) })
                    overview
                    stepsCard
                    heartRate
                    if historyFailed {
                        Button { Task { await loadHistory() } } label: {
                            Label("Couldn’t update your day. Retry", systemImage: "arrow.clockwise")
                                .font(.footnote).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                    }
                    if !selectedWorkouts.isEmpty { sessions.padding(.top, 8) }
                    if !currentMinutes.isEmpty {
                        sectionHeading("Daily timeline").padding(.top, 14)
                        DayTimeline(minutes: currentMinutes, day: viewedDay, now: isViewingToday ? now : nil,
                                    sessions: selectedWorkouts, walkingHours: currentSteps?.walkingHours)
                            .id(viewedDay)
                    }
                    if loading && loadedDay != viewedDay {
                        ProgressView().frame(maxWidth: .infinity).accessibilityLabel("Loading day")
                    }
                    sectionHeading("Health metrics").padding(.top, 16)
                    healthMetrics
                }
                .padding(.horizontal, SnoopStyle.gutter)
                .padding(.bottom, 24)
            }
            .mainScreenChrome("Today")
            .navigationDestination(for: SnoopAPI.Workout.self) { WorkoutDetailView(workout: $0) }
            .navigationDestination(for: StepsView.Scope.self) { StepsView(initialScope: $0, day: viewedDay) }
            .onAppear(perform: applyDemoRoute)
            .refreshable { await loadHistory() }
        }
        .onReceive(clock) { now = $0 }
        .task(id: "\(model.strap.serial)-\(viewedDay.timeIntervalSince1970)") { await loadHistory() }
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
            Button { openSleep(selectedNight) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    metricLabel("Sleep", icon: "moon")
                    SleepDuration(seconds: selectedNight?.metrics.window.asleepS)
                    Text(selectedNight.map { isViewingToday ? "Last night" : $0.metrics.window.offset.formatted(.dateTime.day().month(.abbreviated)) } ?? "No night recorded")
                        .font(.caption).foregroundStyle(SnoopStyle.secondary)
                    if let night = selectedNight, !night.stages.isEmpty {
                        Hypnogram(segments: night.stages, onset: night.metrics.window.onset, offset: night.metrics.window.offset)
                            .frame(height: 22).accessibilityHidden(true)
                    } else {
                        Sparkline(values: precedingNights.map { Double($0.metrics.window.asleepS) }, color: SnoopStyle.sleep)
                            .frame(height: 22).accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                .snoopCard(padding: 14)
            }
            .buttonStyle(PressableCardStyle()).disabled(selectedNight == nil).accessibilityHint("Opens this night in Sleep")
            Button(action: openActivity) {
                VStack(alignment: .leading, spacing: 8) {
                    metricLabel("Day load", icon: "waveform.path")
                    HStack(spacing: 6) {
                        MetricValue(selectedSummary?.load.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—", size: 34)
                        Spacer(minLength: 0)
                        if let load = selectedSummary?.load, !typeSize.isAccessibilitySize {
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
                MetricValue((currentSteps?.walking ?? selectedSummary?.stepsWalking).map { $0.formatted() } ?? "—")
                    .padding(.top, 4)
                Text(selectedSummary?.walkingS.map { "\($0 / 60) min walking" } ?? (isViewingToday ? "Today" : "Walking"))
                    .font(.caption).foregroundStyle(SnoopStyle.secondary)
                if let steps = currentSteps {
                    HourlyStepsChart(hours: steps.walkingHours, day: viewedDay, compact: true)
                        .frame(height: 72).padding(.top, 8).accessibilityHidden(true)
                } else {
                    Color.clear.frame(height: 72).padding(.top, 8)
                        .overlay { if loading { ProgressView().controlSize(.small) } }
                        .accessibilityHidden(true)
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

    private var heartRate: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Label(isViewingToday ? "Heart rate" : "Average heart rate", systemImage: "heart")
                .font(.subheadline).foregroundStyle(SnoopStyle.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(heartRateValue).font(.title3.weight(.semibold)).monospacedDigit()
                Text("bpm").font(.caption).foregroundStyle(SnoopStyle.secondary)
                Text(isViewingToday ? freshness : "Day average").font(.caption).foregroundStyle(SnoopStyle.secondary).padding(.leading, 4)
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
            ForEach(selectedWorkouts) { workout in
                NavigationLink(value: workout) { WorkoutRow(workout: workout) }.buttonStyle(PressableCardStyle())
            }
        }
    }

    private var healthMetrics: some View {
        let night = selectedNight
        let columns = typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 12) {
            Tile(title: "Resting heart rate", value: night?.metrics.physiology.restingHr.map { "\(Int($0.rounded()))" } ?? "—", unit: "bpm",
                 caption: "During sleep", history: precedingNights.compactMap { $0.metrics.physiology.restingHr }, color: SnoopStyle.heartRate)
            Tile(title: "HRV", value: night?.metrics.physiology.hrvRmssdMs.map { "\(Int($0.rounded()))" } ?? "—", unit: "ms",
                 caption: "During sleep", history: precedingNights.compactMap { $0.metrics.physiology.hrvRmssdMs }, color: SnoopStyle.sleep)
            Tile(title: "Skin temperature", value: skinTemperature.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—", unit: "°C",
                 caption: isViewingToday ? freshness : "Day average", history: precedingDays.compactMap { $0.skinTempAvg }, color: SnoopStyle.temperature)
        }
    }

    private func metricLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.caption.weight(.medium)).foregroundStyle(SnoopStyle.secondary)
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title).font(.headline).accessibilityAddTraits(.isHeader)
    }

    private var selectedWorkouts: [SnoopAPI.Workout] {
        workouts.filter { Calendar.current.isDate($0.startTs, inSameDayAs: viewedDay) }.sorted { $0.startTs > $1.startTs }
    }

    private var selectedSummary: SnoopAPI.Day? {
        days.last { StepsView.day($0.day).map { Calendar.current.isDate($0, inSameDayAs: viewedDay) } == true }
    }

    private var currentSteps: SnoopAPI.StepsDay? {
        guard let steps, let day = StepsView.day(steps.day), Calendar.current.isDate(day, inSameDayAs: viewedDay) else { return nil }
        guard steps.walking > 0 || selectedSummary != nil else { return nil }
        return steps
    }

    private func applyDemoRoute() {
        #if targetEnvironment(simulator)
        switch UserDefaults.standard.string(forKey: "demoScreen") {
        case "yesterday":
            selectedDay = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: now))
        case "steps": path.append(StepsView.Scope.day)
        case "steps7d", "stepsday": path.append(StepsView.Scope.week)
        case "steps30d": path.append(StepsView.Scope.month)
        default: break
        }
        #endif
    }

    private func loadHistory() async {
        guard !model.strap.serial.isEmpty, Settings.isConfigured else { return }
        let day = viewedDay
        let serial = model.strap.serial
        let requestID = UUID()
        loadID = requestID
        loading = true
        defer { if loadID == requestID { loading = false } }
        async let d = SnoopAPI.days(deviceId: serial, limit: 30)
        async let n = SnoopAPI.nights(deviceId: serial, limit: 30)
        async let m = SnoopAPI.minutes(deviceId: serial, day: day)
        async let w = SnoopAPI.workouts(deviceId: serial, limit: 500)
        async let s = SnoopAPI.steps(deviceId: serial, day: day)
        let fetchedDays = try? await d
        let fetchedNights = try? await n
        let fetchedMinutes = try? await m
        let fetchedWorkouts = try? await w
        let fetchedSteps = try? await s
        // A slow response from a previous tap must never replace the chosen day.
        guard !Task.isCancelled, loadID == requestID, viewedDay == day, model.strap.serial == serial else { return }
        if let fetchedDays { days = fetchedDays }
        if let fetchedNights { nights = fetchedNights }
        if let fetchedWorkouts { workouts = fetchedWorkouts }
        minutes = fetchedMinutes ?? []
        steps = fetchedSteps
        loadedDay = day
        historyFailed = fetchedDays == nil || fetchedNights == nil || fetchedMinutes == nil
            || fetchedWorkouts == nil || fetchedSteps == nil
    }

    private var viewedDay: Date { selectedDay ?? Calendar.current.startOfDay(for: now) }
    private var isViewingToday: Bool { Calendar.current.isDate(viewedDay, inSameDayAs: now) }
    private var currentMinutes: [SnoopAPI.Minute] { loadedDay == viewedDay ? minutes : [] }

    private var selectedNight: SnoopAPI.Night? {
        nights.first { Calendar.current.isDate($0.metrics.window.offset, inSameDayAs: viewedDay) }
    }

    private var precedingNights: [SnoopAPI.Night] {
        nights.filter { Calendar.current.startOfDay(for: $0.metrics.window.offset) <= viewedDay }.reversed()
    }

    private var precedingDays: [SnoopAPI.Day] {
        days.filter { StepsView.day($0.day).map { $0 <= viewedDay } == true }
    }

    private var heartRateValue: String {
        if isViewingToday { return model.strap.smoothedHeartRate.map(String.init) ?? "—" }
        return selectedSummary?.hrAvg.map { String(Int($0.rounded())) } ?? "—"
    }

    private var skinTemperature: Double? {
        isViewingToday ? model.strap.lastBiometric?.skinTemperatureC.map(Double.init) : selectedSummary?.skinTempAvg
    }

    private var dayLabel: String {
        let date = viewedDay.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        if isViewingToday { return "Today · \(date)" }
        if Calendar.current.isDateInYesterday(viewedDay) { return "Yesterday · \(date)" }
        return date
    }

    private var canStepBack: Bool {
        guard let oldest = days.compactMap({ StepsView.day($0.day) }).min() else { return false }
        return viewedDay > oldest
    }

    private func stepDay(_ delta: Int) {
        guard delta < 0 ? canStepBack : !isViewingToday,
              let day = Calendar.current.date(byAdding: .day, value: delta, to: viewedDay) else { return }
        selectedDay = Calendar.current.isDate(day, inSameDayAs: now) ? nil : day
        historyFailed = false
    }

    private var freshness: String {
        guard let at = model.strap.liveUpdatedAt else { return "No reading" }
        let age = Int(now.timeIntervalSince(at))
        if model.strap.state == .ready, model.strap.realtimeStreaming, age < 5 { return "Live" }
        return age < 60 ? "\(max(0, age))s ago" : "\(age / 60)m ago"
    }
}
