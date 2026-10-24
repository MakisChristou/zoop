import SwiftUI

/// Last night and recent nights as analysed by the server. Numbers come from
/// published methods over the strap's raw data; the screen says what is missing
/// rather than filling gaps with guesses.
struct SleepView: View {
    @EnvironmentObject private var model: AppModel
    @State private var nights: [SnoopAPI.Night] = []
    @State private var selected: SnoopAPI.Night?
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            Group {
                if let night = selected ?? nights.first {
                    content(night)
                } else if loading {
                    ProgressView()
                } else {
                    ContentUnavailableView {
                        Label("No nights yet", systemImage: "moon.zzz")
                    } description: {
                        Text(error ?? emptyDescription)
                    }
                }
            }
            .navigationTitle("Sleep")
            .toolbar {
                if nights.count > 1 {
                    Menu {
                        ForEach(nights) { night in
                            Button(nightLabel(night)) { selected = night }
                        }
                    } label: {
                        Image(systemName: "calendar")
                    }
                }
            }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func content(_ night: SnoopAPI.Night) -> some View {
        let w = night.metrics.window
        let p = night.metrics.physiology
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(nightLabel(night)).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(duration(w.asleepS)).font(.system(size: 56, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("asleep").font(.title3).foregroundStyle(.secondary)
                    }
                    Text("\(w.onset.formatted(date: .omitted, time: .shortened)) – \(w.offset.formatted(date: .omitted, time: .shortened)) · \(duration(w.timeInBedS)) in bed")
                        .font(.footnote).foregroundStyle(.secondary)
                    SleepBar(asleep: w.asleepS, awake: w.wasoS)
                        .frame(height: 14)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    Stat("Efficiency", pct(w.efficiency), "asleep ÷ in bed")
                    Stat("Awake", duration(w.wasoS), "\(w.disturbances) disturbance\(w.disturbances == 1 ? "" : "s")")
                    Stat("Resting HR", p.restingHr.map { "\(Int($0.rounded()))" } ?? "—", "bpm, lowest 5 min")
                    Stat("HRV", p.hrvRmssdMs.map { "\(Int($0.rounded()))" } ?? "—", "ms RMSSD, \(p.hrvWindows) windows")
                    Stat("Breathing", p.respiratoryRate.map { String(format: "%.1f", $0) } ?? "—", "breaths / min")
                    Stat("SpO₂", p.spo2Pct.map { "\(Int($0.rounded())) %" } ?? "—", "\(p.spo2Windows) windows")
                    Stat("Skin temp", p.skinTempC.map { String(format: "%.1f °C", $0) } ?? "—", "night mean")
                    Stat("Coverage", pct(Double(w.coverageS) / Double(max(w.timeInBedS, 1))), "data present")
                }

                if !night.metrics.naps.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Other sleep").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                        ForEach(Array(night.metrics.naps.enumerated()), id: \.offset) { _, nap in
                            Text("\(nap.onset.formatted(date: .omitted, time: .shortened)) – \(nap.offset.formatted(date: .omitted, time: .shortened)) · \(duration(nap.asleepS))")
                                .font(.subheadline)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
                }

                Text("Sleep window from the strap's own rest flag with heart-rate confirmation. Stages are not computed yet. Algorithm v\(night.algoVersion).")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding()
        }
    }

    private func load() async {
        guard !model.strap.serial.isEmpty || !nights.isEmpty else {
            error = "Waiting for the strap's serial number."
            return
        }
        loading = true
        defer { loading = false }
        do {
            nights = try await SnoopAPI.nights(deviceId: model.strap.serial)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private var emptyDescription: String {
        if !Settings.isConfigured {
            return "Add your server in Settings. Sleep is analysed there from the strap's overnight data."
        }
        return "Wear the strap overnight with snoop running in the background. The first analysed night appears here the next morning."
    }

    private func nightLabel(_ night: SnoopAPI.Night) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: night.nightOf) else { return night.nightOf }
        return "Night of " + date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    private func duration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60
        return h > 0 ? "\(h)h \(String(format: "%02d", m))m" : "\(m)m"
    }

    private func pct(_ value: Double) -> String {
        "\(Int((value * 100).rounded())) %"
    }
}

private struct SleepBar: View {
    let asleep: Int
    let awake: Int

    var body: some View {
        GeometryReader { geo in
            let total = max(asleep + awake, 1)
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 4).fill(.indigo)
                    .frame(width: geo.size.width * CGFloat(asleep) / CGFloat(total))
                if awake > 0 {
                    RoundedRectangle(cornerRadius: 4).fill(.orange.opacity(0.8))
                }
            }
        }
    }
}

private struct Stat: View {
    let title: String
    let value: String
    let caption: String

    init(_ title: String, _ value: String, _ caption: String) {
        self.title = title
        self.value = value
        self.caption = caption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            Text(value).font(.system(.title2, design: .rounded).weight(.semibold)).monospacedDigit()
            Text(caption).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }
}
