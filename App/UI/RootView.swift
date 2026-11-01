import SwiftUI

/// Five tabs. Each main screen carries the strap status and the profile button in its
/// own header; the device page lives behind both.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = Tab.today

    enum Tab: Hashable {
        case today, activity, sleep, trends, battery
    }

    var body: some View {
        TabView(selection: $selection) {
            TodayView(openSleep: { selection = .sleep }, openActivity: { selection = .activity })
                .tabItem { Label("Today", systemImage: "square.grid.2x2") }
                .tag(Tab.today)
            ActivityView()
                .tabItem { Label("Activity", systemImage: "figure.run") }
                .tag(Tab.activity)
            SleepView()
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.workouts.checkSoon(force: true) }
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
