import Combine
import ZoopProtocol
import SwiftUI

struct TodayView: View {
    let openSleep: (ZoopAPI.Night?) -> Void
    let openActivity: (Date) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var now = Date()
    @AppStorage(SleepGoal.storageKey) private var sleepGoalMinutes = SleepGoal.defaultMinutes
    /// Nil follows today across midnight; a chosen past day stays fixed.
    @State private var selectedDay: Date?
    @State private var loadedDay: Date?
    @State private var loading = false
    @State private var loadID = UUID()
    @State private var minutes: [ZoopAPI.Minute] = []
    @State private var days: [ZoopAPI.Day] = []
    @State private var nights: [ZoopAPI.Night] = []
    private var workouts: [ZoopAPI.Workout] { model.activity.items }
    @State private var steps: ZoopAPI.StepsDay?
    @State private var path = NavigationPath()
    @State private var historyFailed = false
    @State private var morning = MorningInsightsStore()
    private var insights: MorningInsights? { morning.value(for: insightScope) }
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    DateNavigation(title: dayLabel, canGoBack: canStepBack, canGoForward: !isViewingToday,
                                   previousLabel: "Previous day", nextLabel: "Next day",
                                   previous: { stepDay(-1) }, next: { stepDay(1) },
                                   reset: { selectedDay = nil }, canReset: !isViewingToday)
                    overview.padding(.top, 12)
                    outlookStatus.padding(.bottom, 12)
                    sectionHeading("Activity")
                    stepsCard
                    if historyFailed {
                        Button { Task { await loadHistory() } } label: {
                            Label("Couldn’t update your day. Retry", systemImage: "arrow.clockwise")
                                .font(ZoopType.footnote).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                    }
                    if !selectedWorkouts.isEmpty { sessions.padding(.top, 8) }
                    if isViewingToday {
                        sectionHeading("Weight").padding(.top, 8)
                        WeightCheckIn().padding(.bottom, 12)
                    }
                    if !currentMinutes.isEmpty {
                        sectionHeading("Daily timeline").padding(.top, 14)
                        DayTimeline(minutes: currentMinutes, day: viewedDay, now: isViewingToday ? now : nil,
                                    sessions: selectedWorkouts, walkingHours: currentSteps?.walkingHours)
                            .id(viewedDay)
                    } else if isViewingToday {
                        TodayLiveMetric(kind: .heartRate, isViewingToday: true, summary: selectedSummary, history: []).zoopCard()
                    }
                    sectionHeading("Health metrics").padding(.top, 16)
                    healthMetrics
                }
                .padding(.horizontal, ZoopStyle.gutter)
                .padding(.bottom, 24)
            }
            .mainScreenChrome(screenTitle)
            .zoopLoading(loading, label: "Loading day")
            .onAppear { visible = true }
            .onDisappear { visible = false; morning.stop() }
            .navigationDestination(for: ZoopAPI.Workout.self) { WorkoutDetailView(workout: $0) }
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
        let sleepGoal = SleepGoal(minutes: sleepGoalMinutes)
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 24))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            Button { openSleep(selectedNight) } label: {
                TodaySummaryRing(title: "Sleep", value: selectedNight.map {
                    "\($0.metrics.window.asleepS / 3600)h \(($0.metrics.window.asleepS % 3600) / 60)m"
                } ?? "—", color: ZoopStyle.sleep, progress: sleepGoal.progress(asleepSeconds: selectedNight?.metrics.window.asleepS), isLoading: loading)
            }
            .buttonStyle(.plain).disabled(selectedNight == nil)
            .accessibilityValue(selectedNight.map {
                let seconds = $0.metrics.window.asleepS
                return "\(seconds / 3600)h \((seconds % 3600) / 60)m, \(sleepGoal.percentage(asleepSeconds: seconds)) of \(sleepGoal.title) goal" + (loading ? ", updating" : "")
            } ?? (loading ? "Loading" : "No reading"))
            .accessibilityIdentifier("openSleepSummary").accessibilityHint("Opens this night in Sleep")
            NavigationLink(value: StepsView.Scope.day) {
                if let target = stepTarget {
                    StepGoalProgress(steps: stepCount, target: target, ringPresentation: true, isLoading: loading)
                } else {
                    TodaySummaryRing(title: "Steps", value: stepCount?.formatted() ?? "—",
                                     color: ZoopStyle.text, isLoading: loading)
                }
            }
            .buttonStyle(.plain).accessibilityIdentifier("openStepsSummary")
            .accessibilityHint("Opens steps by hour and by day")
            Button { openActivity(viewedDay) } label: {
                TodaySummaryRing(title: "Load", value: selectedSummary?.load.map {
                    $0.formatted(.number.precision(.fractionLength(1)))
                } ?? "—", color: ZoopStyle.load, progress: selectedSummary?.load.map { $0 / LoadRing.maximum } ?? 0, isLoading: loading)
            }
            .buttonStyle(.plain).accessibilityHint("Opens Activity").accessibilityIdentifier("openDayActivity")
        }.frame(maxWidth: .infinity)
            .background {
                Canvas { context, size in
                    for x in stride(from: 8.0, to: size.width, by: 20) {
                        for y in stride(from: 8.0, to: size.height - 28, by: 20) {
                            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)),
                                         with: .color(ZoopStyle.secondary.opacity(0.12)))
                        }
                    }
                }.accessibilityHidden(true).allowsHitTesting(false)
            }
    }

    private var stepCount: Int? { currentSteps?.walking ?? selectedSummary?.stepsWalking }
    private var stepTarget: Int? { CutTargets.steps(goal: model.weeklyWeight.goal, day: viewedDay, now: now) }

    private var outlookStatus: some View {
        let updating = morning.loading || insights?.state == "updating" || insights?.state == "awaiting_sync"
        let title = insights?.outlookTitle ?? (morning.failed(for: insightScope) ? "Retry" : "—")
        return NavigationLink { MorningInsightsView(day: viewedDay) } label: {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                Text("Outlook").foregroundStyle(ZoopStyle.secondary).fixedSize()
                HStack(spacing: 8) {
                    if updating {
                        ProgressView().controlSize(.mini).tint(ZoopStyle.secondary)
                    } else if title != "—" && title != "Retry" {
                        Circle().fill(outlookColor).frame(width: 6, height: 6)
                    }
                    Text(updating && title == "—" ? "Updating" : title).foregroundStyle(ZoopStyle.text)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Image(systemName: "chevron.right").font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                }
            }
            .font(ZoopType.subheadline).frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore).accessibilityLabel("Outlook")
            .accessibilityValue(updating && title == "—" ? "Loading" : title)
        }
        .buttonStyle(.plain).accessibilityIdentifier("openMorningInsights")
        .accessibilityHint("Opens your nightly comparisons")
    }

    private var outlookColor: Color {
        switch insights?.outlook?.state {
        case "good": ZoopStyle.favourable
        case "average", "mixed": ZoopStyle.typical
        case "low": ZoopStyle.unfavourable
        default: ZoopStyle.secondary
        }
    }

    private var stepsCard: some View {
        NavigationLink(value: StepsView.Scope.day) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    metricLabel("Steps by hour", icon: "shoeprints.fill")
                    Spacer()
                    Image(systemName: "chevron.right").font(ZoopType.font(size: 12, weight: .medium, relativeTo: .caption)).foregroundStyle(ZoopStyle.secondary)
                }
                if let steps = currentSteps {
                    HourlyStepsChart(hours: steps.walkingHours, day: viewedDay, compact: true)
                        .frame(height: 164).padding(.top, 8).accessibilityHidden(true)
                } else {
                    Color.clear.frame(height: 164).padding(.top, 8)
                        .overlay { if loading { ProgressView().controlSize(.small) } }
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .zoopCard()
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("openSteps")
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens steps by hour and by day")
    }

    private var sessions: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Workouts").font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                Spacer()
                Button("See all") { openActivity(viewedDay) }.font(ZoopType.caption).frame(minHeight: 44)
            }
            ForEach(selectedWorkouts) { workout in
                NavigationLink(value: workout) { WorkoutRow(workout: workout) }.buttonStyle(PressableCardStyle())
            }
        }
    }

    private var healthMetrics: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let insights {
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                layout {
                    ForEach(insights.metrics.filter { $0.key != "sleep" }) { metric in
                        NavigationLink { MorningInsightsView(day: viewedDay) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(metric.key == "resting_hr" ? "Resting HR" : metric.title).font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                                MetricValue(metric.formatted(metric.value), unit: metric.unit, size: 24)
                                if let delta = metric.visibleDelta {
                                    Text(delta).font(ZoopType.caption).foregroundStyle(InsightTone.color(metric.comparison?.signal))
                                }
                            }.frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                        }.buttonStyle(.plain)
                    }
                }.zoopCard()
            }
            TodayLiveMetric(kind: .temperature, isViewingToday: isViewingToday, summary: selectedSummary,
                            history: precedingDays.compactMap { $0.skinTempAvg })
        }
    }

    private func metricLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(ZoopType.font(size: 12, weight: .medium, relativeTo: .caption)).foregroundStyle(ZoopStyle.secondary)
    }

    private func sectionHeading(_ title: String) -> some View {
        HStack(spacing: 12) {
            Text(title).font(ZoopStyle.sectionTitle).foregroundStyle(ZoopStyle.secondary)
            Rectangle().fill(ZoopStyle.separator).frame(height: 0.5)
        }.accessibilityAddTraits(.isHeader)
    }

    private var selectedWorkouts: [ZoopAPI.Workout] {
        workouts.filter { $0.startTs < (Calendar.current.date(byAdding: .day, value: 1, to: viewedDay) ?? viewedDay) && $0.endTs > viewedDay }.sorted { $0.startTs > $1.startTs }
    }

    private var selectedSummary: ZoopAPI.Day? {
        days.last { StepsView.day($0.day).map { Calendar.current.isDate($0, inSameDayAs: viewedDay) } == true }
    }

    private var currentSteps: ZoopAPI.StepsDay? {
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
        async let d = ZoopAPI.days(deviceId: serial, limit: 30)
        async let n = ZoopAPI.nights(deviceId: serial, limit: 30)
        async let m = ZoopAPI.minutes(deviceId: serial, day: day)
        async let w: Void = model.activity.reload(device: serial, from: day, to: Calendar.current.date(byAdding: .day, value: 1, to: day))
        async let s = ZoopAPI.steps(deviceId: serial, day: day)
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
    private var currentMinutes: [ZoopAPI.Minute] { loadedDay == viewedDay ? minutes : [] }

    private var selectedNight: ZoopAPI.Night? {
        nights.first { Calendar.current.isDate($0.metrics.window.offset, inSameDayAs: viewedDay) }
    }

    private var precedingNights: [ZoopAPI.Night] {
        nights.filter { Calendar.current.startOfDay(for: $0.metrics.window.offset) <= viewedDay }.reversed()
    }

    private var precedingDays: [ZoopAPI.Day] {
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
