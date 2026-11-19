import SwiftUI

/// Intraday totals and charts are read together from the existing steps endpoint.
struct DaySteps: View {
    let day: Date
    let summary: ZoopAPI.Day?
    let summariesLoaded: Bool
    private var workouts: [ZoopAPI.Workout] { model.activity.items }
    var refreshID = 0

    @Environment(AppModel.self) private var model
    @State private var loadID = UUID()
    @State private var refreshing = false
    @State private var state: Loadable = .loading
    @State private var selectedHour: Double?
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 164

    enum Loadable {
        case loading
        case loaded(ZoopAPI.StepsDay)
        case failed
    }

    private var noData: Bool { summariesLoaded && summary == nil && loaded?.walking == 0 }
    private var loaded: ZoopAPI.StepsDay? {
        if case let .loaded(data) = state { return data }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(ActivityView.dayTitle(day)).font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary)
                MetricValue(headlineValue, size: 20)
                Text("Steps").font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary)
            }
            .accessibilityElement(children: .combine)
            if let target = CutTargets.steps(goal: model.weeklyWeight.goal, day: day) {
                StepGoalProgress(steps: noData ? nil : loaded?.walking ?? summary?.stepsWalking, target: target)
            }
            if case .failed = state {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn’t update steps").font(ZoopType.headline)
                    Button("Try again") { Task { await load() } }.frame(minHeight: 44)
                }.zoopCard()
            } else if noData {
                Text("No step data for this day.")
                    .font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary)
            } else {
                chart
            }
            if let data = loaded, !data.bouts.isEmpty { walks(data) }
        }
        .zoopLoading(refreshing, label: "Loading hourly steps")
        .task(id: "\(model.strap.serial)-\(day.timeIntervalSince1970)-\(refreshID)") { await load() }
    }

    private var headlineValue: String {
        if noData { return "—" }
        return (loaded?.walking ?? summary?.stepsWalking).map { $0.formatted() } ?? "—"
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack { Text("By hour").font(ZoopType.font(size: 14, weight: .medium, relativeTo: .subheadline)); Spacer(); selectionLabel }
                VStack(alignment: .leading, spacing: 4) { Text("By hour").font(ZoopType.font(size: 14, weight: .medium, relativeTo: .subheadline)); selectionLabel }
            }
            if let data = loaded {
                HourlyStepsChart(hours: data.walkingHours, day: day, interactive: true, selection: $selectedHour)
                    .frame(height: chartHeight)
                if data.walking == 0 {
                    Text("No walking recorded").font(ZoopType.footnote).foregroundStyle(ZoopStyle.secondary)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).frame(height: chartHeight)
                    .accessibilityLabel("Loading steps")
            }
        }.zoopCard()
    }

    private var selectionLabel: some View {
        Group {
            if let value = selectedHour, let data = loaded {
                let hour = min(max(Int(value), 0), 23)
                let steps = data.walkingHours.indices.contains(hour) ? data.walkingHours[hour] : 0
                Text("\(HourlyStepsChart.hourLabel(hour, on: day)) · \(steps.formatted()) steps")
            } else {
                Text(day.formatted(.dateTime.day().month(.abbreviated)))
            }
        }
        .font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary).monospacedDigit()
    }

    private func walks(_ data: ZoopAPI.StepsDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Walks").font(ZoopType.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(data.bouts.reduce(0) { $0 + $1.durationS } / 60) min total")
                    .font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
            }
            .padding(.bottom, 12)
            ForEach(data.bouts) { bout in
                if let session = session(for: bout) {
                    NavigationLink(value: session) { WalkRow(bout: bout, linked: true) }.buttonStyle(PressableCardStyle())
                } else { WalkRow(bout: bout, linked: false) }
            }
        }
    }

    private func session(for bout: ZoopAPI.StepsDay.Bout) -> ZoopAPI.Workout? {
        workouts.first { w in
            let overlap = min(w.endTs, bout.end).timeIntervalSince(max(w.startTs, bout.start))
            return overlap * 2 >= Double(bout.durationS)
        }
    }

    private func load() async {
        guard !model.strap.serial.isEmpty, Settings.isConfigured else { state = .failed; return }
        if case .failed = state { state = .loading }
        let request = UUID(); loadID = request
        refreshing = true
        defer { if loadID == request { refreshing = false } }
        let serial = model.strap.serial, connection = Settings.connectionID, date = day
        do {
            let rows = try await ZoopAPI.steps(deviceId: serial, day: date)
            guard !Task.isCancelled, loadID == request, model.strap.serial == serial, Settings.connectionID == connection, day == date else { return }
            state = .loaded(rows)
            model.stepsReminder.receive(rows, scope: model.health.reminderScope)
        } catch {
            guard !Task.isCancelled, loadID == request, model.strap.serial == serial, Settings.connectionID == connection, day == date else { return }
            state = .failed
        }
    }
}
