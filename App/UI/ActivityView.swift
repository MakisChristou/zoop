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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
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
                .padding(.bottom, 24)
            }
            .navigationTitle("Activity")
            .mainScreenChrome("Activity")
            .navigationDestination(for: SnoopAPI.Workout.self) { WorkoutDetailView(workout: $0) }
        }
        .task(id: model.strap.serial) { await load() }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(300)) } catch { return }
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
        let sessions = workouts.filter { $0.startTs >= week.first?.date ?? .distantPast }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Daily load").font(.subheadline.weight(.medium))
                Spacer()
                Text(sessions == 1 ? "1 session" : "\(sessions) sessions").font(.caption).foregroundStyle(SnoopStyle.secondary)
            }
            Text("Last 7 days · 0–21 scale").font(.caption).foregroundStyle(SnoopStyle.secondary)
            if typeSize.isAccessibilitySize {
                ForEach(week) { day in
                    HStack {
                        Text(Self.dayTitle(day.date))
                        Spacer()
                        Text(day.load.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—").monospacedDigit()
                    }.font(.subheadline).padding(.vertical, 4)
                }
            } else {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(week) { day in
                    VStack(spacing: 8) {
                        Text(day.load.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—")
                            .font(.caption2).monospacedDigit().foregroundStyle(SnoopStyle.secondary)
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3).fill(SnoopStyle.track.opacity(0.5)).frame(height: 72)
                            if let load = day.load, load > 0 {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Calendar.current.isDateInToday(day.date) ? SnoopStyle.load : SnoopStyle.load.opacity(0.55))
                                    .frame(height: max(2, 72 * CGFloat(min(load, LoadRing.maximum) / LoadRing.maximum)))
                            }
                        }
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2)
                            .foregroundStyle(Calendar.current.isDateInToday(day.date) ? .primary : .tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(Self.dayTitle(day.date)), \(day.load.map { "load \($0.formatted(.number.precision(.fractionLength(1))))" } ?? "no data")")
                }
            }
            }
        }
        .padding()
        .background(SnoopStyle.surface, in: RoundedRectangle(cornerRadius: SnoopStyle.radius))
        .padding(.horizontal, SnoopStyle.gutter)
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
                .font(.headline).accessibilityAddTraits(.isHeader)
                .padding(.horizontal, SnoopStyle.gutter)
            ForEach(items) { workout in
                NavigationLink(value: workout) { WorkoutRow(workout: workout) }
                    .buttonStyle(PressableCardStyle())
                    .padding(.horizontal, SnoopStyle.gutter)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loaded ? "No activities yet" : "Loading…").font(.headline)
            Text("Wear your WHOOP for a walk or workout. Detected activities appear here after syncing.")
                .font(.footnote).foregroundStyle(SnoopStyle.secondary)
        }
        .padding()
        .background(SnoopStyle.surface, in: RoundedRectangle(cornerRadius: SnoopStyle.radius))
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
