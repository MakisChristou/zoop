import SwiftUI

/// Tab shell with the connection pill pinned above every tab.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tabItem { Label("Today", systemImage: "square.grid.2x2") }
                .tag(0)
            ActivityView()
                .tabItem { Label("Activity", systemImage: "figure.run") }
                .tag(1)
            SleepView()
                .tabItem { Label("Sleep", systemImage: "moon.fill") }
                .tag(2)
            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(3)
            BatteryView()
                .tabItem { Label("Battery", systemImage: "battery.100percent") }
                .tag(4)
            DeviceView()
                .tabItem { Label("Device", systemImage: "sensor.tag.radiowaves.forward") }
                .tag(5)
        }
        .task { await model.battery.requestNotificationsIfNeeded() }
        .onChange(of: model.battery.openBattery, initial: true) { _, open in
            if open { selection = 4; model.battery.openBattery = false }
        }
        .onChange(of: model.battery.openWorkout, initial: true) { _, id in
            if id != nil { selection = 1 }
        }
        .overlay(alignment: .top) {
            ConnectionPill()
                .padding(.top, 4)
        }
    }
}

/// Three-state strap status with battery, visible on every tab.
struct ConnectionPill: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.footnote.weight(.medium))
            if let battery = model.battery.state.percent, model.strap.state == .ready {
                Text("·").foregroundStyle(.secondary)
                Label("\(Int(battery.rounded(.down))) %" + batteryAge, systemImage: model.battery.state.chargingStatus(at: Date()) == true && model.battery.state.isFresh(at: Date()) ? "battery.100percent.bolt" : batteryIcon(battery))
                    .font(.footnote)
                    .foregroundStyle(BatteryColors.level(battery))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var color: Color {
        switch model.strap.state {
        case .ready: .green
        case .connected, .connecting, .scanning: .orange
        case .bluetoothOff, .failed: .red
        }
    }

    private var text: String {
        switch model.strap.state {
        case .ready: "Connected"
        case .connected: "Handshaking"
        case .connecting: "Connecting"
        case .scanning: "Looking for strap"
        case .bluetoothOff: "Bluetooth off"
        case .failed: "Disconnected"
        }
    }

    private var batteryAge: String {
        guard let at = model.battery.state.levelAt else { return "" }
        let minutes = Int(Date().timeIntervalSince(at) / 60)
        return minutes < 2 ? "" : " (\(minutes) min ago)"
    }

    private func batteryIcon(_ percent: Double) -> String {
        switch percent {
        case ..<15: "battery.0percent"
        case ..<40: "battery.25percent"
        case ..<65: "battery.50percent"
        case ..<90: "battery.75percent"
        default: "battery.100percent"
        }
    }
}
