import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
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

                Section("Server") {
                    HStack {
                        Circle().fill(uploadColor).frame(width: 10, height: 10)
                        Text(uploadText)
                        Spacer()
                        if model.isUploading { ProgressView() }
                    }
                    LabeledContent("Waiting to upload", value: "\(model.queued) frames")
                    LabeledContent("Accepted by server", value: "\(model.uploadStats.accepted)")
                    if model.uploadStats.duplicates > 0 || model.uploadStats.rejected > 0 {
                        LabeledContent("Duplicates / rejected", value: "\(model.uploadStats.duplicates) / \(model.uploadStats.rejected)")
                    }
                    if let error = model.uploadStats.lastError ?? model.queueError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    } else if let blocker = model.uploadBlocker {
                        Text(blocker).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button {
                        Task { await model.flush() }
                    } label: {
                        Label(model.isUploading ? "Uploading…" : "Upload now", systemImage: "icloud.and.arrow.up")
                    }
                    .disabled(model.uploadBlocker != nil || model.isUploading)
                }

                Section("Strap sync") {
                    LabeledContent("Frames received", value: "\(model.strap.framesReceived)")
                    LabeledContent("History chunks acknowledged", value: "\(model.strap.offloadChunks)")
                    if let range = model.strap.lastDataRange, let behind = range.pagesBehind {
                        LabeledContent("Pages still on strap", value: "\(behind)")
                    }
                    Button {
                        model.strap.requestOffload()
                    } label: {
                        Label("Fetch history now", systemImage: "arrow.down.circle")
                    }
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

    private var statusColor: Color {
        switch model.strap.state {
        case .ready: .green
        case .connected, .connecting, .scanning: .orange
        case .bluetoothOff, .failed: .red
        }
    }

    private var uploadColor: Color {
        if model.uploadStats.lastError != nil { return .red }
        if model.uploadStats.lastSuccess != nil { return .green }
        return .gray
    }

    private var uploadText: String {
        if model.isUploading { return "Uploading…" }
        if let error = model.uploadStats.lastError { return "Upload failed: \(error)" }
        if let at = model.uploadStats.lastSuccess {
            let age = Int(Date().timeIntervalSince(at))
            let when = age < 60 ? "\(age) s ago" : "\(age / 60) min ago"
            return "Last upload \(when): \(model.lastBatchAccepted) frames accepted"
        }
        return Settings.isConfigured ? "No upload yet" : "Not configured"
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
