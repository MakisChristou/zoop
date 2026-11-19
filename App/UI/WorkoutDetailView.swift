import Charts
import SwiftUI

/// One session: load, the numbers behind it, time in each heart-rate zone, and the
/// heart-rate trace over the session with a drag readout. The type can be changed
/// from the toolbar; the server keeps that choice through recomputes.
struct WorkoutDetailView: View {
    @Environment(AppModel.self) private var model
    @State private var snapshot: ZoopAPI.Workout
    @State private var editor: WorkoutEditorMode?
    @State private var showReset = false
    @State private var confirmRemove = false
    @State private var removalRequest: WorkoutCorrection?
    @State private var readingsLoaded = false
    @State private var minutes: [ZoopAPI.Minute] = []
    @State private var scrub: Date?
    @State private var saving = false
    @State private var error: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    init(workout: ZoopAPI.Workout) {
        _snapshot = State(initialValue: workout)
    }

    private var workout: ZoopAPI.Workout { model.activity.items.first { $0.id == snapshot.id } ?? snapshot }

    private var kind: ActivityKind { .named(workout.kind) }
    private var window: ClosedRange<Date> {
        workout.startTs.addingTimeInterval(-300)...workout.endTs.addingTimeInterval(300)
    }

    private var selected: ZoopAPI.Minute? {
        guard let scrub else { return nil }
        return minutes.min { abs($0.ts.timeIntervalSince(scrub)) < abs($1.ts.timeIntervalSince(scrub)) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !workout.isActive {
                    Text(workout.status == "removed" ? "Workout removed" : "Workout replaced")
                        .font(ZoopType.headline).padding(.vertical)
                    if workout.status == "removed", let id = workout.lastEdit {
                        Button("Restore workout") { Task { await undo(id) } }.disabled(saving).frame(minHeight: 44)
                    }
                    Button("Reset to automatic") { showReset = true }.frame(minHeight: 44)
                } else {
                    hero
                    if workout.metricsPending == true {
                        HStack { ProgressView(); Text("Updating workout").font(ZoopType.footnote) }
                    } else if workout.isPartial {
                        Label("Partial data", systemImage: "waveform.path").font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                    }
                    stats
                    if workout.zonesMin != nil { zones }
                    heartRate
                }
                if workout.isActive { MetricInformation(title: "About load and calories", text: "Load is zone-weighted training impulse (Edwards 1993), displayed on a 0–21 scale. Calories are estimated from heart rate, weight, age and sex (Keytel 2005). Zones use your estimated maximum heart rate.\(workout.trimp.map { " Training impulse: \($0.formatted(.number.precision(.fractionLength(0)))) TRIMP." } ?? "")") }
                if let error { Text(error).font(ZoopType.footnote).foregroundStyle(.red) }
            }
            .padding(.horizontal, ZoopStyle.gutter).padding(.vertical, 16)
        }
        .sheet(isPresented: $showReset) { NavigationStack { AnalysisResetView(domain: "workout", targetId: workout.id, isSheet: true) }.presentationBackground(ZoopStyle.background) }
        .zoopScreen()
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle(kind.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if workout.isActive { ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if workout.isActive {
                        Button("Edit workout", systemImage: "pencil") { editor = .edit(workout) }
                        Button("Merge workouts", systemImage: "arrow.triangle.merge") { editor = .merge(workout) }
                        Button("Split workout", systemImage: "scissors") { editor = .split(workout) }
                        Button("Reset to automatic", systemImage: "arrow.counterclockwise") { showReset = true }
                        if let id = workout.lastEdit {
                            Button("Undo last edit", systemImage: "arrow.uturn.backward") { Task { await undo(id) } }
                        }
                        Divider()
                        Button("Remove workout", systemImage: "trash", role: .destructive) { confirmRemove = true }
                    }
                } label: {
                    if saving { ProgressView() } else { Label("Workout actions", systemImage: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }
                }
                .disabled(saving)
            } }
        }
        .task(id: "\(model.activity.changeToken)-\(model.analysisRevision)") { await load() }
        .sheet(item: $editor) { mode in
            WorkoutEditorView(mode: mode) { Task { await load() } }
        }
        .confirmationDialog("Remove this workout?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove workout", role: .destructive) { Task { await remove() } }
            Button("Cancel", role: .cancel) { }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { WorkoutNotice() }
    }

    // MARK: - Sections

    private var hero: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(spacing: 16))
        return layout {
            ZStack {
                LoadRing(load: workout.load ?? 0, lineWidth: 8)
                Image(systemName: kind.icon).font(ZoopType.font(size: 20, weight: .semibold, relativeTo: .title2)).foregroundStyle(kind.color)
            }
            .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 2) {
                MetricValue(workout.load.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—", unit: "Load")
                Text("\(workout.startTs.formatted(date: .omitted, time: .shortened)) – \(workout.endTs.formatted(date: .omitted, time: .shortened)) · \(ActivityView.dayTitle(workout.startTs).lowercased())")
                    .font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary)
                if workout.edited {
                    Text(workout.autoDetected ? "Edited" : "Added").font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                } else if kind == .activity {
                    Text("Unclassified").font(ZoopType.caption).foregroundStyle(kind.color)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(ZoopStyle.surface, in: RoundedRectangle(cornerRadius: ZoopStyle.radius))
    }

    private var stats: some View {
        var cells: [(String, String, String)] = [
            ("Duration", "\(workout.durationS / 60)", "min"),
            ("Calories", workout.kcal.map { "\(Int($0.rounded()))" } ?? "—", workout.kcal == nil && workout.hrCoverageS != 0 && workout.metricsPending != true ? "needs profile" : "kcal"),
            ("Average heart rate", workout.avgHr.map { "\(Int($0.rounded()))" } ?? "—", "bpm"),
            ("Max heart rate", workout.maxHr.map(String.init) ?? "—", "bpm"),
        ]
        if let steps = workout.steps, steps > 0 { cells.append(("Steps", steps.formatted(), "")) }
        return LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(cells, id: \.0) { title, value, unit in
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                    MetricValue(value, unit: unit, size: 20)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(ZoopStyle.surface, in: RoundedRectangle(cornerRadius: ZoopStyle.radius))
            }
        }
    }

    private var zones: some View {
        let minutesByZone = workout.zonesMin ?? [0, 0, 0, 0, 0]
        let total = max(minutesByZone.reduce(0, +), 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Heart rate zones").font(ZoopType.font(size: 12, weight: .semibold, relativeTo: .caption)).foregroundStyle(ZoopStyle.secondary)
                Spacer()
                Text("of max HR, minutes").font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary)
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(minutesByZone.enumerated()), id: \.offset) { zone, min in
                        if min > 0 {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(ZoneColors.color(zone))
                                .frame(width: max(6, geo.size.width * CGFloat(min) / CGFloat(total) - 2))
                        }
                    }
                    if minutesByZone.allSatisfy({ $0 == 0 }) {
                        RoundedRectangle(cornerRadius: 2).fill(.quaternary.opacity(0.5))
                    }
                }
            }
            .frame(height: 14)
            HStack(spacing: 10) {
                ForEach(Array(minutesByZone.enumerated()), id: \.offset) { zone, min in
                    VStack(spacing: 2) {
                        Text("\(min)").font(ZoopType.font(size: 14, weight: .semibold, relativeTo: .subheadline)).monospacedDigit()
                            .foregroundStyle(min > 0 ? .primary : .tertiary)
                        Text(ZoneColors.label(zone)).font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(20)
        .background(ZoopStyle.surface, in: RoundedRectangle(cornerRadius: ZoopStyle.radius))
    }

    private var heartRate: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Heart rate").font(ZoopType.headline).foregroundStyle(ZoopStyle.text)
                Spacer()
                if let m = selected {
                    Text("\(m.ts.formatted(date: .omitted, time: .shortened)) · \(m.hr.map { "\($0) bpm" } ?? "—")")
                        .font(ZoopType.font(size: 12, weight: .semibold, relativeTo: .caption)).monospacedDigit()
                } else {
                    Text(readingsLoaded ? (minutes.contains { $0.hr != nil } ? "bpm" : "No readings") : "Loading…").accessibilityIdentifier("workoutChartState").font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                }
            }
            Chart {
                RectangleMark(xStart: .value("from", workout.startTs), xEnd: .value("to", workout.endTs))
                    .foregroundStyle(kind.color.opacity(0.12))
                if let avg = workout.avgHr {
                    RuleMark(y: .value("avg", avg)).foregroundStyle(.secondary.opacity(0.5)).lineStyle(StrokeStyle(dash: [3, 3]))
                }
                ForEach(minutes.filter { $0.hr != nil }) { m in
                    AreaMark(x: .value("Time", m.ts), yStart: .value("min", m.hrMin ?? m.hr!), yEnd: .value("max", m.hrMax ?? m.hr!))
                    .foregroundStyle(ZoopStyle.heartRate.opacity(0.18))
                    LineMark(x: .value("Time", m.ts), y: .value("HR", m.hr!))
                        .foregroundStyle(ZoopStyle.heartRate)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
                if let m = selected {
                    RuleMark(x: .value("scrub", m.ts)).foregroundStyle(.primary.opacity(0.6))
                    if let hr = m.hr { PointMark(x: .value("scrub", m.ts), y: .value("HR", hr)).foregroundStyle(.primary) }
                }
            }
            .chartXScale(domain: window)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis { zoopTimeXAxis(ChartPresentation.dateTicks(window)) }
            .chartYAxis { zoopChartYAxis() }
            .font(ZoopType.caption2).frame(height: 164)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let x = value.location.x - geo[proxy.plotFrame!].origin.x
                                    scrub = proxy.value(atX: x, as: Date.self)
                                }
                                .onEnded { _ in scrub = nil }
                        )
                }
            }
        }
        .padding(20)
        .background(ZoopStyle.surface, in: RoundedRectangle(cornerRadius: ZoopStyle.radius))
    }

    // MARK: - Data

    private func load() async {
        guard !model.strap.serial.isEmpty, Settings.isConfigured else { return }
        do {
            var refreshed = try await ZoopAPI.workout(deviceId: model.strap.serial, id: snapshot.id)
            // Merged-away notification links lead to the surviving workout.
            for _ in 0..<10 {
                guard refreshed.status == "superseded", let id = refreshed.replacements?.first, id != refreshed.id else { break }
                refreshed = try await ZoopAPI.workout(deviceId: model.strap.serial, id: id)
            }
            snapshot = refreshed
            if refreshed.isActive {
                minutes = try await ZoopAPI.minutes(deviceId: model.strap.serial, window: window)
            }
            readingsLoaded = true
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func remove() async {
        saving = true
        defer { saving = false }
        let next = WorkoutCorrection(action: "remove", targets: [.init(workout)])
        if removalRequest?.hasSameChange(as: next) != true { removalRequest = next }
        guard let request = removalRequest else { return }
        do {
            try await model.activity.save(device: model.strap.serial, command: request)
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private func undo(_ id: String) async {
        saving = true
        defer { saving = false }
        do { try await model.activity.undo(device: model.strap.serial, id: id); await load() }
        catch { self.error = error.localizedDescription }
    }
}
