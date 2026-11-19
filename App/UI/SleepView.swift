import SwiftUI

struct SleepView: View {
    @Environment(AppModel.self) private var model
    @Binding var selected: ZoopAPI.Night?
    @State private var selectedDay = Date()
    @State private var editor: SleepEditorMode?
    @State private var resetTarget: ZoopAPI.SleepSession?
    @State private var error: String?
    @State private var loading = false
    @State private var loadID = UUID()
    @Environment(\.dynamicTypeSize) private var typeSize
    private var timezone: String { model.sleep.items.first?.timezone ?? TimeZone.current.identifier }
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: timezone) ?? .current; return c }
    private var key: String { ZoopAPI.SleepSession.day(selectedDay, timezone: timezone) }
    private var rows: [ZoopAPI.SleepSession] { model.sleep.items.filter { $0.day == key }.sorted { $0.startTs < $1.startTs } }
    private var main: ZoopAPI.SleepSession? { rows.first { $0.kind == "main" } }
    private var dayTitle: String { let f = DateFormatter(); f.timeZone = calendar.timeZone; f.dateFormat = "EEE d MMM"; return f.string(from: selectedDay) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DateNavigation(title: dayTitle, canGoBack: true, canGoForward: key < ZoopAPI.SleepSession.day(Date(), timezone: timezone), previousLabel: "Previous day", nextLabel: "Next day", previous: { step(-1) }, next: { step(1) })
                    if let main, let night = main.night { content(night, record: main) }
                    else if loading { ProgressView().frame(maxWidth: .infinity).padding(40) }
                    else {
                        ContentUnavailableView {
                            Label(main != nil ? "Updating sleep" : "No main sleep", systemImage: "moon.zzz")
                        } description: {
                            Text(error ?? (main != nil ? "Your sleep is being updated." : "Detected sleep appears here after syncing."))
                        }
                    }
                    if !rows.filter({ $0.kind == "nap" }).isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Naps").font(ZoopType.headline)
                            ForEach(rows.filter { $0.kind == "nap" }) { row in
                                NavigationLink { SleepSessionDetailView(initial: row) } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(row.startTs.formatted(date: .omitted, time: .shortened) + " – " + row.endTs.formatted(date: .omitted, time: .shortened))
                                            if let data = row.sleep { Text(duration(data.window.asleepS)).font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary) }
                                            if row.metricsPending { Text("Updating sleep").font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary) }
                                        }
                                        Spacer(); Image(systemName: "chevron.right").font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                                    }.frame(minHeight: 44).padding().background(ZoopStyle.surface, in: RoundedRectangle(cornerRadius: ZoopStyle.radius))
                                }.buttonStyle(PressableCardStyle()).accessibilityIdentifier("napSession-\(row.id)")
                            }
                        }
                    }
                    if main != nil, let error { Text(error).font(ZoopType.footnote).foregroundStyle(.red) }
                    NavigationLink("Removed sleep") { RemovedSleepView() }.font(ZoopType.footnote).frame(minHeight: 44)
                }.padding(.horizontal, ZoopStyle.gutter).padding(.bottom, 24)
            }
            .navigationTitle("Sleep").mainScreenChrome("Sleep")
            .safeAreaInset(edge: .bottom, spacing: 0) { SleepNotice() }
            .refreshable { await load() }
            .task(id: model.strap.serial) { if let selected { selectedDay = selected.endTs }; await load() }
            .onChange(of: selected?.id) { _, _ in if let selected { selectedDay = selected.endTs } }
            .onChange(of: model.analysisRevision) { _, _ in Task { await load() } }
        }
        .sheet(item: $editor) { SleepEditorView(mode: $0) }
        .sheet(item: $resetTarget) { row in NavigationStack { AnalysisResetView(domain: "sleep", targetId: row.id, isSheet: true) }.presentationBackground(ZoopStyle.background) }
    }
    private func step(_ delta: Int) { selected = nil; selectedDay = calendar.date(byAdding: .day, value: delta, to: selectedDay) ?? selectedDay }
    private func load() async {
        guard !model.strap.serial.isEmpty else { error = "Connect your WHOOP to load sleep."; return }
        let request = UUID(); loadID = request
        loading = true; error = nil
        defer { if loadID == request { loading = false } }
        do {
            try await model.sleep.reload(device: model.strap.serial)
        } catch {
            // Tab changes and superseded refreshes cancel reads intentionally.
            guard !Task.isCancelled, loadID == request, !(error is CancellationError),
                  (error as? URLError)?.code != .cancelled else { return }
            self.error = error.localizedDescription
        }
    }
    private func content(_ night: ZoopAPI.Night, record: ZoopAPI.SleepSession) -> some View {
        let w = night.metrics.window
        let p = night.metrics.physiology
        let deltas = SleepMetricDelta.all(record: record, history: model.sleep.items, calendar: calendar)
        return VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        SleepDuration(seconds: w.asleepS, size: 20)
                        Spacer()
                        Menu {
                            Button("Edit sleep", systemImage: "pencil") { editor = .edit(record) }
                            Button("Merge sleep", systemImage: "arrow.triangle.merge") { editor = .merge(record) }
                            if let id = record.lastEdit { Button("Undo last change", systemImage: "arrow.uturn.backward") { Task { do { try await model.sleep.undo(device: model.strap.serial, id: id) } catch { self.error = error.localizedDescription } } } }
                            Button("Reset to automatic", systemImage: "arrow.counterclockwise") { resetTarget = record }
                            NavigationLink("Sleep details") { SleepSessionDetailView(initial: record) }
                        } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Sleep options")
                    }
                    if record.metricsPending { Label("Updating sleep", systemImage: "arrow.triangle.2.circlepath").font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary) }
                    else if record.edited { Text(record.autoDetected ? "Edited" : "Added").font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary) }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Time asleep").font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary)
                        Spacer()
                        if let delta = deltas[.asleep] { SleepDeltaLabel(delta: delta, id: "Time asleep") }
                    }
                    if night.stages.isEmpty {
                        Text("\(w.onset.formatted(date: .omitted, time: .shortened)) – \(w.offset.formatted(date: .omitted, time: .shortened))")
                            .font(ZoopType.footnote).foregroundStyle(ZoopStyle.secondary)
                        NavigationLink { SleepSessionDetailView(initial: record) } label: {
                            Label("Sleep details", systemImage: "chevron.right").font(ZoopType.footnote).frame(minHeight: 44)
                        }
                    } else {
                        NavigationLink {
                            SleepSessionDetailView(initial: record)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Hypnogram(segments: night.stages, onset: w.onset, offset: w.offset)
                                    .frame(height: 140).zoopCard(padding: 12)
                                HStack {
                                    Spacer()
                                    Label("Sleep details", systemImage: "chevron.right")
                                        .font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                                }
                            }
                            .padding(.top, 8)
                        }
                        .buttonStyle(PressableCardStyle()).accessibilityIdentifier("sleepTimelineDetails")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)

                if let st = night.metrics.stages, !night.stages.isEmpty {
                    let scored = max(st.lightS + st.deepS + st.remS, 1)
                    VStack(alignment: .leading, spacing: 20) {
                        SleepSectionHeader(title: "Sleep stages", comparison: "vs avg")
                        GeometryReader { geo in
                            let total = CGFloat(max(scored + st.wakeS, 1))
                            HStack(spacing: 2) {
                                Rectangle().fill(Hypnogram.color(.deep)).frame(width: max(0, (geo.size.width - 6) * CGFloat(st.deepS) / total))
                                Rectangle().fill(Hypnogram.color(.rem)).frame(width: max(0, (geo.size.width - 6) * CGFloat(st.remS) / total))
                                Rectangle().fill(Hypnogram.color(.light)).frame(width: max(0, (geo.size.width - 6) * CGFloat(st.lightS) / total))
                                Rectangle().fill(Hypnogram.color(.wake))
                            }.clipShape(Capsule())
                        }.frame(height: 12).accessibilityHidden(true)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: typeSize.isAccessibilitySize ? 1 : 2), alignment: .leading, spacing: 20) {
                            StageRow(name: "Deep", color: Hypnogram.color(.deep), seconds: st.deepS, share: Double(st.deepS) / Double(scored), delta: deltas[.deep])
                            StageRow(name: "REM", color: Hypnogram.color(.rem), seconds: st.remS, share: Double(st.remS) / Double(scored), delta: deltas[.rem])
                            StageRow(name: "Light", color: Hypnogram.color(.light), seconds: st.lightS, share: Double(st.lightS) / Double(scored), delta: deltas[.light])
                            // Stage-scored wake differs from rest-signal WASO; do not attach its delta here.
                            StageRow(name: "Awake", color: Hypnogram.color(.wake), seconds: st.wakeS, share: nil, delta: nil)
                        }
                        Divider().overlay(ZoopStyle.separator)
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Fell asleep").font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                                Text(w.onset.formatted(date: .omitted, time: .shortened)).font(ZoopType.title)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                Text("Woke up").font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                                Text(w.offset.formatted(date: .omitted, time: .shortened)).font(ZoopType.title)
                            }
                        }
                    }.zoopCard()
                }

                VStack(alignment: .leading, spacing: 12) {
                    SleepSectionHeader(title: "Nightly metrics", comparison: "vs your average")
                    LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                        Stat("Efficiency", record.sleep?.efficiency.map { "\(Int(($0 * 100).rounded()))" } ?? "—", unit: "%", delta: deltas[.efficiency])
                        Stat("Awake", duration(w.wasoS), delta: deltas[.awake])
                        Stat("Resting heart rate", p.restingHr.map { "\(Int($0.rounded()))" } ?? "—", unit: "bpm", delta: deltas[.restingHR])
                        Stat("HRV", p.hrvRmssdMs.map { "\(Int($0.rounded()))" } ?? "—", unit: "ms", delta: deltas[.hrv])
                        Stat("Breathing", p.respiratoryRate.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—", unit: "/min", delta: deltas[.breathing])
                        Stat("SpO₂", p.spo2Pct.map { "\(Int($0.rounded()))" } ?? "—", unit: "%", delta: deltas[.oxygen])
                        Stat("Skin temperature", p.skinTempC.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—", unit: "°C", delta: deltas[.temperature])
                        Stat("Disturbances", "\(w.disturbances)", delta: deltas[.disturbances])
                    }.zoopCard(padding: 4)
                }

                let awakenings = night.stages.filter { $0.stage == .wake && $0.start > w.onset && $0.end < w.offset }
                if !awakenings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Awake during the night").font(ZoopType.font(size: 12, weight: .semibold, relativeTo: .caption)).foregroundStyle(ZoopStyle.secondary)
                        ForEach(Array(awakenings.enumerated()), id: \.offset) { _, seg in
                            HStack {
                                Text(seg.start.formatted(date: .omitted, time: .shortened))
                                Text("·").foregroundStyle(ZoopStyle.secondary)
                                Text(duration(Int(seg.end.timeIntervalSince(seg.start))))
                                    .foregroundStyle(ZoopStyle.secondary)
                            }
                            .font(ZoopType.subheadline)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(ZoopStyle.surface, in: RoundedRectangle(cornerRadius: ZoopStyle.radius))
                }

                if w.coverageS < w.timeInBedS - 120 {
                    Label("\(duration(w.timeInBedS - w.coverageS)) of this night has no data, for example while the strap was off or charging. Those minutes are not counted as sleep.", systemImage: "exclamationmark.triangle")
                        .font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                }

                HStack {
                    Text("Recording coverage")
                    Spacer()
                    Text(pct(Double(w.coverageS) / Double(max(w.timeInBedS, 1)))).monospacedDigit()
                }.font(ZoopType.footnote).foregroundStyle(ZoopStyle.secondary)

                MetricInformation(title: "About sleep estimates", text: "Sleep is estimated from the strap’s rest signal and heart rate. Stages use motion, heart rate, HRV and breathing; they are estimates, and deep sleep is the least certain. The Awake total uses the strap’s rest signal; chart awakenings are separate stage estimates. HRV uses RMSSD across \(p.hrvWindows) windows; oxygen saturation uses \(p.spo2Windows) windows. Algorithm v\(night.algoVersion).")
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
    let segments: [ZoopAPI.Night.Segment]
    let onset: Date
    let offset: Date

    static func color(_ stage: ZoopAPI.Night.Stage) -> Color {
        switch stage {
        case .wake: ZoopStyle.secondary.opacity(0.25)
        case .light: ZoopStyle.sleep.opacity(0.25)
        case .deep: ZoopStyle.sleep
        case .rem: ZoopStyle.sleep.opacity(0.6)
        }
    }

    private static func level(_ stage: ZoopAPI.Night.Stage) -> CGFloat {
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
    let delta: SleepMetricDelta?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10).accessibilityHidden(true)
                Text(name).font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) { durationLabel; shareLabel; if let delta { SleepDeltaLabel(delta: delta, id: name) } }
                VStack(alignment: .leading, spacing: 4) { durationLabel; shareLabel; if let delta { SleepDeltaLabel(delta: delta, id: name) } }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var durationLabel: some View { Text(hm(seconds)).font(ZoopType.headline).monospacedDigit() }
    @ViewBuilder private var shareLabel: some View {
        if let share { Text("\(Int((share * 100).rounded()))%")
            .font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary).monospacedDigit() }
    }
    private func hm(_ s: Int) -> String {
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(String(format: "%02d", m))m" : "\(m)m"
    }
}

private struct Stat: View {
    let title: String
    let value: String
    let unit: String
    let delta: SleepMetricDelta?

    init(_ title: String, _ value: String, unit: String = "", delta: SleepMetricDelta?) {
        self.title = title
        self.value = value
        self.unit = unit
        self.delta = delta
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title == "Resting heart rate" ? "Resting HR" : title)
                .font(ZoopType.font(size: 12, weight: .medium, relativeTo: .caption)).foregroundStyle(ZoopStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(ZoopType.font(size: 16, weight: .medium, relativeTo: .title3)).monospacedDigit()
                if !unit.isEmpty { Text(unit).font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary) }
            }
            if let delta { SleepDeltaLabel(delta: delta, id: title) }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
    }
}

private struct SleepDeltaLabel: View {
    let delta: SleepMetricDelta
    let id: String
    var body: some View {
        Text(delta.text).font(ZoopType.font(size: 12, weight: .semibold, relativeTo: .caption)).monospacedDigit()
            .foregroundStyle(InsightTone.color(delta.signal))
            .accessibilityLabel(delta.accessibility)
            .accessibilityIdentifier("sleepDelta-\(id)")
    }
}

private struct SleepSectionHeader: View {
    let title: String
    let comparison: String
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        layout {
            Text(title).font(ZoopStyle.sectionTitle).foregroundStyle(ZoopStyle.text)
            if !typeSize.isAccessibilitySize { Spacer() }
            Text(comparison).font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
        }
    }
}
