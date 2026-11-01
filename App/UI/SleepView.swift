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
    @Environment(\.dynamicTypeSize) private var typeSize

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
            .mainScreenChrome("Sleep")
            .refreshable { await load() }
            .task(id: model.strap.serial) { await load() }
        }
    }

    private func content(_ night: SnoopAPI.Night) -> some View {
        let w = night.metrics.window
        let p = night.metrics.physiology
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Button { step(1) } label: { Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44) }
                        .foregroundStyle(canStep(1) ? SnoopStyle.text : SnoopStyle.secondary.opacity(0.35))
                        .disabled(!canStep(1)).accessibilityLabel("Previous night")
                    Spacer(minLength: 4)
                    Text(nightLabel(night)).font(.subheadline).multilineTextAlignment(.center)
                    Spacer(minLength: 4)
                    Button { step(-1) } label: { Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44) }
                        .foregroundStyle(canStep(-1) ? SnoopStyle.text : SnoopStyle.secondary.opacity(0.35))
                        .disabled(!canStep(-1)).accessibilityLabel("Next night")
                }
                VStack(alignment: .leading, spacing: 6) {
                    SleepDuration(seconds: w.asleepS, size: 48)
                    Text("Time asleep").font(.subheadline).foregroundStyle(SnoopStyle.secondary)
                    Text("\(w.onset.formatted(date: .omitted, time: .shortened)) – \(w.offset.formatted(date: .omitted, time: .shortened)) · \(duration(w.timeInBedS)) in bed")
                        .font(.footnote).foregroundStyle(SnoopStyle.secondary)
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
                                    Label("Sleep details", systemImage: "chevron.right")
                                        .font(.caption).foregroundStyle(SnoopStyle.secondary)
                                }
                            }
                            .padding(.top, 8)
                        }
                        .buttonStyle(PressableCardStyle())
                        HStack {
                            Text(w.onset.formatted(date: .omitted, time: .shortened))
                            Spacer()
                            Text(w.offset.formatted(date: .omitted, time: .shortened))
                        }
                        .font(.caption2).foregroundStyle(SnoopStyle.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(SnoopStyle.surface, in: RoundedRectangle(cornerRadius: SnoopStyle.radius))

                if let st = night.metrics.stages, !night.stages.isEmpty {
                    let scored = max(st.lightS + st.deepS + st.remS, 1)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sleep stages").font(.headline)
                        StageRow(name: "REM", color: Hypnogram.color(.rem), seconds: st.remS, share: Double(st.remS) / Double(scored))
                        StageRow(name: "Deep", color: Hypnogram.color(.deep), seconds: st.deepS, share: Double(st.deepS) / Double(scored))
                        StageRow(name: "Light", color: Hypnogram.color(.light), seconds: st.lightS, share: Double(st.lightS) / Double(scored))
                        StageRow(name: "Awake", color: Hypnogram.color(.wake), seconds: st.wakeS, share: nil)
                        Text("Stages are estimates").font(.caption).foregroundStyle(SnoopStyle.secondary).padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(SnoopStyle.surface, in: RoundedRectangle(cornerRadius: SnoopStyle.radius))
                }

                LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    Stat("Efficiency", pct(w.efficiency), "Time in bed spent asleep")
                    Stat("Awake", duration(w.wasoS), "\(w.disturbances) disturbance\(w.disturbances == 1 ? "" : "s")")
                    Stat("Resting heart rate", p.restingHr.map { "\(Int($0.rounded()))" } ?? "—", "bpm")
                    Stat("HRV", p.hrvRmssdMs.map { "\(Int($0.rounded()))" } ?? "—", "ms · during sleep")
                    Stat("Breathing", p.respiratoryRate.map { String(format: "%.1f", $0) } ?? "—", "breaths / min")
                    Stat("SpO₂", p.spo2Pct.map { "\(Int($0.rounded())) %" } ?? "—", "During sleep")
                    Stat("Skin temperature", p.skinTempC.map { String(format: "%.1f °C", $0) } ?? "—", "Nightly average")
                    Stat("Data coverage", pct(Double(w.coverageS) / Double(max(w.timeInBedS, 1))), "Recorded during the night")
                }

                let awakenings = night.stages.filter { $0.stage == .wake && $0.start > w.onset && $0.end < w.offset }
                if !awakenings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Awake during the night").font(.caption.weight(.semibold)).foregroundStyle(SnoopStyle.secondary)
                        ForEach(Array(awakenings.enumerated()), id: \.offset) { _, seg in
                            HStack {
                                Text(seg.start.formatted(date: .omitted, time: .shortened))
                                Text("·").foregroundStyle(SnoopStyle.secondary)
                                Text(duration(Int(seg.end.timeIntervalSince(seg.start))))
                                    .foregroundStyle(SnoopStyle.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(SnoopStyle.surface, in: RoundedRectangle(cornerRadius: SnoopStyle.radius))
                }

                if w.coverageS < w.timeInBedS - 120 {
                    Label("\(duration(w.timeInBedS - w.coverageS)) of this night has no data, for example while the strap was off or charging. Those minutes are not counted as sleep.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(SnoopStyle.secondary)
                }

                if !night.metrics.naps.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Other sleep").font(.caption.weight(.semibold)).foregroundStyle(SnoopStyle.secondary)
                        ForEach(Array(night.metrics.naps.enumerated()), id: \.offset) { _, nap in
                            Text("\(nap.onset.formatted(date: .omitted, time: .shortened)) – \(nap.offset.formatted(date: .omitted, time: .shortened)) · \(duration(nap.asleepS))")
                                .font(.subheadline)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(SnoopStyle.surface, in: RoundedRectangle(cornerRadius: SnoopStyle.radius))
                }

                MetricInformation(title: "About sleep estimates", text: "Sleep is estimated from the strap’s rest signal and heart rate. Stages use motion, heart rate, HRV and breathing; they are estimates, and deep sleep is the least certain. HRV uses RMSSD across \(p.hrvWindows) windows; oxygen saturation uses \(p.spo2Windows) windows. Algorithm v\(night.algoVersion).")
            }
            .padding(.horizontal, SnoopStyle.gutter).padding(.bottom, 24)
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
            error = "Connect your WHOOP to load sleep."
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
            return "Set up your server connection in Profile & settings."
        }
        return "Wear your WHOOP overnight. Your sleep appears here after syncing in the morning."
    }

    private func nightLabel(_ night: SnoopAPI.Night) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: night.nightOf) else { return night.nightOf }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
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
        case .light: SnoopStyle.sleep.opacity(0.5)
        case .deep: SnoopStyle.sleep
        case .rem: SnoopStyle.sleep.opacity(0.78)
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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                Text(name).font(.subheadline.weight(.semibold))
                Text(hm(seconds) + (share.map { " · \(Int(($0 * 100).rounded()))%" } ?? ""))
                    .font(.subheadline).monospacedDigit()
                if let share { ProgressView(value: share).tint(color).accessibilityHidden(true) }
            }
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
        } else {
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
            Text(share.map { "\(Int(($0 * 100).rounded())) %" } ?? "").foregroundStyle(SnoopStyle.secondary).frame(width: 40, alignment: .trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        }
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
                RoundedRectangle(cornerRadius: 4).fill(SnoopStyle.sleep)
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
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(SnoopStyle.secondary)
            Text(value).font(.system(.title2, design: .default).weight(.semibold)).monospacedDigit()
            Text(caption).font(.caption2).foregroundStyle(SnoopStyle.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(SnoopStyle.surface, in: RoundedRectangle(cornerRadius: SnoopStyle.radius))
    }
}
