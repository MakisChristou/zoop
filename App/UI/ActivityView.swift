import Charts
import ZoopData
import SwiftUI

/// Detected sessions, newest first, grouped by day, with the week's load on top.
/// Everything here is read from the server; the strap does not know what a workout is.
struct ActivityView: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedDay: Date?
    let requestID: UUID
    var detail = false
    var initialSummary: ZoopAPI.Day?
    private var workouts: [ZoopAPI.Workout] { model.activity.items }
    @State private var days: [ZoopAPI.Day] = []
    @State private var error: String?
    @State private var loaded = false
    @State private var loading = false
    @State private var loadID = UUID()
    @State private var path: [ZoopAPI.Workout] = []
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        SwiftUI.Group {
            if detail { screen }
            else { NavigationStack(path: $path) { screen } }
        }
        .onChange(of: requestID) { _, _ in path = []; Task { await load() } }
        .onChange(of: selectedDay) { _, _ in Task { await load() } }
        .onChange(of: model.sleep.changeToken) { _, _ in Task { await load() } }
        .onChange(of: model.analysisRevision) { _, _ in Task { await load() } }
        .onChange(of: model.activity.changeToken) { _, _ in Task { await load() } }
        .task(id: model.strap.serial) { await load() }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(300)) } catch { return }
                await load()
            }
        }
        .refreshable { await load() }
        .onChange(of: model.battery.openWorkout, initial: true) { _, id in
            guard !detail, let id else { return }
            Task { await open(id) }
        }
    }

    private var screen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                weekCard
                VStack(alignment: .leading, spacing: 12) {
                    actions
                    if visibleWorkouts.isEmpty {
                        Text(loaded ? (selectedDay == nil ? "No activities yet" : "No workouts this day") : "Loading…")
                            .font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary)
                    } else {
                        let sections = groups
                        VStack(spacing: 0) {
                            ForEach(Array(sections.enumerated()), id: \.element.day) { index, group in
                                section(group.day, group.workouts, first: index == 0, last: index == sections.count - 1)
                            }
                        }
                    }
                }.zoopCard().padding(.horizontal, ZoopStyle.gutter)
                if let error { Text(error).font(ZoopType.footnote).foregroundStyle(.red).padding(.horizontal) }
            }
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { WorkoutNotice() }
        .mainScreenChrome(detail ? "Load" : "Activity", detail: detail)
        .zoopLoading(loading, label: "Loading activity")
        .navigationDestination(for: ZoopAPI.Workout.self) { WorkoutDetailView(workout: $0) }
    }

    // MARK: - Week

    private struct WeekDay: Identifiable {
        let date: Date
        let load: Double?
        var id: Date { date }
    }

    private var week: [WeekDay] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: detail ? (selectedDay ?? Date()) : Date())
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
                Text("Daily load").font(ZoopType.font(size: 14, weight: .medium, relativeTo: .subheadline))
                Spacer()
                if !detail { Text(sessions == 1 ? "1 session" : "\(sessions) sessions").font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary) }
            }
            if detail {
                let summary = days.first { Self.day($0.day) == selectedDay } ?? (loaded ? nil : initialSummary)
                Text(summary?.load.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—")
                    .font(ZoopType.title).monospacedDigit().accessibilityIdentifier("dailyLoadValue")
            } else {
                Text("Last 7 days").font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
            }
            if typeSize.isAccessibilitySize {
                ForEach(week) { day in
                    HStack {
                        Text(Self.dayTitle(day.date))
                        Spacer()
                        Text(day.load.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—").monospacedDigit()
                    }.font(ZoopType.subheadline).padding(.vertical, 4)
                }
            } else {
            Chart(week) { day in
                if let load = day.load {
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Load", load), width: .ratio(0.65))
                        .foregroundStyle(ZoopStyle.load).cornerRadius(3)
                        .accessibilityLabel(Self.dayTitle(day.date))
                        .accessibilityValue("Load \(load.formatted(.number.precision(.fractionLength(1))))")
                }
            }
            .chartYScale(domain: 0...LoadRing.maximum)
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary)
            } }
            .chartYAxis { zoopChartYAxis() }
            .frame(height: 164).padding(.top, 10)

            }
        }
        .padding(20)
        .background(ZoopStyle.surface, in: RoundedRectangle(cornerRadius: ZoopStyle.radius))
        .padding(.horizontal, ZoopStyle.gutter)
    }

    // MARK: - Sessions

    private struct Group {
        let day: Date
        let workouts: [ZoopAPI.Workout]
    }

    private var visibleWorkouts: [ZoopAPI.Workout] {
        guard let selectedDay, let end = Calendar.current.date(byAdding: .day, value: 1, to: selectedDay) else { return workouts }
        return workouts.filter { $0.startTs < end && $0.endTs > selectedDay }
    }

    private var actions: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedDay.map(Self.dayTitle) ?? "Recent activities").font(ZoopStyle.sectionTitle)
                if selectedDay != nil && !detail { Button("Show all") { selectedDay = nil }.font(ZoopType.caption).frame(minHeight: 44) }
            }
            Spacer()
            NavigationLink { RemovedWorkoutsView() } label: {
                Image(systemName: "archivebox").font(.system(size: 16)).frame(width: 44, height: 44).padding(.vertical, -12)
            }.accessibilityLabel("Removed workouts").accessibilityIdentifier("removedWorkouts")
        }
    }

    private var groups: [Group] {
        let cal = Calendar.current
        return Dictionary(grouping: visibleWorkouts) { cal.startOfDay(for: $0.startTs) }
            .map { Group(day: $0.key, workouts: $0.value.sorted { $0.startTs > $1.startTs }) }
            .sorted { $0.day > $1.day }
    }

    private func section(_ day: Date, _ items: [ZoopAPI.Workout], first: Bool, last: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Circle().fill(ZoopStyle.secondary.opacity(0.4)).frame(width: 7, height: 7)
                    .frame(width: 36).background(ZoopStyle.surface)
                    .accessibilityHidden(true)
                Text(Self.dayTitle(day)).font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
            }.frame(minHeight: 28)
                .background { WorkoutTimelineRail(startsHere: first) }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, workout in
                NavigationLink(value: workout) {
                    WorkoutTimelineRow(workout: workout, isLast: last && index == items.count - 1)
                }
                .accessibilityIdentifier("workout-\(workout.id)")
                .buttonStyle(PressableCardStyle())
            }
        }
    }

    // MARK: - Data

    private func load() async {
        guard !model.strap.serial.isEmpty, Settings.isConfigured else { return }
        let serial = model.strap.serial, connection = Settings.connectionID, day = selectedDay
        let request = UUID(); loadID = request
        loading = true
        defer { if loadID == request { loading = false } }
        async let w: Void = model.activity.reload(device: serial, from: day, to: day.flatMap { Calendar.current.date(byAdding: .day, value: 1, to: $0) })
        async let d = ZoopAPI.days(deviceId: serial, limit: detail ? 37 : 7)
        var failure: String?
        do { try await w } catch { failure = error.localizedDescription }
        let rows = try? await d
        guard !Task.isCancelled, loadID == request, model.strap.serial == serial, Settings.connectionID == connection, day == selectedDay else { return }
        error = failure
        if let rows { days = rows }
        loaded = true
    }

    private func open(_ id: Int64) async {
        do {
            let workout = try await ZoopAPI.workout(deviceId: model.strap.serial, id: id)
            path = [workout]
        } catch { self.error = "Couldn’t open this workout. Refresh and try again." }
        model.battery.openWorkout = nil
    }

    private static func day(_ text: String) -> Date? {
        DayKey.date(text)
    }

    static func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }
}
