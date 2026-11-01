import Charts
import SwiftUI

/// One session: load, the numbers behind it, time in each heart-rate zone, and the
/// heart-rate trace over the session with a drag readout. The type can be changed
/// from the toolbar; the server keeps that choice through recomputes.
struct WorkoutDetailView: View {
    @EnvironmentObject private var model: AppModel
    @State private var workout: SnoopAPI.Workout
    @State private var minutes: [SnoopAPI.Minute] = []
    @State private var scrub: Date?
    @State private var saving = false
    @State private var error: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    init(workout: SnoopAPI.Workout) {
        _workout = State(initialValue: workout)
    }

    private var kind: ActivityKind { .named(workout.kind) }
    private var detected: ActivityKind { .named(workout.detectedKind) }
    private var window: ClosedRange<Date> {
        workout.startTs.addingTimeInterval(-300)...workout.endTs.addingTimeInterval(300)
    }

    private var selected: SnoopAPI.Minute? {
        guard let scrub else { return nil }
        return minutes.min { abs($0.ts.timeIntervalSince(scrub)) < abs($1.ts.timeIntervalSince(scrub)) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero
                stats
                zones
                heartRate
                MetricInformation(title: "About load and calories", text: "Load is zone-weighted training impulse (Edwards 1993), displayed on a 0–21 scale. Calories are estimated from heart rate, weight, age and sex (Keytel 2005). Zones use your estimated maximum heart rate.\(workout.trimp.map { " Training impulse: \($0.formatted(.number.precision(.fractionLength(0)))) TRIMP." } ?? "")")
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .padding(.horizontal, SnoopStyle.gutter).padding(.vertical, 16)
        }
        .snoopScreen()
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle(kind.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Type", selection: kindBinding) {
                        ForEach(ActivityKind.allCases) { k in
                            Label(k.longName, systemImage: k.icon).tag(k)
                        }
                    }
                } label: {
                    if saving { ProgressView() } else { Label("Change type", systemImage: "pencil.circle") }
                }
                .disabled(saving)
            }
        }
        .task { await load() }
    }

    private var kindBinding: Binding<ActivityKind> {
        Binding(get: { kind }, set: { newKind in
            guard newKind != kind else { return }
            Task { await relabel(newKind) }
        })
    }

    // MARK: - Sections

    private var hero: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(spacing: 16))
        return layout {
            ZStack {
                LoadRing(load: workout.load ?? 0, lineWidth: 8)
                Image(systemName: kind.icon).font(.title2.weight(.semibold)).foregroundStyle(kind.color)
            }
            .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 2) {
                MetricValue(workout.load.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—", unit: "Load")
                Text("\(workout.startTs.formatted(date: .omitted, time: .shortened)) – \(workout.endTs.formatted(date: .omitted, time: .shortened)) · \(ActivityView.dayTitle(workout.startTs).lowercased())")
                    .font(.subheadline).foregroundStyle(SnoopStyle.secondary)
                if workout.edited {
                    Text("Edited · detected as \(detected.name.lowercased())").font(.caption).foregroundStyle(SnoopStyle.secondary)
                } else if kind == .activity {
                    Text("Choose an activity type").font(.caption).foregroundStyle(kind.color)
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(SnoopStyle.surface, in: RoundedRectangle(cornerRadius: SnoopStyle.radius))
    }

    private var stats: some View {
        var cells: [(String, String, String)] = [
            ("Duration", "\(workout.durationS / 60)", "min"),
            ("Calories", workout.kcal.map { "\(Int($0.rounded()))" } ?? "—", workout.kcal == nil ? "needs profile" : "kcal"),
            ("Average heart rate", workout.avgHr.map { "\(Int($0.rounded()))" } ?? "—", "bpm"),
            ("Max heart rate", workout.maxHr.map(String.init) ?? "—", "bpm"),
        ]
        if let steps = workout.steps, steps > 0 { cells.append(("Steps", steps.formatted(), "")) }
        return LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(cells, id: \.0) { title, value, unit in
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.caption).foregroundStyle(SnoopStyle.secondary)
                    MetricValue(value, unit: unit, size: 28)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(SnoopStyle.surface, in: RoundedRectangle(cornerRadius: SnoopStyle.radius))
            }
        }
    }

    private var zones: some View {
        let minutesByZone = workout.zonesMin ?? [0, 0, 0, 0, 0]
        let total = max(minutesByZone.reduce(0, +), 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Heart rate zones").font(.caption.weight(.semibold)).foregroundStyle(SnoopStyle.secondary)
                Spacer()
                Text("of max HR, minutes").font(.caption2).foregroundStyle(SnoopStyle.secondary)
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
                        Text("\(min)").font(.subheadline.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(min > 0 ? .primary : .tertiary)
                        Text(ZoneColors.label(zone)).font(.caption2).foregroundStyle(SnoopStyle.secondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(SnoopStyle.surface, in: RoundedRectangle(cornerRadius: SnoopStyle.radius))
    }

    private var heartRate: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Heart rate").font(.caption.weight(.semibold)).foregroundStyle(SnoopStyle.secondary)
                Spacer()
                if let m = selected {
                    Text("\(m.ts.formatted(date: .omitted, time: .shortened)) · \(m.hr.map { "\($0) bpm" } ?? "—")")
                        .font(.caption.weight(.semibold)).monospacedDigit()
                } else {
                    Text(minutes.isEmpty ? "Loading…" : "bpm").font(.caption).foregroundStyle(SnoopStyle.secondary)
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
                    .foregroundStyle(SnoopStyle.heartRate.opacity(0.18))
                    LineMark(x: .value("Time", m.ts), y: .value("HR", m.hr!))
                        .foregroundStyle(SnoopStyle.heartRate)
                        .lineStyle(StrokeStyle(lineWidth: 1.4))
                        .interpolationMethod(.monotone)
                }
                if let m = selected {
                    RuleMark(x: .value("scrub", m.ts)).foregroundStyle(.primary.opacity(0.6))
                    if let hr = m.hr { PointMark(x: .value("scrub", m.ts), y: .value("HR", hr)).foregroundStyle(.primary) }
                }
            }
            .chartXScale(domain: window)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.hour().minute()) } }
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
            .frame(height: 160)
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
        .padding()
        .background(SnoopStyle.surface, in: RoundedRectangle(cornerRadius: SnoopStyle.radius))
    }

    // MARK: - Data

    private func load() async {
        guard !model.strap.serial.isEmpty, Settings.isConfigured else { return }
        do {
            let all = try await SnoopAPI.minutes(deviceId: model.strap.serial, day: workout.startTs)
            var inWindow = all.filter { window.contains($0.ts) }
            if workout.endTs > Calendar.current.startOfDay(for: workout.startTs).addingTimeInterval(86_400 - 300),
               let next = try? await SnoopAPI.minutes(deviceId: model.strap.serial, day: workout.endTs) {
                inWindow += next.filter { window.contains($0.ts) }
            }
            minutes = inWindow
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func relabel(_ newKind: ActivityKind) async {
        saving = true
        defer { saving = false }
        do {
            workout = try await SnoopAPI.setWorkoutKind(deviceId: model.strap.serial, id: workout.id, kind: newKind.rawValue)
            error = nil
        } catch {
            self.error = "Could not save the type: \(error.localizedDescription)"
        }
    }
}
