import SwiftUI

struct ConnectionStatusLabel: View {
    @EnvironmentObject private var model: AppModel
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: model.strap.state == .ready ? "battery.100percent" : "sensor.tag.radiowaves.forward")
                if compact {
                    EmptyView()
                } else if model.strap.state == .ready {
                    Text(model.battery.state.percent.map { "\(Int($0.rounded(.down)))%" } ?? "—").monospacedDigit()
                } else { Text(status) }
            }
            .font(.caption).foregroundStyle(SnoopStyle.secondary)
            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("WHOOP, \(status)")
        .accessibilityValue(model.strap.state == .ready ? model.battery.state.percent.map { "\(Int($0.rounded(.down))) percent battery" } ?? "" : "")
        .accessibilityHint("Opens device settings")
        .accessibilityShowsLargeContentViewer()
    }

    private var status: String {
        switch model.strap.state {
        case .ready: "Connected"
        case .connected, .connecting, .scanning: "Connecting…"
        case .bluetoothOff: "Bluetooth off"
        case .failed: "Disconnected"
        }
    }
}
