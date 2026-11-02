import SwiftUI

/// Five tabs. Each main screen carries the strap status and the profile button in its
/// own header; the device page lives behind both.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = Tab.today
    @State private var selectedNight: SnoopAPI.Night?
    @State private var selectedActivityDay: Date?
    @State private var activityRequest = UUID()
    @State private var sleepRequest = UUID()

    enum Tab: Hashable {
        case today, activity, sleep, trends, battery
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
            BatteryView()
                .tabItem { Label("Battery", systemImage: "battery.100percent") }
                .tag(Tab.battery)
        }
        .tint(SnoopStyle.load)
        .foregroundStyle(SnoopStyle.text)
        .toolbarBackground(SnoopStyle.surface, for: .tabBar)
        .task {
            #if targetEnvironment(simulator)
            if UserDefaults.standard.string(forKey: "demoScreen") != nil { return }
            #endif
            await model.battery.requestNotificationsIfNeeded()
        }
        .onChange(of: model.battery.openBattery, initial: true) { _, open in
            if open { selection = .battery; model.battery.openBattery = false }
        }
        .onChange(of: model.battery.openWorkout, initial: true) { _, id in
            if id != nil { selection = .activity }
        }
        .sheet(isPresented: Binding(get: { model.health.showWeightEntry }, set: { model.health.showWeightEntry = $0 })) { WeightEntryView() }
        .onChange(of: model.battery.openWeightScope, initial: true) { _, scope in
            if let scope { selection = .today; model.health.openReminder(scope: scope); model.battery.openWeightScope = nil }
        }
        .onChange(of: model.sleep.changeToken) { _, _ in model.health.checkSoon() }
        .onChange(of: model.activity.changeToken) { _, _ in model.health.checkSoon() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.health.activate(model.strap.serial); model.health.checkSoon(); model.workouts.checkSoon(force: true); if model.analysisUpdating { model.refreshAnalysis() } }
        }
        .onAppear(perform: applyDemoRoute)
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
        case "battery": selection = .battery
        default: break
        }
        #endif
    }
}
