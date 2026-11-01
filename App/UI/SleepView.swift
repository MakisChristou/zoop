import SwiftUI

struct SleepView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selected: SnoopAPI.Night?
    @State private var selectedDay = Date()
    @State private var editor: SleepEditorMode?
    @State private var resetTarget: SnoopAPI.SleepSession?
    @State private var error: String?
    @State private var loading = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var timezone: String { model.sleep.items.first?.timezone ?? TimeZone.current.identifier }
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: timezone) ?? .current; return c }
    private var key: String { SnoopAPI.SleepSession.day(selectedDay, timezone: timezone) }
    private var rows: [SnoopAPI.SleepSession] { model.sleep.items.filter { $0.day == key }.sorted { $0.startTs < $1.startTs } }
    private var main: SnoopAPI.SleepSession? { rows.first { $0.kind == "main" } }
    private var dayTitle: String { let f = DateFormatter(); f.timeZone = calendar.timeZone; f.dateFormat = "EEE d MMM"; return f.string(from: selectedDay) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DateNavigation(title: dayTitle, canGoBack: true, canGoForward: key < SnoopAPI.SleepSession.day(Date(), timezone: timezone), previousLabel: "Previous day", nextLabel: "Next day", previous: { step(-1) }, next: { step(1) }, reset: { editor = .init(action: "add", day: selectedDay) }, canReset: true, resetTitle: "Add sleep", resetIcon: "plus", resetAccessibility: "Add sleep")
                    if let main, let night = main.night { content(night, record: main) }
                    else if loading { ProgressView().frame(maxWidth: .infinity).padding(40) }
                    else {
                        ContentUnavailableView {
                            Label(main != nil ? "Updating sleep" : "No main sleep", systemImage: "moon.zzz")
                        } description: { Text(error ?? "Add missed sleep from your recorded data.") }
                        actions: { Button("Add sleep") { editor = .init(action: "add", day: selectedDay) } }
                    }
                    if !rows.filter({ $0.kind == "nap" }).isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Naps").font(.headline)
                            ForEach(rows.filter { $0.kind == "nap" }) { row in
                                NavigationLink { SleepSessionDetailView(initial: row) } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(row.startTs.formatted(date: .omitted, time: .shortened) + " – " + row.endTs.formatted(date: .omitted, time: .shortened))
                                            if let data = row.sleep { Text(duration(data.window.asleepS)).font(.subheadline).foregroundStyle(SnoopStyle.secondary) }
                                            if row.metricsPending { Text("Updating sleep").font(.caption).foregroundStyle(SnoopStyle.secondary) }
                                        }
                                        Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(SnoopStyle.secondary)
                                    }.frame(minHeight: 44).padding().background(SnoopStyle.surface, in: RoundedRectangle(cornerRadius: SnoopStyle.radius))
                                }.buttonStyle(PressableCardStyle())
                            }
                        }
                    }
                    if main != nil, let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    NavigationLink("Removed sleep") { RemovedSleepView() }.font(.footnote).frame(minHeight: 44)
                }.padding(.horizontal, SnoopStyle.gutter).padding(.bottom, 24)
            }
            .navigationTitle("Sleep").mainScreenChrome("Sleep")
            .safeAreaInset(edge: .bottom, spacing: 0) { SleepNotice() }
            .refreshable { await load() }
            .task(id: model.strap.serial) { if let selected { selectedDay = selected.endTs }; await load() }
            .onChange(of: selected?.id) { _, _ in if let selected { selectedDay = selected.endTs } }
            .onChange(of: model.analysisRevision) { _, _ in Task { await load() } }
        }
        .sheet(item: $editor) { SleepEditorView(mode: $0) }
        .sheet(item: $resetTarget) { row in NavigationStack { AnalysisResetView(domain: "sleep", targetId: row.id, isSheet: true) }.presentationBackground(SnoopStyle.background) }
    }
    private func step(_ delta: Int) { selected = nil; selectedDay = calendar.date(byAdding: .day, value: delta, to: selectedDay) ?? selectedDay }
    private func load() async {
        guard !model.strap.serial.isEmpty else { error = "Connect your WHOOP to load sleep."; return }
        loading = true; defer { loading = false }
        do { try await model.sleep.reload(device: model.strap.serial); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func content(_ night: SnoopAPI.Night, record: SnoopAPI.SleepSession) -> some View {
        let w = night.metrics.window
        let p = night.metrics.physiology
        return VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        SleepDuration(seconds: w.asleepS, size: 48)
                        Spacer()
                        Menu {
                            Button("Edit sleep", systemImage: "pencil") { editor = .init(action: "edit", record: record) }
                            Button("Merge sleep", systemImage: "arrow.triangle.merge") { editor = .init(action: "merge", record: record) }
                            if let id = record.lastEdit { Button("Undo last change", systemImage: "arrow.uturn.backward") { Task { do { try await model.sleep.undo(device: model.strap.serial, id: id) } catch { self.error = error.localizedDescription } } } }
                            Button("Reset to automatic", systemImage: "arrow.counterclockwise") { resetTarget = record }
                            NavigationLink("Sleep details") { SleepSessionDetailView(initial: record) }
                        } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Sleep options")
                    }
                    if record.metricsPending { Label("Updating sleep", systemImage: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(SnoopStyle.secondary) }
                    else if record.edited { Text(record.autoDetected ? "Edited" : "Added").font(.caption).foregroundStyle(SnoopStyle.secondary) }
                    Text("Time asleep").font(.subheadline).foregroundStyle(SnoopStyle.secondary)
                    Text("\(w.onset.formatted(date: .omitted, time: .shortened)) – \(w.offset.formatted(date: .omitted, time: .shortened)) · \(duration(w.timeInBedS)) sleep period")
                        .font(.footnote).foregroundStyle(SnoopStyle.secondary)
                    if night.stages.isEmpty {
                        NavigationLink { SleepSessionDetailView(initial: record) } label: {
                            Label("Sleep details", systemImage: "chevron.right").font(.footnote).frame(minHeight: 44)
                        }
                    } else {
                        NavigationLink {
                            SleepSessionDetailView(initial: record)
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
                    Stat("Efficiency", record.sleep?.efficiency.map(pct) ?? "—", "Sleep period spent asleep")
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

                MetricInformation(title: "About sleep estimates", text: "Sleep is estimated from the strap’s rest signal and heart rate. Stages use motion, heart rate, HRV and breathing; they are estimates, and deep sleep is the least certain. HRV uses RMSSD across \(p.hrvWindows) windows; oxygen saturation uses \(p.spo2Windows) windows. Algorithm v\(night.algoVersion).")
            }
            .padding(.bottom, 4)
    }

    private func duration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60
        return h > 0 ? "\(h)h \(String(format: "%02d", m))m" : "\(m)m"
    }
    private func pct(_ value: Double) -> String { "\(Int((value * 100).rounded())) %" }
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
