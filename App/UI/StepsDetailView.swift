import Charts
import SwiftUI

/// Steps in depth. Today by hour with each walk listed; a week or a month of days to
/// compare, any of which opens into its own hours and walks in place.
struct StepsDetailView: View {
    @EnvironmentObject private var model: AppModel
    @State private var scope: Scope = .today
    @State private var days: [SnoopAPI.Day] = []
    @State private var workouts: [SnoopAPI.Workout] = []
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var detail: SnoopAPI.StepsDay?
    @State private var scrubHour: Int?
    @State private var error: String?

    enum Scope: String, CaseIterable, Identifiable {
        case today = "Today", week = "7D", month = "30D"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Scope", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if scope != .today { comparison }
                dayCard
                walks
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .padding()
        }
        .navigationTitle("Steps")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadAll() }
        .refreshable { await loadAll() }
        .onChange(of: scope) { _, new in
            if new == .today { select(Calendar.current.startOfDay(for: Date())) }
        }
    }

    // MARK: - Comparison

    private struct DayPoint: Identifiable {
        let date: Date
        let steps: Int
        var id: Date { date }
    }

    private var points: [DayPoint] {
        let count = scope == .week ? 7 : 30
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let byDay = Dictionary(uniqueKeysWithValues: days.compactMap { d in Self.day(d.day).map { ($0, d.stepsWalking ?? d.steps ?? 0) } })
        return (0..<count).reversed().map { back in
            let date = cal.date(byAdding: .day, value: -back, to: today)!
            return DayPoint(date: date, steps: byDay[date] ?? 0)
        }
    }

    private var comparison: some View {
        let pts = points
        let with = pts.filter { $0.steps > 0 }
        let average = with.isEmpty ? 0 : Double(with.map(\.steps).reduce(0, +)) / Double(with.count)
        let selectedSteps = pts.first { $0.date == selectedDay }?.steps
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(scope == .week ? "Last 7 days" : "Last 30 days").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                Text("avg \(Int(average.rounded()).formatted()) · tap a day").font(.caption2).foregroundStyle(.tertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text((selectedSteps ?? 0).formatted())
                    .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                Text(ActivityView.dayTitle(selectedDay).lowercased()).font(.subheadline).foregroundStyle(.secondary)
                if let s = selectedSteps, average > 0 {
                    let delta = Int((Double(s) - average).rounded())
                    Text((delta >= 0 ? "+" : "") + delta.formatted() + " vs avg")
                        .font(.caption).foregroundStyle(delta >= 0 ? .green : .secondary).monospacedDigit()
                }
            }
            Chart {
                ForEach(pts) { p in
                    BarMark(x: .value("Day", p.date, unit: .day), y: .value("Steps", p.steps))
                        .foregroundStyle(p.date == selectedDay ? Color.teal : Color.teal.opacity(0.35))
                        .cornerRadius(3)
                }
                if average > 0 {
                    RuleMark(y: .value("avg", average)).foregroundStyle(.secondary.opacity(0.5)).lineStyle(StrokeStyle(dash: [3, 3]))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: scope == .week ? 1 : 7)) { _ in
                    AxisValueLabel(format: scope == .week ? .dateTime.weekday(.narrow) : .dateTime.day().month(.abbreviated))
                }
            }
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
            .frame(height: 130)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0).onEnded { value in
                                let x = value.location.x - geo[proxy.plotFrame!].origin.x
                                if let date = proxy.value(atX: x, as: Date.self) {
                                    select(Calendar.current.startOfDay(for: date))
                                }
                            }
                        )
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Day

    private struct Hour: Identifiable {
        let hour: Int
        let walking: Int
        let other: Int
        var id: Int { hour }
    }

    private var hours: [Hour] {
        guard let detail else { return [] }
        return (0..<24).map { h in
            let total = h < detail.hours.count ? detail.hours[h] : 0
            let walking = h < detail.walkingHours.count ? detail.walkingHours[h] : 0
            return Hour(hour: h, walking: walking, other: max(0, total - walking))
        }
    }

    private var dayRow: SnoopAPI.Day? {
        days.first { Self.day($0.day) == selectedDay }
    }

    private var dayCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(scope == .today ? "By hour" : "\(ActivityView.dayTitle(selectedDay)) by hour")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                if let h = scrubHour, let hour = hours.first(where: { $0.hour == h }) {
                    Text("\(String(format: "%02d", h)):00 · \((hour.walking + hour.other).formatted()) steps")
                        .font(.caption.weight(.semibold)).monospacedDigit()
                } else {
                    Text(detail == nil ? "loading" : "drag to inspect").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            if scope == .today {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text((detail?.walking ?? 0).formatted())
                        .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text("while walking").font(.subheadline).foregroundStyle(.secondary)
                }
                Text(dayCaption).font(.caption).foregroundStyle(.tertiary)
            } else {
                Text(dayCaption).font(.caption).foregroundStyle(.secondary)
            }
            Chart(hours) { h in
                BarMark(x: .value("Hour", h.hour), y: .value("Walking", h.walking))
                    .foregroundStyle(Color.teal)
                BarMark(x: .value("Hour", h.hour), y: .value("Other", h.other))
                    .foregroundStyle(Color.teal.opacity(0.3))
            }
            .chartXScale(domain: -0.5...23.5)
            .chartXAxis { AxisMarks(values: [0, 6, 12, 18]) { v in AxisGridLine(); AxisValueLabel { Text("\(v.as(Int.self) ?? 0)h") } } }
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
            .frame(height: 140)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let x = value.location.x - geo[proxy.plotFrame!].origin.x
                                    scrubHour = proxy.value(atX: x, as: Double.self).map { Int($0.rounded()) }
                                }
                                .onEnded { _ in scrubHour = nil }
                        )
                }
            }
            HStack(spacing: 14) {
                Label { Text("walking") } icon: { RoundedRectangle(cornerRadius: 2).fill(Color.teal).frame(width: 12, height: 8) }
                Label { Text("other counter movement") } icon: { RoundedRectangle(cornerRadius: 2).fill(Color.teal.opacity(0.3)).frame(width: 12, height: 8) }
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }

    private var dayCaption: String {
        guard let detail else { return "" }
        var parts: [String] = []
        if scope != .today { parts.append("\(detail.walking.formatted()) while walking") }
        if detail.total > detail.walking { parts.append("\(detail.total.formatted()) on the counter") }
        if let s = dayRow?.walkingS { parts.append("\(s / 60) min on foot") }
        parts.append(detail.bouts.count == 1 ? "1 walk" : "\(detail.bouts.count) walks")
        return parts.joined(separator: " · ")
    }

    // MARK: - Walks

    private var walks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Walks").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            if let detail, detail.bouts.isEmpty {
                Text("No walk of three minutes or more \(scope == .today ? "yet today" : "that day").").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(detail?.bouts ?? []) { bout in
                if let session = session(for: bout) {
                    NavigationLink(value: session) { BoutRow(bout: bout, linked: true) }.buttonStyle(PressableCardStyle())
                } else {
                    BoutRow(bout: bout, linked: false)
                }
            }
        }
    }

    private struct BoutRow: View {
        let bout: SnoopAPI.StepsDay.Bout
        let linked: Bool

        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: "figure.walk").font(.body.weight(.semibold)).foregroundStyle(.teal).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(bout.start.formatted(date: .omitted, time: .shortened)) – \(bout.end.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline.weight(.medium)).monospacedDigit()
                    Text("\(bout.durationS / 60) min · \(bout.steps.formatted()) steps · \(Int(bout.cadenceSpm.rounded())) /min")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                if linked {
                    Text("session").font(.caption2).foregroundStyle(.tertiary)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    /// The session a bout belongs to, when one covers at least half of it.
    private func session(for bout: SnoopAPI.StepsDay.Bout) -> SnoopAPI.Workout? {
        workouts.first { w in
            let overlap = min(w.endTs, bout.end).timeIntervalSince(max(w.startTs, bout.start))
            return overlap * 2 >= Double(bout.durationS)
        }
    }

    // MARK: - Data

    private func loadAll() async {
        guard !model.strap.serial.isEmpty, Settings.isConfigured else { return }
        async let d = SnoopAPI.days(deviceId: model.strap.serial, limit: 30)
        async let w = SnoopAPI.workouts(deviceId: model.strap.serial, limit: 60)
        if let d = try? await d { days = d }
        if let w = try? await w { workouts = w }
        await loadDetail(selectedDay)
    }

    private func select(_ day: Date) {
        guard day <= Calendar.current.startOfDay(for: Date()) else { return }
        withAnimation(.easeOut(duration: 0.2)) { selectedDay = day }
        Task { await loadDetail(day) }
    }

    private func loadDetail(_ day: Date) async {
        guard !model.strap.serial.isEmpty, Settings.isConfigured else { return }
        do {
            let fetched = try await SnoopAPI.steps(deviceId: model.strap.serial, day: day)
            if day == selectedDay { detail = fetched }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private static func day(_ text: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: text)
    }
}
