import SwiftUI
import ZoopHealth

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
    @State private var stepsReminder = true
    @State private var stepsReminderMinute = 22 * 60
    @State private var hasStepGoal = false
    @State private var stepGoal = "8000"
    @State private var hasFinish = false
    @State private var finish = Date()
    @State private var original: ZoopAPI.WeightGoal?
    @State private var initialized = false
    @State private var error: String?
    @State private var confirmPause = false
    @FocusState private var typing: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize = 58.0
    var onSaved: () -> Void = {}
    private var existing: ZoopAPI.WeightGoal? { original }
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
    private var stepsTime: Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: stepsReminderMinute / 60, minute: stepsReminderMinute % 60, second: 0, of: Date()) ?? Date() }, set: { stepsReminderMinute = Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0) })
    }
    private var time: Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date() }, set: { minute = Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0) })
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Text("Weekly loss").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10))
                        layout {
                            TextField("Weekly loss", text: $value).keyboardType(.decimalPad).focused($typing)
                                .font(.system(size: min(numberSize, 88), weight: .medium)).monospacedDigit().multilineTextAlignment(.center)
                                .frame(maxWidth: 180).accessibilityLabel("Weekly loss").accessibilityIdentifier("weeklyLossInput")
                            Text("\(unit) / week").font(.body).foregroundStyle(ZoopStyle.secondary)
                        }
                        if let rate, let weight = model.health.lastWeight?.kg, weight > 0, rate / weight > 0.01 {
                            Text("Fast pace · over 1% per week").font(.subheadline).foregroundStyle(ZoopStyle.typical)
                        }
                        MeasurementRuler(value: ruler, range: (unit == "lb" ? 0.3...2.2 : 0.1...1.0), step: 0.1, unit: "\(unit) per week", label: "Weekly loss ruler", majorTickEvery: 4, onEditing: { typing = false })
                            .accessibilityIdentifier("weeklyLossRuler")
                    }.padding(.top, 16).padding(.bottom, 12)
                    VStack(spacing: 0) {
                        NavigationLink { finishEditor } label: {
                            goalRow("Finish date", value: hasFinish ? finishLabel : "None")
                        }.accessibilityIdentifier("editCutFinish")
                        Divider()
                        NavigationLink { stepsEditor } label: {
                            goalRow("Daily steps", value: hasStepGoal ? parsedSteps.map { $0.formatted() } ?? "Set goal" : "Off")
                        }.accessibilityIdentifier("editCutSteps")
                    }.buttonStyle(.plain).zoopCard()
                    NavigationLink { reminderEditor } label: {
                        goalRow("Reminders", value: nil)
                    }.buttonStyle(.plain).zoopCard().accessibilityIdentifier("editCutReminders")
                    if rate == nil { Text("Choose \(WeeklyWeightPresentation.weight(0.1, unit: unit))–\(WeeklyWeightPresentation.weight(1, unit: unit)) \(unit) per week.").font(.footnote).foregroundStyle(ZoopStyle.unfavourable) }
                    if hasStepGoal && parsedSteps == nil { Text("Set a daily goal between 1 and 100,000 steps.").font(.footnote).foregroundStyle(ZoopStyle.unfavourable) }
                    if !validFinish { Text("Choose a finish date after the start date.").font(.footnote).foregroundStyle(ZoopStyle.unfavourable) }
                    if let error { Text(error).font(.footnote).foregroundStyle(ZoopStyle.unfavourable).accessibilityIdentifier("weightGoalSaveError") }
                    if editing {
                        Button("Pause cut", role: .destructive) { confirmPause = true }.font(.subheadline).frame(minHeight: 44).accessibilityIdentifier("pauseWeightGoal")
                    }
                }.padding(ZoopStyle.gutter)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button { save(active: true) } label: {
                    HStack { if model.weeklyWeight.saving { ProgressView() }; Text(editing ? "Save" : "Start cut").font(.headline) }
                        .frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                }.buttonStyle(.borderedProminent).disabled(rate == nil || !validFinish || (hasStepGoal && parsedSteps == nil) || model.weeklyWeight.saving)
                    .accessibilityIdentifier("saveWeightGoal").padding(ZoopStyle.gutter).background(ZoopStyle.background)
            }
            .navigationTitle(editing ? "Edit cut" : "Start a cut").navigationBarTitleDisplayMode(.inline).zoopScreen().tint(ZoopStyle.text)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.weeklyWeight.saving) } }
            .interactiveDismissDisabled(model.weeklyWeight.saving)
            .confirmationDialog("Pause your cut?", isPresented: $confirmPause, titleVisibility: .visible) {
                Button("Pause cut", role: .destructive) { save(active: false) }
            } message: { Text("Cut reminders stop. Your weigh-ins stay saved.") }
            .onAppear {
                guard !initialized else { return }; initialized = true
                original = model.weeklyWeight.goal
                stepsReminder = model.stepsReminder.enabled; stepsReminderMinute = model.stepsReminder.minute
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
    private func goalRow(_ title: String, value: String?) -> some View {
        HStack(spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack { Text(title); Spacer(minLength: 12); if let value { Text(value).foregroundStyle(ZoopStyle.secondary).monospacedDigit() } }
                VStack(alignment: .leading, spacing: 4) { Text(title); if let value { Text(value).foregroundStyle(ZoopStyle.secondary).monospacedDigit() } }
            }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(ZoopStyle.secondary)
        }.frame(minHeight: 44).padding(.vertical, 4).contentShape(Rectangle())
    }
    private var finishLabel: String {
        var format = Date.FormatStyle(date: .abbreviated, time: .omitted); format.timeZone = calendar.timeZone
        return finish.formatted(format)
    }
    private var finishEditor: some View {
        Form {
            Section {
                Toggle("Finish date", isOn: $hasFinish).accessibilityIdentifier("hasCutFinish")
                if hasFinish {
                    DatePicker("Finish", selection: $finish, in: finishRange, displayedComponents: .date)
                        .environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone).accessibilityIdentifier("cutFinishDate")
                }
            }.listRowBackground(ZoopStyle.surface)
            if hasFinish {
                Section {
                    LabeledContent("Target weight", value: WeeklyWeightPresentation.weight(targetWeight, unit: unit) + (targetWeight == nil ? "" : " " + unit))
                        .monospacedDigit().accessibilityIdentifier("cutTargetWeight")
                }.listRowBackground(ZoopStyle.surface)
            }
        }.scrollContentBackground(.hidden).zoopScreen().tint(ZoopStyle.text).navigationTitle("Finish date").navigationBarTitleDisplayMode(.inline)
    }
    private var stepsEditor: some View {
        Form {
            Section {
                Toggle("Daily steps", isOn: $hasStepGoal).accessibilityIdentifier("hasCutSteps")
                if hasStepGoal {
                    LabeledContent("Goal") {
                        TextField("Steps", text: $stepGoal).keyboardType(.numberPad).multilineTextAlignment(.trailing).monospacedDigit()
                            .accessibilityLabel("Daily steps goal").accessibilityIdentifier("cutStepsInput")
                    }
                }
            }.listRowBackground(ZoopStyle.surface)
        }.scrollDismissesKeyboard(.interactively).scrollContentBackground(.hidden).zoopScreen().tint(ZoopStyle.text).navigationTitle("Daily steps").navigationBarTitleDisplayMode(.inline)
    }
    private var reminderEditor: some View {
        Form {
            if hasStepGoal {
                Section {
                    Toggle("Steps reminder", isOn: $stepsReminder).accessibilityIdentifier("cutStepsReminder")
                    if stepsReminder {
                        reminderTime("Time", selection: stepsTime, identifier: "cutStepsReminderTime")
                    }
                }.listRowBackground(ZoopStyle.surface)
            }
            Section {
                Toggle("Weekly outlook", isOn: $reminder).accessibilityIdentifier("weeklyWeightReminder")
                if reminder {
                    Picker("Day", selection: $weekday) {
                        ForEach(1...7, id: \.self) { day in Text(Calendar.current.weekdaySymbols[day - 1]).tag(day) }
                    }.accessibilityIdentifier("weeklyWeightDay")
                    reminderTime("Time", selection: time, identifier: "weeklyWeightTime")
                }
            }.listRowBackground(ZoopStyle.surface)
        }.scrollContentBackground(.hidden).zoopScreen().tint(ZoopStyle.text).navigationTitle("Reminders").navigationBarTitleDisplayMode(.inline)
    }
    @ViewBuilder private func reminderTime(_ title: String, selection: Binding<Date>, identifier: String) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                DatePicker(title, selection: selection, displayedComponents: .hourAndMinute).labelsHidden().accessibilityIdentifier(identifier)
            }
        } else {
            DatePicker(title, selection: selection, displayedComponents: .hourAndMinute).accessibilityIdentifier(identifier)
        }
    }
    private func save(active: Bool) {
        guard let rate else { return }; typing = false; error = nil
        let input = ZoopAPI.WeightGoalInput(revision: existing?.revision ?? 0, active: active, timezone: existing?.timezone ?? TimeZone.current.identifier,
                                           weeklyLossKg: rate, reminderEnabled: reminder, reminderWeekday: weekday, reminderMinute: minute, dailyStepsGoal: hasStepGoal ? parsedSteps : nil, finishDate: hasFinish ? CutPlan.key(finish, calendar: calendar) : nil)
        Task {
            do {
                try await model.weeklyWeight.save(input)
                model.stepsReminder.minute = stepsReminderMinute
                model.stepsReminder.enabled = stepsReminder
                if active && (reminder || (hasStepGoal && stepsReminder)) { await model.battery.requestNotificationsIfNeeded() }
                model.refreshReminders()
                dismiss(); onSaved()
            } catch { self.error = error.localizedDescription }
        }
    }
}
