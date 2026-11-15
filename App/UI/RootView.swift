import SwiftUI

/// Four tabs. Each main screen carries the strap status and the profile button in its
/// own header; the device page lives behind both.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var showDevice = false
    @State private var showECG = false
    @State private var showWeeklyWeight = false
    @State private var selection = Tab.today
    @State private var selectedNight: SnoopAPI.Night?
    @State private var selectedActivityDay: Date?
    @State private var activityRequest = UUID()
    @State private var sleepRequest = UUID()

    enum Tab: Hashable {
        case today, activity, sleep, trends
    }

    var body: some View {
        TabView(selection: $selection) {
            TodayView(openSleep: { selectedNight = $0; sleepRequest = UUID(); selection = .sleep }, openActivity: { selectedActivityDay = $0; activityRequest = UUID(); selection = .activity })
                .tabItem { Label("Today", systemImage: "square.grid.2x2") }
                .tag(Tab.today)
            ActivityView(selectedDay: $selectedActivityDay, requestID: activityRequest)
                .tabItem { Label("Activity", systemImage: "figure.run") }
                .tag(Tab.activity)
            SleepView(selected: $selectedNight).id(sleepRequest)
                .tabItem { Label("Sleep", systemImage: "moon.fill") }
                .tag(Tab.sleep)
            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Tab.trends)
        }
        .tint(SnoopStyle.load)
        .foregroundStyle(SnoopStyle.text)
        .toolbarBackground(SnoopStyle.surface, for: .tabBar)
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
        .sheet(isPresented: $showWeeklyWeight) { NavigationStack { WeeklyWeightView() } }
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

    // A cold-launch tap can arrive before the account journal has loaded.
    private func openCheckInNotification() {
        guard let current = model.health.reminderScope else { return }
        if let scope = model.battery.openECGScope {
            if scope == current { showECG = true }
            model.battery.openECGScope = nil
        }
        if let scope = model.battery.openWeeklyWeightScope {
            if scope == current { showWeeklyWeight = true }
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
        case "weekly-weight": showWeeklyWeight = true
        default: break
        }
        #endif
    }
}
