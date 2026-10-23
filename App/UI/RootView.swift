import SwiftUI

/// Tab shell with the connection pill pinned above every tab.
struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "square.grid.2x2") }
            SleepView()
                .tabItem { Label("Sleep", systemImage: "moon.fill") }
            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.line.uptrend.xyaxis") }
            DeviceView()
                .tabItem { Label("Device", systemImage: "sensor.tag.radiowaves.forward") }
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
            if let battery = model.strap.batteryPercent, model.strap.state == .ready {
                Text("·").foregroundStyle(.secondary)
                Label(battery.formatted(.number.precision(.fractionLength(0))) + " %", systemImage: batteryIcon(battery))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
