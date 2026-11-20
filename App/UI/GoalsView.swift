import SwiftUI
import ZoopHealth

struct GoalsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("weightUnit") private var unit = "kg"
    @State private var editing = false
    @State private var ending = false
    @State private var about = false
    @State private var weekly = false
    @State private var selectedWeek: String?
    @State private var selectedPeriod: ZoopAPI.GoalPeriod?
    @State private var actionError: String?
    private var store: WeeklyWeightStore { model.weeklyWeight }
    private var data: CutProgressData? {
        guard let g = store.goal, g.active, let s = store.summary else { return nil }
        return CutProgressData(goal: g, summary: s)
    }
    private var maintenanceReadings: [ZoopAPI.CutWeighIn] {
        let calendar = Calendar.current
        let range = WeightChartData.Period.month.range(now: Date(), calendar: calendar)
        let points = WeightChartData(model.health.rows, range: range, calendar: calendar).points
        return Dictionary(grouping: points) { calendar.startOfDay(for: $0.date) }.compactMap {
            day, rows in
            rows.max { $0.date < $1.date }.map {
                .init(day: CutPlan.key(day, calendar: calendar), kg: $0.kg)
            }
        }.sorted { $0.day < $1.day }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if store.goal != nil || store.loaded {
                    header
                    if let data {
                        GoalWeightChart(
                            readings: data.summary.progress?.weighIns ?? [],
                            timezone: data.goal.timezone, unit: unit,
                            target: data.summary.progress?.targetWeightKg, lower: data.summary.maintenanceLowerKg, upper: data.summary.maintenanceUpperKg)
                        GoalProgressCard(data: data, unit: unit)
                        if let target = CutTargets.steps(goal: store.goal, day: Date()) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack { Text("Steps").font(ZoopStyle.sectionTitle); Spacer(); Text(model.stepsReminder.currentSteps?.formatted() ?? "—").font(ZoopType.subheadline).monospacedDigit() }
                                StepGoalProgress(steps: model.stepsReminder.currentSteps, target: target)
                            }.zoopCard()
                        }
                    } else if store.goal?.active != true {
                        GoalWeightChart(
                            readings: maintenanceReadings, timezone: TimeZone.current.identifier,
                            unit: unit)
                    } else if store.loading {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 144)
                    }
                } else if store.loading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 144)
                }
                history
                if let error = actionError ?? store.error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).foregroundStyle(ZoopStyle.unfavourable)
                        Button("Refresh") { Task { await refresh() } }.frame(minHeight: 44)
                    }.font(ZoopType.subheadline)
                }
                if store.goal?.reminderEnabled == true && store.goal?.active == true
                    && model.battery.authorization == .denied
                {
                    Button("Allow weekly notifications in Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }.font(ZoopType.footnote)
                }
                if let error = store.reminder.error {
                    VStack(alignment: .leading) {
                        Text(error)
                        Button("Retry") { model.refreshReminders() }.frame(minHeight: 44)
                    }.font(ZoopType.footnote)
                }
            }.padding(ZoopStyle.gutter)
        }.zoopScreen().mainScreenChrome("Goals").zoopLoading(store.loading, label: "Loading goals")
            .sheet(isPresented: $editing) {
                WeightGoalSetupView(onSaved: { Task { await store.reloadHistory() } })
            }
            .sheet(isPresented: $weekly) {
                NavigationStack {
                    ScrollView {
                        if let data {
                            CutWeeklyChart(data: data, unit: unit, selection: $selectedWeek)
                                .padding(ZoopStyle.gutter)
                        }
                    }
                    .zoopScreen().navigationTitle("Weekly pace").navigationBarTitleDisplayMode(
                        .inline
                    )
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { weekly = false }
                        }
                    }
                }
            }
            .sheet(isPresented: $about) {
                NavigationStack {
                    List {
                        Section("Weekly weight") {
                            Text("Weekly median. Comparisons need 4 weigh-ins across 5 days.")
                        }
                        Section("Your pace") { Text("Three qualifying weeks establish your trend. A single slow week isn’t a stall.") }
                        if store.goal?.kind == "maintenance" {
                            Section("Maintenance range") { Text("A fixed reference from your first full week, or a weight you choose. It won’t follow gradual drift.") }
                        } else {
                            Section("Target weight") { Text("Based on your rate and finish date. A goal, not a prediction.") }
                        }
                    }.navigationTitle("About").toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { about = false }
                        }
                    }
                }
            }
            .sheet(item: $selectedPeriod) { GoalPeriodView(id: $0.id, store: store, unit: unit) }
            .confirmationDialog("End this goal?", isPresented: $ending, titleVisibility: .visible) {
                Button("End goal") {
                    Task {
                        do {
                            actionError = nil
                            try await store.endCurrent()
                            model.refreshReminders()
                        } catch { actionError = error.localizedDescription }
                    }
                }.disabled(store.saving)
                Button("Keep going", role: .cancel) {}
            } message: {
                Text("Maintenance starts next. Your history stays.")
            }
            .task {
                await refresh()
                await model.battery.refreshAuthorization()
            }
            .refreshable { await refresh() }
            .onChange(of: store.goal?.id) { _, _ in selectedWeek = nil }
    }
    private func refresh() async {
        actionError = nil
        await store.reload()
        await store.reloadHistory()
    }
    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text(store.goal?.title ?? "Maintenance").font(
                    ZoopStyle.sectionTitle)
                Spacer(minLength: 4)
                if store.goal?.active == true {
                    if !typeSize.isAccessibilitySize, let time = data?.time {
                        Text("\(time.remaining) days left").font(ZoopType.caption).foregroundStyle(
                            ZoopStyle.secondary)
                    }
                    Menu {
                        Button("Edit goal") { editing = true }.accessibilityIdentifier(
                            "editWeightGoal")
                        if store.goal?.kind != "maintenance" { Button("End goal") { ending = true } }
                        if data != nil { Button("Weekly pace") { weekly = true } }
                        Button("About weight outlook") { about = true }
                    } label: {
                        if store.saving {
                            ProgressView().frame(width: 44, height: 44)
                        } else {
                            Image(systemName: "ellipsis").frame(width: 44, height: 44)
                        }
                    }.disabled(store.saving).accessibilityLabel("Goal options")
                        .accessibilityIdentifier("cutOptions")
                } else {
                    Button("Start a goal") { editing = true }.buttonStyle(.borderedProminent)
                        .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                        .accessibilityIdentifier("startWeightGoal")
                }
            }
            if typeSize.isAccessibilitySize, store.goal?.active == true, let time = data?.time {
                Text("\(time.remaining) days left").font(ZoopType.caption).foregroundStyle(
                    ZoopStyle.secondary
                ).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let summary = store.summary {
                Text(WeeklyWeightPresentation.title(summary.state)).font(ZoopType.caption)
                    .foregroundStyle(WeeklyWeightPresentation.color(summary.state)).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().overlay(ZoopStyle.separator)
        }.padding(.bottom, 8)
    }
    @ViewBuilder private var history: some View {
        if !store.history.isEmpty || store.historyLoading || store.historyError != nil {
            VStack(alignment: .leading, spacing: 20) {
                Text("Past goals").font(ZoopStyle.sectionTitle)
                ForEach(store.history) { period in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 20) {
                            Circle().fill(ZoopStyle.secondary.opacity(0.45)).frame(
                                width: 8, height: 8
                            ).frame(width: 36)
                            Text(periodDates(period)).font(ZoopType.caption).foregroundStyle(
                                ZoopStyle.secondary)
                        }
                        Button {
                            selectedPeriod = period
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: period.goal.kind == "bulk" ? "arrow.up.right" : period.goal.kind == "maintenance" ? "arrow.right" : "arrow.down.right").font(ZoopType.body).frame(
                                    width: 36, height: 36
                                )
                                .background(ZoopStyle.surface, in: Circle()).overlay(
                                    Circle().stroke(ZoopStyle.separator, lineWidth: 1))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(period.goal.title).font(ZoopType.subheadline)
                                    Text(period.outcome).font(ZoopType.caption).foregroundStyle(
                                        period.outcome == "Target reached"
                                            ? ZoopStyle.favourable : ZoopStyle.secondary)
                                }
                                Spacer(minLength: 8)
                                Text(
                                    WeeklyWeightPresentation.weight(
                                        period.summary.progress?.totalLostKg.map { -$0 },
                                        unit: unit, signed: true)
                                        + (period.summary.progress?.totalLostKg == nil
                                            ? "" : " " + unit)
                                )
                                .font(ZoopType.subheadline).monospacedDigit()
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }.background(alignment: .leading) {
                        Rectangle().fill(ZoopStyle.separator).frame(width: 1).padding(
                            .leading, 17.5
                        ).padding(.top, 6)
                    }
                }
                if store.historyLoading { ProgressView().frame(maxWidth: .infinity) }
                if let error = store.historyError {
                    Text(error).font(ZoopType.footnote).foregroundStyle(ZoopStyle.unfavourable)
                    Button("Retry") { Task { await store.reloadHistory() } }.frame(minHeight: 44)
                } else if store.nextCursor != nil {
                    Button("More goals") { Task { await store.reloadHistory(more: true) } }.frame(
                        minHeight: 44
                    ).disabled(store.historyLoading)
                }
            }.zoopCard()
        }
    }
    private func periodDates(_ p: ZoopAPI.GoalPeriod) -> String {
        var f = Date.FormatStyle().day().month(.abbreviated).year()
        f.timeZone = TimeZone(identifier: p.goal.timezone) ?? .current
        return p.goal.startedAt.formatted(f) + " – "
            + p.endedAt.addingTimeInterval(-0.001).formatted(f)
    }
}
