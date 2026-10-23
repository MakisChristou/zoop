import SnoopProtocol
import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @State private var now = Date()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heartRateHero
                    tiles
                    if model.strap.state != .ready {
                        Text(hint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .navigationBarTitleDisplayMode(.large)
        }
        .onReceive(clock) { now = $0 }
        .onAppear { model.strap.setRealtimeHeartRate(true) }
        .onDisappear { model.strap.setRealtimeHeartRate(false) }
        .onChange(of: model.strap.state) { _, state in
            if state == .ready { model.strap.setRealtimeHeartRate(true) }
        }
    }

    private var heartRateHero: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Heart rate", systemImage: "heart.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(model.strap.smoothedHeartRate.map(String.init) ?? "—")
                    .font(.system(size: 72, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("bpm").font(.title3).foregroundStyle(.secondary)
            }
            Text(freshness)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var tiles: some View {
        let b = model.strap.lastBiometric
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            Tile(title: "HRV", value: rmssdText, unit: "ms", caption: "RMSSD, last 10 s")
            Tile(title: "Skin temp", value: b?.skinTemperatureC.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—", unit: "°C", caption: "latest record")
            Tile(title: "Steps", value: b.map { "\($0.steps)" } ?? "—", unit: "", caption: "today, from the strap")
            Tile(title: "Strap says", value: b.map { bandStateText($0.bandState) } ?? "—", unit: "", caption: "its own rest flag")
        }
        .padding(.horizontal)
    }

    private var freshness: String {
        guard let at = model.strap.liveUpdatedAt else { return "Waiting for the first reading" }
        let age = Int(now.timeIntervalSince(at))
        if model.strap.realtimeStreaming, age < 5 { return "Live" }
        return age < 60 ? "\(age) s ago" : "\(age / 60) min ago"
    }

    private var hint: String {
        switch model.strap.state {
        case .scanning: "Make sure the strap is on your wrist, nearby, and the official WHOOP app is fully closed."
        case .bluetoothOff: "Turn Bluetooth on to connect to the strap."
        case .failed: "Connection failed. The Device tab has details."
        default: "Connecting to the strap…"
        }
    }

    private var rmssdText: String {
        let rr = model.strap.liveRR.map(Double.init)
        guard rr.count >= 2 else { return "—" }
        let diffs = zip(rr.dropFirst(), rr).map { $0 - $1 }
        let value = (diffs.map { $0 * $0 }.reduce(0, +) / Double(diffs.count)).squareRoot()
        return value.formatted(.number.precision(.fractionLength(0)))
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

private struct Tile: View {
    let title: String
    let value: String
    let unit: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(.title, design: .rounded).weight(.semibold)).monospacedDigit()
                if !unit.isEmpty { Text(unit).font(.subheadline).foregroundStyle(.secondary) }
            }
            Text(caption).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }
}
