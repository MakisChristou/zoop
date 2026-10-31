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
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { step(1) } label: { Image(systemName: "chevron.left") }
                            .disabled(!canStep(1))
                        Button { step(-1) } label: { Image(systemName: "chevron.right") }
                            .disabled(!canStep(-1))
                    }
                }
            }
            .mainScreenChrome()
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
                    if night.stages.isEmpty {
                        SleepBar(asleep: w.asleepS, awake: w.wasoS)
                            .frame(height: 14)
                            .padding(.top, 4)
                    } else {
                        NavigationLink {
                            SleepDetailView(night: night)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Hypnogram(segments: night.stages, onset: w.onset, offset: w.offset)
                                    .frame(height: 96)
                                HStack {
                                    Spacer()
                                    Label("Inspect night", systemImage: "chevron.right")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.top, 8)
                        }
                        .buttonStyle(.plain)
                        HStack {
                            Text(w.onset.formatted(date: .omitted, time: .shortened))
                            Spacer()
                            Text(w.offset.formatted(date: .omitted, time: .shortened))
                        }
                        .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))

                if let st = night.metrics.stages, !night.stages.isEmpty {
                    let scored = max(st.lightS + st.deepS + st.remS, 1)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Stages").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                        StageRow(name: "REM", color: Hypnogram.color(.rem), seconds: st.remS, share: Double(st.remS) / Double(scored))
                        StageRow(name: "Deep", color: Hypnogram.color(.deep), seconds: st.deepS, share: Double(st.deepS) / Double(scored))
                        StageRow(name: "Light", color: Hypnogram.color(.light), seconds: st.lightS, share: Double(st.lightS) / Double(scored))
                        StageRow(name: "Awake", color: Hypnogram.color(.wake), seconds: st.wakeS, share: nil)
                        if let rem = st.remLatencyS {
                            Text("First REM after \(duration(rem)). Deep-sleep minutes are the least certain of these figures.")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
                }

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

                let awakenings = night.stages.filter { $0.stage == .wake && $0.start > w.onset && $0.end < w.offset }
                if !awakenings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Awake during the night").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                        ForEach(Array(awakenings.enumerated()), id: \.offset) { _, seg in
                            HStack {
                                Text(seg.start.formatted(date: .omitted, time: .shortened))
                                Text("·").foregroundStyle(.tertiary)
                                Text(duration(Int(seg.end.timeIntervalSince(seg.start))))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
                }

                if w.coverageS < w.timeInBedS - 120 {
                    Label("\(duration(w.timeInBedS - w.coverageS)) of this night has no data, for example while the strap was off or charging. Those minutes are not counted as sleep.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.secondary)
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

                Text("Sleep window from the strap's own rest flag with heart-rate confirmation. Stages from motion, heart rate, HRV and breathing, using published wrist-device methods; about 70 % epoch agreement is the state of the art without EEG. Algorithm v\(night.algoVersion).")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding()
        }
    }

    /// Nights are newest first; +1 steps back in time.
    private func currentIndex() -> Int {
        nights.firstIndex { $0.id == (selected ?? nights.first)?.id } ?? 0
    }

    private func canStep(_ delta: Int) -> Bool {
        let i = currentIndex() + delta
        return i >= 0 && i < nights.count
    }

    private func step(_ delta: Int) {
        guard canStep(delta) else { return }
        selected = nights[currentIndex() + delta]
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

struct Hypnogram: View {
    let segments: [SnoopAPI.Night.Segment]
    let onset: Date
    let offset: Date

    static func color(_ stage: SnoopAPI.Night.Stage) -> Color {
        switch stage {
        case .wake: .orange
        case .light: .indigo.opacity(0.55)
        case .deep: .indigo
        case .rem: .teal
        }
    }

    private static func level(_ stage: SnoopAPI.Night.Stage) -> CGFloat {
        switch stage {
        case .wake: 0
        case .rem: 1
        case .light: 2
        case .deep: 3
        }
    }

    var body: some View {
        GeometryReader { geo in
            let total = max(offset.timeIntervalSince(onset), 1)
            let rowHeight = geo.size.height / 4
            ZStack(alignment: .topLeading) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    let x = CGFloat(seg.start.timeIntervalSince(onset) / total) * geo.size.width
                    let w = max(CGFloat(seg.end.timeIntervalSince(seg.start) / total) * geo.size.width, 1)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Self.color(seg.stage))
                        .frame(width: w, height: rowHeight - 3)
                        .offset(x: x, y: Self.level(seg.stage) * rowHeight)
                }
            }
        }
    }
}

private struct StageRow: View {
    let name: String
    let color: Color
    let seconds: Int
    let share: Double?

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(name).frame(width: 52, alignment: .leading)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(min(share ?? 0, 1)), height: 8)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            Text(hm(seconds)).monospacedDigit().frame(width: 62, alignment: .trailing)
            Text(share.map { "\(Int(($0 * 100).rounded())) %" } ?? "").foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
        }
        .font(.subheadline)
    }

    private func hm(_ s: Int) -> String {
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(String(format: "%02d", m))m" : "\(m)m"
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
