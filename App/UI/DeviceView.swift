import SnoopProtocol
import SwiftUI

/// The strap itself: link state, identity, history sync, and the raw latest record
/// for anyone curious what the strap is reporting. Pushed from the profile sheet.
struct DeviceView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section("Strap") {
                HStack {
                    Circle().fill(statusColor).frame(width: 10, height: 10)
                    Text(statusText)
                    Spacer()
                    if model.strap.framesReceived > 0, model.strap.state == .ready {
                        Text("receiving").foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                if !model.strap.serial.isEmpty {
                    LabeledContent("Model", value: "WHOOP \(model.strap.model)")
                    LabeledContent("Serial", value: model.strap.serial)
                }
                if let firmware = model.strap.firmware {
                    LabeledContent("Firmware", value: firmware)
                }
                if let battery = model.strap.batteryPercent {
                    LabeledContent("Battery", value: battery.formatted(.number.precision(.fractionLength(0))) + " %")
                }
            }

            Section {
                LabeledContent("Frames received", value: model.strap.framesReceived.formatted())
                LabeledContent("History chunks acknowledged", value: model.strap.offloadChunks.formatted())
                if let range = model.strap.lastDataRange, let behind = range.pagesBehind {
                    LabeledContent("Pages still on strap", value: behind.formatted())
                }
                Button {
                    model.strap.requestOffload()
                } label: {
                    Label("Fetch history now", systemImage: "arrow.down.circle")
                }
                .disabled(model.strap.state != .ready)
            } header: {
                Text("Sync")
            } footer: {
                Text("The strap keeps its own history and hands it over in chunks whenever the app is connected.")
            }

            Section("Latest record") {
                if let b = model.strap.lastBiometric {
                    LabeledContent("Heart rate", value: "\(b.heartRate) bpm")
                    LabeledContent("Strap says", value: bandStateText(b.bandState))
                    LabeledContent("Step counter", value: b.steps.formatted())
                    LabeledContent("R-R intervals", value: b.rrMilliseconds.isEmpty ? "none" : b.rrMilliseconds.map(String.init).joined(separator: ", ") + " ms")
                    if let skin = b.skinTemperatureC {
                        LabeledContent("Skin temp", value: skin.formatted(.number.precision(.fractionLength(2))) + " °C")
                    }
                    if let spo2 = b.spo2Percent {
                        LabeledContent("SpO₂", value: "\(spo2) %")
                    }
                    LabeledContent("Recorded", value: Date(timeIntervalSince1970: TimeInterval(b.header.unixSeconds)).formatted(date: .omitted, time: .standard))
                } else {
                    Text("No records yet.").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("My device")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusColor: Color {
        switch model.strap.state {
        case .ready: .green
        case .connected, .connecting, .scanning: .orange
        case .bluetoothOff, .failed: .red
        }
    }

    private var statusText: String {
        switch model.strap.state {
        case .bluetoothOff: "Bluetooth off"
        case .scanning: "Looking for strap…"
        case .connecting: "Connecting…"
        case .connected: "Connected, handshaking…"
        case .ready: "Ready"
        case let .failed(reason): "Failed: \(reason)"
        }
    }

    private func bandStateText(_ state: BandState) -> String {
        switch state {
        case .wake: "awake"
        case .still: "still"
        case .sleep: "asleep"
        case .up: "up"
        }
    }
}
