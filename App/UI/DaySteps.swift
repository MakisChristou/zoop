import SwiftUI

/// Intraday totals and charts are read together from the existing steps endpoint.
struct DaySteps: View {
    let day: Date
    let summary: SnoopAPI.Day?
    let summariesLoaded: Bool
    private var workouts: [SnoopAPI.Workout] { model.activity.items }
    var refreshID = 0

    @Environment(AppModel.self) private var model
    @State private var loadID = UUID()
    @State private var state: Loadable = .loading
    @State private var selectedHour: Double?
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 190

    enum Loadable {
        case loading
        case loaded(SnoopAPI.StepsDay)
        case failed
    }

    private var noData: Bool { summariesLoaded && summary == nil && loaded?.walking == 0 }
    private var loaded: SnoopAPI.StepsDay? {
        if case let .loaded(data) = state { return data }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(ActivityView.dayTitle(day)).font(.subheadline).foregroundStyle(SnoopStyle.secondary)
                MetricValue(headlineValue, size: 54)
                Text("Steps").font(.subheadline).foregroundStyle(SnoopStyle.secondary)
            }
            .accessibilityElement(children: .combine)
            if let target = CutTargets.steps(goal: model.weeklyWeight.goal, day: day) {
                StepGoalProgress(steps: noData ? nil : loaded?.walking ?? summary?.stepsWalking, target: target)
            }
            if case .failed = state {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn’t update steps").font(.headline)
                    Button("Try again") { Task { await load() } }.frame(minHeight: 44)
                }.snoopCard()
            } else if noData {
                Text("No step data for this day.")
                    .font(.subheadline).foregroundStyle(SnoopStyle.secondary)
            } else {
                chart
            }
            if let data = loaded, !data.bouts.isEmpty { walks(data) }
        }
        .task(id: "\(model.strap.serial)-\(day.timeIntervalSince1970)-\(refreshID)") { await load() }
    }

    private var headlineValue: String {
        if noData { return "—" }
        return (loaded?.walking ?? summary?.stepsWalking).map { $0.formatted() } ?? "—"
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack { Text("By hour").font(.subheadline.weight(.medium)); Spacer(); selectionLabel }
                VStack(alignment: .leading, spacing: 4) { Text("By hour").font(.subheadline.weight(.medium)); selectionLabel }
            }
            if let data = loaded {
                HourlyStepsChart(hours: data.walkingHours, day: day, interactive: true, selection: $selectedHour)
                    .frame(height: chartHeight)
                if data.walking == 0 {
                    Text("No walking recorded").font(.footnote).foregroundStyle(SnoopStyle.secondary)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).frame(height: chartHeight)
                    .accessibilityLabel("Loading steps")
            }
        }
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
        .font(.caption).foregroundStyle(SnoopStyle.secondary).monospacedDigit()
    }

    private func walks(_ data: SnoopAPI.StepsDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Walks").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(data.bouts.reduce(0) { $0 + $1.durationS } / 60) min total")
                    .font(.caption).foregroundStyle(SnoopStyle.secondary)
            }
            .padding(.bottom, 12)
            ForEach(data.bouts) { bout in
                if let session = session(for: bout) {
                    NavigationLink(value: session) { WalkRow(bout: bout, linked: true) }.buttonStyle(PressableCardStyle())
                } else { WalkRow(bout: bout, linked: false) }
            }
        }
    }

    private func session(for bout: SnoopAPI.StepsDay.Bout) -> SnoopAPI.Workout? {
        workouts.first { w in
            let overlap = min(w.endTs, bout.end).timeIntervalSince(max(w.startTs, bout.start))
            return overlap * 2 >= Double(bout.durationS)
        }
    }

    private func load() async {
        guard !model.strap.serial.isEmpty, Settings.isConfigured else { state = .failed; return }
        if case .failed = state { state = .loading }
        let request = UUID(); loadID = request
        let serial = model.strap.serial, connection = Settings.connectionID, date = day
        do {
            let rows = try await SnoopAPI.steps(deviceId: serial, day: date)
            guard !Task.isCancelled, loadID == request, model.strap.serial == serial, Settings.connectionID == connection, day == date else { return }
            state = .loaded(rows)
        } catch {
            guard !Task.isCancelled, loadID == request, model.strap.serial == serial, Settings.connectionID == connection, day == date else { return }
            state = .failed
        }
    }
}
