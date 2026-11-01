import SwiftUI

/// Strap status for the navigation bar: a dot and a word, battery when connected.
/// Tapping opens the device page. Sits in the header of every main screen instead of
/// floating over them.
struct ConnectionStatusLabel: View {
    @EnvironmentObject private var model: AppModel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(text).font(.footnote.weight(.medium)).foregroundStyle(.primary)
                if let battery = model.battery.state.percent, model.strap.state == .ready {
                    Text("\(Int(battery.rounded(.down))) %")
                        .font(.footnote).foregroundStyle(BatteryColors.level(battery)).monospacedDigit()
                }
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens the device page")
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

    private var accessibilityText: String {
        var parts = ["Strap \(text.lowercased())"]
        if let battery = model.battery.state.percent, model.strap.state == .ready {
            parts.append("battery \(Int(battery.rounded(.down))) percent")
        }
        return parts.joined(separator: ", ")
    }
}
