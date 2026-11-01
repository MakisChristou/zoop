import SwiftUI

/// Detected sessions, newest first, grouped by day, with the week's load on top.
/// Everything here is read from the server; the strap does not know what a workout is.
struct ActivityView: View {
    @EnvironmentObject private var model: AppModel
    @State private var workouts: [SnoopAPI.Workout] = []
    @State private var days: [SnoopAPI.Day] = []
    @State private var error: String?
    @State private var loaded = false
    @State private var path: [SnoopAPI.Workout] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    weekCard
                    if workouts.isEmpty {
                        emptyState
                    } else {
                        ForEach(groups, id: \.day) { group in
                            section(group.day, group.workouts)
                        }
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal) }
                }
                .padding(.vertical)
            }
            .navigationTitle("Activity")
            .mainScreenChrome()
            .navigationDestination(for: SnoopAPI.Workout.self) { WorkoutDetailView(workout: $0) }
        }
        .task { await load() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                await load()
            }
        }
        .refreshable { await load() }
        .onChange(of: model.battery.openWorkout, initial: true) { _, id in
            guard let id else { return }
            Task { await open(id) }
        }
    }

    // MARK: - Week

    private struct WeekDay: Identifiable {
        let date: Date
        let load: Double?
        var id: Date { date }
    }

    private var week: [WeekDay] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let byDay = Dictionary(uniqueKeysWithValues: days.compactMap { d in Self.day(d.day).map { ($0, d.load) } })
        return (0..<7).reversed().map { back in
            let date = cal.date(byAdding: .day, value: -back, to: today)!
            return WeekDay(date: date, load: byDay[date] ?? nil)
        }
    }

    private var weekCard: some View {
        let week = week
        let total = week.compactMap(\.load).reduce(0, +)
        let sessions = workouts.filter { $0.startTs >= week.first?.date ?? .distantPast }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                Text(sessions == 1 ? "1 session" : "\(sessions) sessions").font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(total.formatted(.number.precision(.fractionLength(1))))
                    .font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                Text("load").font(.title3).foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(week) { day in
                    VStack(spacing: 4) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 2).fill(.quaternary.opacity(0.5)).frame(height: 44)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Calendar.current.isDateInToday(day.date) ? Color.orange : Color.orange.opacity(0.45))
                                .frame(height: max(2, 44 * CGFloat((day.load ?? 0) / LoadRing.maximum)))
                        }
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2)
                            .foregroundStyle(Calendar.current.isDateInToday(day.date) ? .primary : .tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Sessions

    private struct Group {
        let day: Date
        let workouts: [SnoopAPI.Workout]
    }

    private var groups: [Group] {
        let cal = Calendar.current
        return Dictionary(grouping: workouts) { cal.startOfDay(for: $0.startTs) }
            .map { Group(day: $0.key, workouts: $0.value.sorted { $0.startTs > $1.startTs }) }
            .sorted { $0.day > $1.day }
    }

    private func section(_ day: Date, _ items: [SnoopAPI.Workout]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Self.dayTitle(day))
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                .padding(.horizontal)
            ForEach(items) { workout in
                NavigationLink(value: workout) { WorkoutRow(workout: workout) }
                    .buttonStyle(PressableCardStyle())
                    .padding(.horizontal)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loaded ? "No sessions yet" : "Loading…").font(.headline)
            Text("Walks of ten minutes and gym sessions of twenty are found on the server after each upload. Relabel anything it gets wrong.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding()
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Data

    private func load() async {
        guard !model.strap.serial.isEmpty, Settings.isConfigured else { return }
        async let w = SnoopAPI.workouts(deviceId: model.strap.serial, limit: 60)
        async let d = SnoopAPI.days(deviceId: model.strap.serial, limit: 7)
        do {
            workouts = try await w
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        if let d = try? await d { days = d }
        loaded = true
    }

    private func open(_ id: Int64) async {
        if workouts.isEmpty { await load() }
        if let workout = workouts.first(where: { $0.id == id }) {
            path = [workout]
        }
        model.battery.openWorkout = nil
    }

    private static func day(_ text: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: text)
    }

    static func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }
}

/// One session in a list: kind, when, how long, and its load.
struct WorkoutRow: View {
    let workout: SnoopAPI.Workout

    private var kind: ActivityKind { .named(workout.kind) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(kind.color.opacity(0.18))
                Image(systemName: kind.icon).font(.body.weight(.semibold)).foregroundStyle(kind.color)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(kind.name).font(.headline)
                    if kind == .activity, !workout.edited {
                        Text("Label it")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(kind.color.opacity(0.15), in: Capsule())
                            .foregroundStyle(kind.color)
                    }
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(workout.load.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—")
                    .font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
                Text("load").font(.caption2).foregroundStyle(.tertiary)
            }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }

    private var subtitle: String {
        var parts = ["\(workout.startTs.formatted(date: .omitted, time: .shortened)) · \(workout.durationS / 60) min"]
        if let kcal = workout.kcal { parts.append("\(Int(kcal.rounded())) kcal") }
        if let hr = workout.avgHr { parts.append("\(Int(hr.rounded())) bpm") }
        return parts.joined(separator: " · ")
    }
}
