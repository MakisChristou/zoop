import SwiftUI

/// Five tabs. Each main screen carries the strap status and the profile button in its
/// own header; the device page lives behind both.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var showDevice = false
    @State private var showECG = false
    @State private var showSteps = false
    private struct GoalLink: Identifiable { let id: Int64; let scope: String }
    @State private var goalLink: GoalLink?
    @AppStorage("weightUnit") private var weightUnit = "kg"
    @State private var selection = Tab.today
    @State private var selectedNight: ZoopAPI.Night?
    @State private var selectedActivityDay: Date?
    @State private var activityRequest = UUID()
    @State private var sleepRequest = UUID()

    enum Tab: Hashable {
        case today, activity, sleep, trends, goals
    }

    var body: some View {
        // Reserve real space so pushed scroll views cannot extend beneath navigation.
        VStack(spacing: 0) {
            TabView(selection: $selection) {
                TodayView(openSleep: { selectedNight = $0; sleepRequest = UUID(); selection = .sleep }, openActivity: { selectedActivityDay = $0; activityRequest = UUID(); selection = .activity })
                    .tabItem { Label("Today", systemImage: "square.grid.2x2") }
                    .tag(Tab.today)
                    .toolbar(.hidden, for: .tabBar)
                ActivityView(selectedDay: $selectedActivityDay, requestID: activityRequest)
                    .tabItem { Label("Activity", systemImage: "figure.run") }
                    .tag(Tab.activity)
                    .toolbar(.hidden, for: .tabBar)
                SleepView(selected: $selectedNight).id(sleepRequest)
                    .tabItem { Label("Sleep", systemImage: "moon.fill") }
                    .tag(Tab.sleep)
                    .toolbar(.hidden, for: .tabBar)
                TrendsView()
                    .tabItem { Label("Trends", systemImage: "chart.line.uptrend.xyaxis") }
                    .tag(Tab.trends)
                    .toolbar(.hidden, for: .tabBar)
                NavigationStack { GoalsView() }
                    .tabItem { Label("Goals", systemImage: "target") }
                    .tag(Tab.goals)
                    .toolbar(.hidden, for: .tabBar)
            }
            .toolbar(.hidden, for: .tabBar)
            navigationBar
        }
        .background(ZoopStyle.background.ignoresSafeArea())
        .tint(ZoopStyle.text)
        .foregroundStyle(ZoopStyle.text)
        .task {
            #if targetEnvironment(simulator)
            if UserDefaults.standard.string(forKey: "demoScreen") != nil { return }
            #endif
            await model.battery.requestNotificationsIfNeeded()
            model.refreshReminders()
        }
        .onChange(of: model.battery.openBattery, initial: true) { _, open in
            if open { showDevice = true; model.battery.openBattery = false }
        }
        .onChange(of: model.battery.openWorkout, initial: true) { _, id in
            if id != nil { selection = .activity }
        }
        .sheet(item: $goalLink) { link in
            if model.health.reminderScope == link.scope { GoalPeriodView(id: link.id, store: model.weeklyWeight, unit: weightUnit) }
        }
        .sheet(isPresented: $showSteps) { NavigationStack { StepsView() } }
        .onChange(of: model.battery.openStepsScope, initial: true) { _, _ in openCheckInNotification() }
        .onChange(of: model.battery.openWeeklyWeightScope, initial: true) { _, _ in openCheckInNotification() }
        .sheet(isPresented: $showECG) { ProfileSheet(open: .ecg) }
        .onChange(of: model.battery.openECGScope, initial: true) { _, scope in
            openCheckInNotification()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in model.refreshReminders() }
        .sheet(isPresented: $showDevice) { ProfileSheet(open: .device) }
        .sheet(isPresented: Binding(get: { model.health.showWeightEntry }, set: { model.health.showWeightEntry = $0 })) { WeightEntryView() }
        .onChange(of: model.battery.openWeightScope, initial: true) { _, scope in
            openCheckInNotification()
        }
        .onChange(of: model.health.reminderScope) { _, _ in openCheckInNotification() }
        .onChange(of: model.sleep.changeToken) { _, _ in model.health.checkSoon() }
        .onChange(of: model.activity.changeToken) { _, _ in model.health.checkSoon() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.ecg.cancel() }
            if phase == .active { model.refreshReminders(); Task { await model.health.refreshReminderCompletion() }; model.health.activate(model.strap.serial); model.health.checkSoon(); model.workouts.checkSoon(force: true); if model.analysisUpdating { model.refreshAnalysis() } }
        }
        .onAppear(perform: applyDemoRoute)
    }

    private var navigationBar: some View {
        HStack(spacing: 0) {
            tab(.today, title: "Today", icon: "square.grid.2x2")
            tab(.activity, title: "Activity", icon: "figure.run")
            tab(.sleep, title: "Sleep", icon: "moon")
            tab(.trends, title: "Trends", icon: "chart.line.uptrend.xyaxis")
            tab(.goals, title: "Goals", icon: "target")
        }
        .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 2)
        .background(ZoopStyle.background)
        .overlay(alignment: .top) { Rectangle().fill(ZoopStyle.separator).frame(height: 0.5) }
        .accessibilityElement(children: .contain).accessibilityLabel("Main navigation")
        .accessibilityIdentifier("mainNavigation")
    }

    private func tab(_ tab: Tab, title: String, icon: String) -> some View {
        Button { selection = tab } label: {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 19, weight: .regular))
                Text(title).font(ZoopType.caption2)
            }.frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selection == tab ? ZoopStyle.text : ZoopStyle.secondary)
        .accessibilityLabel(title).accessibilityIdentifier("tab-\(title)")
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
        .accessibilityShowsLargeContentViewer()
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    // A cold-launch tap can arrive before the account journal has loaded.
    private func openCheckInNotification() {
        guard let current = model.health.reminderScope else { return }
        if let scope = model.battery.openECGScope {
            if scope == current { showECG = true }
            model.battery.openECGScope = nil
        }
        if let scope = model.battery.openStepsScope {
            if scope == current { showSteps = true }
            model.battery.openStepsScope = nil
        }
        if let scope = model.battery.openWeeklyWeightScope {
            if scope == current {
                selection = .goals
                let id = model.battery.openWeeklyWeightID
                Task {
                    await model.weeklyWeight.reload()
                    guard model.health.reminderScope == scope else { return }
                    if let id, model.weeklyWeight.goal?.id != id || model.weeklyWeight.goal?.active != true { goalLink = GoalLink(id: id, scope: scope) }
                }
            }
            model.battery.openWeeklyWeightID = nil
            model.battery.openWeeklyWeightScope = nil
        }
        if let scope = model.battery.openWeightScope {
            if scope == current { selection = .today; model.health.openReminder(scope: scope) }
            model.battery.openWeightScope = nil
        }
    }

    /// Simulator builds can be launched on a given tab for screenshots
    /// (`-demoScreen activity`); the simulator has no Bluetooth, so nothing else
    /// could get there.
    private func applyDemoRoute() {
        #if targetEnvironment(simulator)
        switch UserDefaults.standard.string(forKey: "demoScreen") {
        case "activity": selection = .activity
        case "sleep": selection = .sleep
        case "trends": selection = .trends
        case "battery": showDevice = true
        case "weekly-weight", "goals": selection = .goals
        default: break
        }
        #endif
    }
}
