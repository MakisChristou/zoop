import SwiftUI
import SnoopHealth

struct WeightGoalSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("weightUnit") private var unit = "kg"
    @State private var value = "0.3"
    @State private var initialValue = ""
    @State private var initialRate = 0.3
    @State private var reminder = true
    @State private var weekday = 1
    @State private var minute = 20 * 60
    @State private var hasStepGoal = false
    @State private var stepGoal = "8000"
    @State private var hasFinish = false
    @State private var finish = Date()
    @State private var original: SnoopAPI.WeightGoal?
    @State private var initialized = false
    @State private var error: String?
    @State private var confirmPause = false
    @FocusState private var typing: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize = 58.0
    var onSaved: () -> Void = {}
    private var existing: SnoopAPI.WeightGoal? { original }
    private var editing: Bool { existing?.active == true }
    private var factor: Double { unit == "lb" ? 2.2046226218 : 1 }
    private var rate: Double? {
        if value == initialValue { return initialRate }
        let normalized = value.replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")
        guard let n = Double(normalized), n.isFinite else { return nil }
        let kg = n / factor
        return (0.1...1.0).contains(kg) ? kg : nil
    }
    private var calendar: Calendar { CutPlan.calendar(timezone: existing?.timezone ?? TimeZone.current.identifier) }
    private var start: Date { editing ? (existing?.startedAt ?? Date()) : Date() }
    private var baseline: Double? {
        if editing { return model.weeklyWeight.summary?.progress?.startingWeightKg }
        return CutPlan.baseline(model.health.rows, start: start, calendar: calendar)
    }
    private var targetWeight: Double? { guard hasFinish, let rate else { return nil }; return CutPlan.target(starting: baseline, rate: rate, start: start, finish: finish, calendar: calendar) }
    private var finishRange: ClosedRange<Date> {
        let first = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: start)) ?? start
        let current = calendar.startOfDay(for: Date())
        let previous = editing ? CutPlan.date(existing?.finishDate, calendar: calendar) : nil
        let earliest = previous.map { min($0, max(first, current)) } ?? max(first, current)
        let latest = calendar.date(byAdding: .day, value: 730, to: start) ?? earliest
        return min(earliest, latest)...max(earliest, latest)
    }
    private var parsedSteps: Int? { guard let value = Int(stepGoal), (1...100_000).contains(value) else { return nil }; return value }
    private var validFinish: Bool { !hasFinish || calendar.startOfDay(for: finish) > calendar.startOfDay(for: start) }
    private var ruler: Binding<Double> {
        Binding(get: { rate.map { $0 * factor } ?? 0.3 * factor }, set: { value = $0.formatted(.number.precision(.fractionLength(1))) })
    }
    private var time: Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date() }, set: { minute = Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0) })
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Text("Weekly loss").font(.title2.weight(.semibold))
                        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10))
                        layout {
                            TextField("Weekly loss", text: $value).keyboardType(.decimalPad).focused($typing)
                                .font(.system(size: min(numberSize, 88), weight: .medium)).monospacedDigit().multilineTextAlignment(.center)
                                .frame(maxWidth: 180).accessibilityLabel("Weekly loss").accessibilityIdentifier("weeklyLossInput")
                            Text("\(unit) / week").font(.body).foregroundStyle(SnoopStyle.secondary)
                        }
                        if let rate, let weight = model.health.lastWeight?.kg, weight > 0 {
                            let percent = rate / weight * 100
                            Text("\(percent.formatted(.number.precision(.fractionLength(1))))% of body weight\(percent > 1 ? " · Fast pace" : "")")
                                .font(.subheadline).foregroundStyle(percent > 1 ? SnoopStyle.typical : SnoopStyle.secondary)
                        }
                        MeasurementRuler(value: ruler, range: (unit == "lb" ? 0.3...2.2 : 0.1...1.0), step: 0.1, unit: "\(unit) per week", label: "Weekly loss ruler", majorTickEvery: 4, onEditing: { typing = false })
                            .accessibilityIdentifier("weeklyLossRuler")
                    }.padding(.top, 16).padding(.bottom, 12)
                    VStack(spacing: 12) {
                        Toggle("Finish date", isOn: $hasFinish).accessibilityIdentifier("hasCutFinish")
                        if hasFinish {
                            DatePicker("Finish", selection: $finish, in: finishRange, displayedComponents: .date)
                                .environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone).accessibilityIdentifier("cutFinishDate")
                            Divider()
                            HStack { Text("Target weight"); Spacer(); Text(WeeklyWeightPresentation.weight(targetWeight, unit: unit) + (targetWeight == nil ? "" : " " + unit)).monospacedDigit() }
                                .foregroundStyle(SnoopStyle.secondary).accessibilityIdentifier("cutTargetWeight")
                        }
                    }.snoopCard()
                    VStack(spacing: 12) {
                        Toggle("Daily steps", isOn: $hasStepGoal).accessibilityIdentifier("hasCutSteps")
                        if hasStepGoal {
                            HStack {
                                Text("Goal").foregroundStyle(SnoopStyle.secondary)
                                Spacer()
                                TextField("Steps", text: $stepGoal).keyboardType(.numberPad).multilineTextAlignment(.trailing).monospacedDigit()
                                    .frame(maxWidth: 140).accessibilityLabel("Daily steps goal").accessibilityIdentifier("cutStepsInput")
                            }
                        }
                    }.snoopCard()
                    VStack(spacing: 12) {
                        Toggle("Weekly brief", isOn: $reminder).accessibilityIdentifier("weeklyWeightReminder")
                        if reminder {
                            Divider()
                            ViewThatFits(in: .horizontal) {
                                HStack { Text("Remind me").foregroundStyle(SnoopStyle.secondary); Spacer(); schedule }
                                VStack(alignment: .leading, spacing: 8) { Text("Remind me").foregroundStyle(SnoopStyle.secondary); schedule }
                            }
                        }
                    }.snoopCard()
                    if let error { Text(error).font(.footnote).foregroundStyle(SnoopStyle.unfavourable).accessibilityIdentifier("weightGoalSaveError") }
                    if editing {
                        Button("Pause cut", role: .destructive) { confirmPause = true }.frame(minHeight: 44).accessibilityIdentifier("pauseWeightGoal")
                    }
                }.padding(SnoopStyle.gutter)
            }
            .safeAreaInset(edge: .bottom) {
                Button { save(active: true) } label: {
                    HStack { if model.weeklyWeight.saving { ProgressView() }; Text(editing ? "Save changes" : "Start cut").font(.headline) }
                        .frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                }.buttonStyle(.borderedProminent).disabled(rate == nil || !validFinish || (hasStepGoal && parsedSteps == nil) || model.weeklyWeight.saving)
                    .accessibilityIdentifier("saveWeightGoal").padding(SnoopStyle.gutter).background(SnoopStyle.background)
            }
            .navigationTitle(editing ? "Edit cut" : "Start a cut").navigationBarTitleDisplayMode(.inline).snoopScreen().tint(SnoopStyle.load)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.weeklyWeight.saving) } }
            .interactiveDismissDisabled(model.weeklyWeight.saving)
            .confirmationDialog("Pause your cut?", isPresented: $confirmPause, titleVisibility: .visible) {
                Button("Pause cut", role: .destructive) { save(active: false) }
            } message: { Text("Weekly reminders stop. Your weigh-ins stay saved.") }
            .onAppear {
                guard !initialized else { return }; initialized = true
                original = model.weeklyWeight.goal
                hasStepGoal = existing?.dailyStepsGoal != nil
                stepGoal = String(existing?.dailyStepsGoal ?? 8000)
                hasFinish = editing && existing?.finishDate != nil
                finish = (editing ? CutPlan.date(existing?.finishDate, calendar: calendar) : nil) ?? (calendar.date(byAdding: .weekOfYear, value: 8, to: Date()) ?? Date())
                initialRate = existing?.weeklyLossKg ?? 0.3
                value = (initialRate * factor).formatted(.number.precision(.fractionLength(1)))
                initialValue = value
                reminder = existing?.reminderEnabled ?? true; weekday = existing?.reminderWeekday ?? 1; minute = existing?.reminderMinute ?? 1200
            }
        }
    }
    private var schedule: some View {
        HStack(spacing: 4) {
            Picker("Reminder day", selection: $weekday) {
                ForEach(1...7, id: \.self) { day in Text(Calendar.current.weekdaySymbols[day - 1]).tag(day) }
            }.labelsHidden().pickerStyle(.menu).accessibilityIdentifier("weeklyWeightDay")
            DatePicker("Reminder time", selection: time, displayedComponents: .hourAndMinute).labelsHidden().accessibilityIdentifier("weeklyWeightTime")
        }
    }
    private func save(active: Bool) {
        guard let rate else { return }; typing = false; error = nil
        let input = SnoopAPI.WeightGoalInput(revision: existing?.revision ?? 0, active: active, timezone: existing?.timezone ?? TimeZone.current.identifier,
                                           weeklyLossKg: rate, reminderEnabled: reminder, reminderWeekday: weekday, reminderMinute: minute, dailyStepsGoal: hasStepGoal ? parsedSteps : nil, finishDate: hasFinish ? CutPlan.key(finish, calendar: calendar) : nil)
        Task {
            do {
                try await model.weeklyWeight.save(input)
                if active && reminder { await model.battery.requestNotificationsIfNeeded(); model.refreshReminders() }
                dismiss(); onSaved()
            } catch { self.error = error.localizedDescription }
        }
    }
}
