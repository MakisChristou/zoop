import Combine
import SnoopProtocol
import SwiftUI

struct TodayView: View {
    let openSleep: (SnoopAPI.Night?) -> Void
    let openActivity: (Date) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var now = Date()
    /// Nil follows today across midnight; a chosen past day stays fixed.
    @State private var selectedDay: Date?
    @State private var loadedDay: Date?
    @State private var loading = false
    @State private var loadID = UUID()
    @State private var minutes: [SnoopAPI.Minute] = []
    @State private var days: [SnoopAPI.Day] = []
    @State private var nights: [SnoopAPI.Night] = []
    private var workouts: [SnoopAPI.Workout] { model.activity.items }
    @State private var steps: SnoopAPI.StepsDay?
    @State private var path = NavigationPath()
    @State private var historyFailed = false
    @State private var morning = MorningInsightsStore()
    private var insights: MorningInsights? { morning.value(for: insightScope) }
    private var insightsFailed: Bool { morning.failed(for: insightScope) }
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    DateNavigation(title: dayLabel, canGoBack: canStepBack, canGoForward: !isViewingToday,
                                   previousLabel: "Previous day", nextLabel: "Next day",
                                   previous: { stepDay(-1) }, next: { stepDay(1) },
                                   reset: { selectedDay = nil }, canReset: !isViewingToday)
                    if let insights {
                        MorningBriefView(insights: insights, day: viewedDay)
                    } else if insightsFailed {
                        Button("Couldn’t update morning insights. Retry") { Task { await loadHistory() } }
                            .font(.footnote).frame(minHeight: 44)
                    }
                    if isViewingToday { WeightCheckIn() }
                    overview
                    stepsCard
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
                    } else if isViewingToday {
                        TodayLiveMetric(kind: .heartRate, isViewingToday: true, summary: selectedSummary, history: []).snoopCard()
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
            .mainScreenChrome(screenTitle)
            .onAppear { visible = true }
            .onDisappear { visible = false; morning.stop() }
            .navigationDestination(for: SnoopAPI.Workout.self) { WorkoutDetailView(workout: $0) }
            .navigationDestination(for: StepsView.Scope.self) { StepsView(initialScope: $0, day: viewedDay) }
            .onAppear(perform: applyDemoRoute)
            .refreshable { await loadHistory() }
        }
        .onChange(of: model.sleep.changeToken) { _, _ in Task { await loadHistory() } }
        .onChange(of: model.analysisRevision) { _, _ in Task { await loadHistory() } }
        .onChange(of: model.activity.changeToken) { _, _ in Task { await loadHistory() } }
        .onReceive(clock) { if !Calendar.current.isDate(now, inSameDayAs: $0) { now = $0 } }
        .task(id: "\(model.strap.serial)-\(viewedDay.timeIntervalSince1970)") { await loadHistory() }
        .task(id: MorningInsightsStore.FollowKey(scope: insightScope, active: visible && scenePhase == .active)) {
            guard visible, scenePhase == .active, Settings.isConfigured else {
                morning.stop(clear: !Settings.isConfigured); return
            }
            let scope = insightScope
            await morning.follow(scope) { visible && scenePhase == .active && insightScope == scope }
        }
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
            Button { openActivity(viewedDay) } label: {
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
            .buttonStyle(PressableCardStyle()).accessibilityHint("Opens Activity").accessibilityIdentifier("openDayActivity")
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
                if let target = CutTargets.steps(goal: model.weeklyWeight.goal, day: viewedDay, now: now) {
                    StepGoalProgress(steps: currentSteps?.walking ?? selectedSummary?.stepsWalking, target: target)
                } else {
                    Text(selectedSummary?.walkingS.map { "\($0 / 60) min walking" } ?? (isViewingToday ? "Today" : "Walking"))
                        .font(.caption).foregroundStyle(SnoopStyle.secondary)
                }
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

    private var sessions: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionHeading("Activity")
                Spacer()
                Button("See all") { openActivity(viewedDay) }.font(.caption).frame(minHeight: 44)
            }
            ForEach(selectedWorkouts) { workout in
                NavigationLink(value: workout) { WorkoutRow(workout: workout) }.buttonStyle(PressableCardStyle())
            }
        }
    }

    private var healthMetrics: some View {
        TodayLiveMetric(kind: .temperature, isViewingToday: isViewingToday, summary: selectedSummary,
                        history: precedingDays.compactMap { $0.skinTempAvg })
    }

    private func metricLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.caption.weight(.medium)).foregroundStyle(SnoopStyle.secondary)
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title).font(.headline).accessibilityAddTraits(.isHeader)
    }

    private var selectedWorkouts: [SnoopAPI.Workout] {
        workouts.filter { $0.startTs < (Calendar.current.date(byAdding: .day, value: 1, to: viewedDay) ?? viewedDay) && $0.endTs > viewedDay }.sorted { $0.startTs > $1.startTs }
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
        let connection = Settings.connectionID
        let requestID = UUID()
        loadID = requestID
        loading = true
        defer { if loadID == requestID { loading = false } }
        let scope = insightScope
        async let brief: Void = morning.reload(scope) { insightScope == scope && visible && scenePhase == .active }
        async let d = SnoopAPI.days(deviceId: serial, limit: 30)
        async let n = SnoopAPI.nights(deviceId: serial, limit: 30)
        async let m = SnoopAPI.minutes(deviceId: serial, day: day)
        async let w: Void = model.activity.reload(device: serial, from: day, to: Calendar.current.date(byAdding: .day, value: 1, to: day))
        async let s = SnoopAPI.steps(deviceId: serial, day: day)
        await brief
        let fetchedDays = try? await d
        let fetchedNights = try? await n
        let fetchedMinutes = try? await m
        let fetchedWorkouts: Void? = try? await w
        let fetchedSteps = try? await s
        // A slow response from a previous tap must never replace the chosen day.
        guard !Task.isCancelled, loadID == requestID, viewedDay == day, model.strap.serial == serial, Settings.connectionID == connection else { return }
        if let fetchedDays { days = fetchedDays }
        if let fetchedNights { nights = fetchedNights }

        minutes = fetchedMinutes ?? []
        steps = fetchedSteps
        if let fetchedSteps { model.stepsReminder.receive(fetchedSteps, scope: model.health.reminderScope) }
        loadedDay = day
        historyFailed = fetchedDays == nil || fetchedNights == nil || fetchedMinutes == nil
            || fetchedWorkouts == nil || fetchedSteps == nil
    }

    private var viewedDay: Date { selectedDay ?? Calendar.current.startOfDay(for: now) }
    private var insightScope: MorningInsightsStore.Scope {
        .init(device: model.strap.serial, day: viewedDay, connection: Settings.connectionID, timezone: TimeZone.current.identifier)
    }
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

    private var screenTitle: String {
        if isViewingToday { return "Today" }
        if Calendar.current.isDateInYesterday(viewedDay) { return "Yesterday" }
        return viewedDay.formatted(.dateTime.weekday(.wide))
    }

    private var dayLabel: String {
        viewedDay.formatted(.dateTime.day().month(.wide).year())
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


}
