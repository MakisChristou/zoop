import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section("Strap") {
                    LabeledContent("Status", value: statusText)
                    if !model.strap.serial.isEmpty {
                        LabeledContent("Serial", value: model.strap.serial)
                        LabeledContent("Model", value: model.strap.model)
                    }
                    if let battery = model.strap.batteryPercent {
                        LabeledContent("Battery", value: battery.formatted(.number.precision(.fractionLength(0))) + " %")
                    }
                }

                Section("Live") {
                    HStack(alignment: .firstTextBaseline) {
                        Text(model.strap.liveHeartRate.map(String.init) ?? "—")
                            .font(.system(size: 56, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("bpm").foregroundStyle(.secondary)
                    }
                    if let rmssd = rmssd(model.strap.liveRR) {
                        LabeledContent("RMSSD", value: rmssd.formatted(.number.precision(.fractionLength(0))) + " ms")
                    }
                    if let b = model.strap.lastBiometric {
                        LabeledContent("Band state", value: "\(b.bandState)")
                        if let skin = b.skinTemperatureC {
                            LabeledContent("Skin temp", value: skin.formatted(.number.precision(.fractionLength(2))) + " °C")
                        }
                        LabeledContent("Steps", value: "\(b.steps)")
                        if let spo2 = b.spo2Percent {
                            LabeledContent("SpO₂", value: "\(spo2) %")
                        }
                    }
                }

                Section("Sync") {
                    LabeledContent("Frames received", value: "\(model.strap.framesReceived)")
                    LabeledContent("Offload chunks", value: "\(model.strap.offloadChunks)")
                    if let range = model.strap.lastDataRange, let behind = range.pagesBehind {
                        LabeledContent("Pages behind", value: "\(behind)")
                    }
                    LabeledContent("Queued", value: "\(model.queued)")
                    LabeledContent("Uploaded", value: "\(model.uploadStats.accepted)")
                    if let error = model.uploadStats.lastError ?? model.queueError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                    Button("Upload now") { Task { await model.flush() } }
                        .disabled(!Settings.isConfigured)
                    Button("Request offload") { model.strap.requestOffload() }
                        .disabled(model.strap.state != .ready)
                }
            }
            .navigationTitle("snoop")
            .toolbar {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
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

    /// Root mean square of successive differences over the latest live R-R window.
    private func rmssd(_ rr: [UInt16]) -> Double? {
        guard rr.count >= 2 else { return nil }
        let diffs = zip(rr.dropFirst(), rr).map { Double($0) - Double($1) }
        return (diffs.map { $0 * $0 }.reduce(0, +) / Double(diffs.count)).squareRoot()
    }
}
