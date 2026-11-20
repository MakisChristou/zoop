import SwiftUI
import ZoopHealth

struct WeightGoalSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("weightUnit") private var unit = "kg"
    @State private var phase = "cut"
    @State private var reference = ""
    @State private var maintenanceRange = "1"
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
    @State private var conflict = false
    @FocusState private var typing: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize = 58.0
    var onSaved: () -> Void = {}
    private var existing: ZoopAPI.WeightGoal? { original }
    private var editing: Bool { existing?.active == true && existing?.kind == phase }
    private var factor: Double { unit == "lb" ? 2.2046226218 : 1 }
    private var rate: Double? {
        if phase == "maintenance" { return 0 }
        if value == initialValue { return initialRate }
        let normalized = value.replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")
        guard let n = Double(normalized), n.isFinite else { return nil }
        let kg = n / factor
        return (0.05...1.0).contains(kg) ? kg : nil
    }
    private var calendar: Calendar { CutPlan.calendar(timezone: existing?.timezone ?? TimeZone.current.identifier) }
    private var start: Date { editing ? (existing?.startedAt ?? Date()) : Date() }
    private var baseline: Double? {
        if editing { return model.weeklyWeight.summary?.progress?.startingWeightKg }
        return CutPlan.baseline(model.health.rows, start: start, calendar: calendar)
    }
    private var targetWeight: Double? { guard hasFinish, let rate else { return nil }; return CutPlan.target(starting: baseline, rate: phase == "bulk" ? -rate : rate, start: start, finish: finish, calendar: calendar) }
    private var finishRange: ClosedRange<Date> {
        let first = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: start)) ?? start
        let current = calendar.startOfDay(for: Date())
        let previous = editing ? CutPlan.date(existing?.finishDate, calendar: calendar) : nil
        let earliest = previous.map { min($0, max(first, current)) } ?? max(first, current)
        let latest = calendar.date(byAdding: .day, value: 730, to: start) ?? earliest
        return min(earliest, latest)...max(earliest, latest)
    }
    private var parsedSteps: Int? { guard let value = Int(stepGoal), (1...100_000).contains(value) else { return nil }; return value }
    private var validFinish: Bool { if phase != "maintenance" && !editing && !hasFinish { return false }; return !hasFinish || calendar.startOfDay(for: finish) > calendar.startOfDay(for: start) }
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
                    Picker("Goal", selection: $phase) {
                        Text("Cut").tag("cut"); Text("Bulk").tag("bulk"); Text("Maintain").tag("maintenance")
                    }.pickerStyle(.segmented).accessibilityIdentifier("goalPhase")
                    if phase == "maintenance" {
                        VStack(spacing: 12) {
                            maintenanceField("Reference · \(unit)", placeholder: "Learning", value: $reference, identifier: "maintenanceReference")
                            Divider()
                            maintenanceField("Range · ±%", placeholder: "1", value: $maintenanceRange, identifier: "maintenanceRange")
                        }.zoopCard()
                    } else {
                    VStack(spacing: 12) {
                        Text(phase == "bulk" ? "Weekly gain" : "Weekly loss").font(ZoopType.font(size: 20, weight: .semibold, relativeTo: .title2)).accessibilityAddTraits(.isHeader)
                        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10))
                        layout {
                            TextField(phase == "bulk" ? "Weekly gain" : "Weekly loss", text: $value).keyboardType(.decimalPad).focused($typing)
                                .font(ZoopType.fixed(size: min(numberSize, 88), weight: .medium)).monospacedDigit().multilineTextAlignment(.center)
                                .frame(maxWidth: 180).accessibilityLabel(phase == "bulk" ? "Weekly gain" : "Weekly loss").accessibilityIdentifier("weeklyLossInput")
                            Text("\(unit) / week").font(ZoopType.body).foregroundStyle(ZoopStyle.secondary)
                        }
                        if let rate, let weight = model.health.lastWeight?.kg, weight > 0, rate / weight > 0.01 {
                            Text("Fast pace · over 1% per week").font(ZoopType.subheadline).foregroundStyle(ZoopStyle.typical)
                        }
                        MeasurementRuler(value: ruler, range: (unit == "lb" ? 0.3...2.2 : 0.1...1.0), step: 0.1, unit: "\(unit) per week", label: "Weekly loss ruler", majorTickEvery: 4, onEditing: { typing = false })
                            .accessibilityIdentifier("weeklyLossRuler")
                    }.padding(.top, 16).padding(.bottom, 12)
                    }
                    VStack(spacing: 0) {
                        if phase != "maintenance" {
                        NavigationLink { finishEditor } label: {
                            goalRow("Finish date", value: hasFinish ? finishLabel : "None")
                        }.accessibilityIdentifier("editCutFinish")
                        Divider()
                        }
                        NavigationLink { stepsEditor } label: {
                            goalRow("Daily steps", value: hasStepGoal ? parsedSteps.map { $0.formatted() } ?? "Set goal" : "Off")
                        }.accessibilityIdentifier("editCutSteps")
                    }.buttonStyle(.plain).zoopCard()
                    NavigationLink { reminderEditor } label: {
                        goalRow("Reminders", value: nil)
                    }.buttonStyle(.plain).zoopCard().accessibilityIdentifier("editCutReminders")
                    if rate == nil { Text("Choose \(WeeklyWeightPresentation.weight(0.1, unit: unit))–\(WeeklyWeightPresentation.weight(1, unit: unit)) \(unit) per week.").font(ZoopType.footnote).foregroundStyle(ZoopStyle.unfavourable) }
                    if hasStepGoal && parsedSteps == nil { Text("Set a daily goal between 1 and 100,000 steps.").font(ZoopType.footnote).foregroundStyle(ZoopStyle.unfavourable) }
                    if !validFinish { Text("Choose a finish date after the start date.").font(ZoopType.footnote).foregroundStyle(ZoopStyle.unfavourable) }
                    if conflict {
                        Button("Discard edits and reload") {
                            Task { await model.weeklyWeight.reload(); if model.weeklyWeight.error == nil { dismiss() } else { error = model.weeklyWeight.error } }
                        }.font(ZoopType.footnote).frame(minHeight: 44).disabled(model.weeklyWeight.loading)
                    }
                    if let error { Text(error).font(ZoopType.footnote).foregroundStyle(ZoopStyle.unfavourable).accessibilityIdentifier("weightGoalSaveError") }
                }.padding(ZoopStyle.gutter)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button { save(active: true) } label: {
                    HStack { if model.weeklyWeight.saving { ProgressView() }; Text(editing ? "Save" : "Start goal").font(ZoopType.headline) }
                        .frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                }.buttonStyle(.borderedProminent).disabled(rate == nil || !validFinish || (hasStepGoal && parsedSteps == nil) || model.weeklyWeight.saving || conflict)
                    .accessibilityIdentifier("saveWeightGoal").padding(ZoopStyle.gutter).background(ZoopStyle.background)
            }
            .navigationTitle(editing ? "Edit goal" : "Start a goal").navigationBarTitleDisplayMode(.inline).zoopScreen().tint(ZoopStyle.text)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.weeklyWeight.saving) } }
            .interactiveDismissDisabled(model.weeklyWeight.saving)
            .onChange(of: phase) { old, new in
                guard initialized, old != new else { return }
                let same = existing?.kind == new
                initialRate = same ? existing?.weeklyLossKg ?? 0.3 : (new == "bulk" ? 0.2 : 0.3)
                value = (initialRate * factor).formatted(.number.precision(.fractionLength(2)))
                initialValue = value
                hasStepGoal = same && existing?.dailyStepsGoal != nil
                stepGoal = String(same ? existing?.dailyStepsGoal ?? 8000 : 8000)
                hasFinish = new != "maintenance"
                if !same { finish = calendar.date(byAdding: .weekOfYear, value: 8, to: Date()) ?? Date() }
                reference = same ? existing?.maintenanceReferenceKg.map { ($0 * factor).formatted(.number.precision(.fractionLength(1))) } ?? "" : ""
                maintenanceRange = same ? String(existing?.maintenanceRangePct ?? 1) : "1"
            }
            .onAppear {
                guard !initialized else { return }; initialized = true
                original = model.weeklyWeight.goal
                phase = existing?.kind ?? "cut"
                reference = existing?.maintenanceReferenceKg.map { ($0 * factor).formatted(.number.precision(.fractionLength(1))) } ?? ""
                maintenanceRange = String(existing?.maintenanceRangePct ?? 1)
                stepsReminder = model.stepsReminder.enabled; stepsReminderMinute = model.stepsReminder.minute
                hasStepGoal = existing?.dailyStepsGoal != nil
                stepGoal = String(existing?.dailyStepsGoal ?? 8000)
                hasFinish = phase != "maintenance" && (!editing || existing?.finishDate != nil)
                finish = (editing ? CutPlan.date(existing?.finishDate, calendar: calendar) : nil) ?? (calendar.date(byAdding: .weekOfYear, value: 8, to: Date()) ?? Date())
                initialRate = existing?.weeklyLossKg ?? 0.3
                value = (initialRate * factor).formatted(.number.precision(.fractionLength(1)))
                initialValue = value
                reminder = existing?.reminderEnabled ?? true; weekday = existing?.reminderWeekday ?? 1; minute = existing?.reminderMinute ?? 1200
            }
        }
    }
    private func maintenanceField(_ title: String, placeholder: String, value: Binding<String>, identifier: String) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 16))
        return layout {
            Text(title).font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary).fixedSize(horizontal: false, vertical: true)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            TextField(placeholder, text: value).keyboardType(.decimalPad)
                .font(ZoopType.body).monospacedDigit()
                .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                .accessibilityLabel(title).accessibilityIdentifier(identifier)
        }.frame(minHeight: 44)
    }
    private func goalRow(_ title: String, value: String?) -> some View {
        HStack(spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack { Text(title); Spacer(minLength: 12); if let value { Text(value).foregroundStyle(ZoopStyle.secondary).monospacedDigit() } }
                VStack(alignment: .leading, spacing: 4) { Text(title); if let value { Text(value).foregroundStyle(ZoopStyle.secondary).monospacedDigit() } }
            }
            Image(systemName: "chevron.right").font(ZoopType.font(size: 12, weight: .semibold, relativeTo: .caption)).foregroundStyle(ZoopStyle.secondary)
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
        let savedReference = existing?.kind == phase ? existing?.maintenanceReferenceKg : nil
        let originalReferenceText = savedReference.map { ($0 * factor).formatted(.number.precision(.fractionLength(1))) } ?? ""
        let parsedReference = reference == originalReferenceText ? savedReference : Double(reference.replacingOccurrences(of: ",", with: ".")).map { $0 / factor }
        let parsedRange = Double(maintenanceRange.replacingOccurrences(of: ",", with: "."))
        if phase == "maintenance" && ((!reference.isEmpty && (parsedReference == nil || !(20...400).contains(parsedReference!))) || parsedRange == nil || !(0.5...5).contains(parsedRange!)) {
            error = "Check your reference and range (0.5–5%)."; return
        }
        let input = ZoopAPI.WeightGoalInput(clearMaintenanceReference: phase == "maintenance" && reference.isEmpty && savedReference != nil, phase: phase, maintenanceReferenceKg: phase == "maintenance" ? parsedReference : nil, maintenanceRangePct: phase == "maintenance" ? parsedRange : nil, revision: existing?.revision ?? 0, active: active, timezone: existing?.timezone ?? TimeZone.current.identifier,
                                           weeklyLossKg: rate, reminderEnabled: reminder, reminderWeekday: weekday, reminderMinute: minute, dailyStepsGoal: hasStepGoal ? parsedSteps : nil, finishDate: phase != "maintenance" && hasFinish ? CutPlan.key(finish, calendar: calendar) : nil)
        Task {
            do {
                try await model.weeklyWeight.save(input)
                model.stepsReminder.minute = stepsReminderMinute
                model.stepsReminder.enabled = stepsReminder
                if active && (reminder || (hasStepGoal && stepsReminder)) { await model.battery.requestNotificationsIfNeeded() }
                model.refreshReminders()
                dismiss(); onSaved()
            } catch {
                self.error = error.localizedDescription
                if let failure = error as? ZoopAPI.Failure, case .server(409, _) = failure { conflict = true }
            }
        }
    }
}
