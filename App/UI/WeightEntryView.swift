import SwiftUI
import SnoopHealth

struct WeightEntryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("weightUnit") private var unit = "kg"
    @State private var value = ""
    @State private var measuredAt = Date()
    @State private var choosingDate = false
    @State private var saving = false
    @State private var error: String?
    @State private var identity = "snoop:" + UUID().uuidString
    @FocusState private var focused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize = 56.0
    var editing: WeightReading?
    private var entry: WeightReading? {
        if let editing { return model.health.rows.first { $0.id == editing.id } ?? editing }
        return WeightReading.preferred(model.health.rows, on: measuredAt)
    }
    private var kg: Double? {
        let separator = Locale.current.decimalSeparator ?? "."
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: separator, with: ".")
        guard let number = Double(normalized) else { return nil }
        let result = unit == "lb" ? number / 2.2046226218 : number
        return result.isFinite && (20...400).contains(result) ? result : nil
    }
    private var rulerValue: Binding<Double> {
        Binding(get: { kg.map { unit == "lb" ? $0 * 2.2046226218 : $0 } ?? (unit == "lb" ? 165 : 75) },
                set: { value = $0.formatted(.number.precision(.fractionLength(1))) })
    }
    var body: some View {
        NavigationStack {
            Group {
                if let row = entry, row.source == "health" {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            MetricValue(display(row.kg), unit: unit, size: 52)
                            Text(row.measuredAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(SnoopStyle.secondary)
                            Text(row.sourceName).font(.headline)
                            Text("Edit this measurement in Apple Health.").font(.subheadline).foregroundStyle(SnoopStyle.secondary)
                        }.padding(SnoopStyle.gutter).frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            Text(entry == nil ? "What did the scale say?" : "Edit your weigh-in")
                                .font(.title2.weight(.semibold)).multilineTextAlignment(.center).padding(.top, 12)
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                TextField("Weight", text: $value).keyboardType(.decimalPad)
                                    .font(.system(size: min(numberSize, 88), weight: .medium)).monospacedDigit()
                                    .multilineTextAlignment(.center).focused($focused).accessibilityLabel("Weight").accessibilityIdentifier("weightInput")
                                    .accessibilityHint("Tap to type a weight")
                                    .frame(maxWidth: 240)
                                Picker("Unit", selection: $unit) { Text("kg").tag("kg"); Text("lb").tag("lb") }
                                    .pickerStyle(.menu).fixedSize().accessibilityLabel("Weight unit")
                            }
                            MeasurementRuler(value: rulerValue, range: unit == "lb" ? 44.1...881.8 : 20...400,
                                             step: 0.1, unit: unit, label: "Weight ruler", onEditing: { focused = false })
                                .accessibilityIdentifier("weightRuler")
                            if entry == nil, let previous = model.health.lastWeight {
                                Text("Previous · \(display(previous.kg)) \(unit) · \(previous.measuredAt.formatted(.dateTime.day().month(.abbreviated)))")
                                    .font(.subheadline).foregroundStyle(SnoopStyle.secondary).multilineTextAlignment(.center)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Button { focused = false; choosingDate.toggle() } label: {
                                    ViewThatFits(in: .horizontal) {
                                        HStack { Text("Measured").foregroundStyle(SnoopStyle.secondary); Spacer(); measuredLabel }
                                        VStack(alignment: .leading, spacing: 8) { Text("Measured").foregroundStyle(SnoopStyle.secondary); measuredLabel }
                                    }.font(.subheadline).frame(minHeight: 44).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityIdentifier("weightMeasuredDate")
                                if choosingDate {
                                    DatePicker("Measured", selection: $measuredAt, in: ...Date()).datePickerStyle(.compact)
                                        .labelsHidden().accessibilityLabel("Measurement date and time")
                                }
                            }.padding(.top, 4)
                            if let error { Text(error).font(.footnote).foregroundStyle(SnoopStyle.unfavourable).accessibilityIdentifier("weightSaveError") }
                        }.padding(.horizontal, SnoopStyle.gutter).padding(.bottom, 20)
                    }
                    .safeAreaInset(edge: .bottom) {
                        Button(action: save) {
                            HStack { if saving { ProgressView() }; Text(entry == nil ? "Save weight" : "Save changes").font(.headline) }
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                        }.buttonStyle(.borderedProminent).disabled(kg == nil || saving).accessibilityIdentifier("saveWeight")
                            .padding(.horizontal, SnoopStyle.gutter).padding(.vertical, 12).background(SnoopStyle.background)
                    }
                }
            }
            .snoopScreen().tint(SnoopStyle.load)
            .navigationTitle(entry?.source == "health" ? "Weight" : entry == nil ? "Today’s weigh-in" : "Edit weight").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(entry?.source == "health" ? "Done" : "Cancel") { dismiss() }.disabled(saving) } }
            .interactiveDismissDisabled(saving)
            .onAppear {
                if let row = entry ?? model.health.lastWeight {
                    value = display(row.kg)
                    if entry != nil { measuredAt = row.measuredAt }
                }
            }
            .onChange(of: entry?.id) { _, _ in
                if let row = entry { value = display(row.kg) }
            }
            .onChange(of: unit) { old, new in
                let formatter = NumberFormatter(); formatter.numberStyle = .decimal
                if let number = formatter.number(from: value)?.doubleValue {
                    value = (old == "kg" && new == "lb" ? number * 2.2046226218 : number / 2.2046226218).formatted(.number.precision(.fractionLength(1)))
                }
            }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
    private var measuredLabel: some View {
        HStack(spacing: 5) {
            Text(Calendar.current.isDateInToday(measuredAt) ? "Today, \(measuredAt.formatted(date: .omitted, time: .shortened))" : measuredAt.formatted(date: .abbreviated, time: .shortened))
            Image(systemName: "chevron.down").font(.caption)
        }.foregroundStyle(SnoopStyle.load)
    }
    private func display(_ kg: Double) -> String { (unit == "lb" ? kg * 2.2046226218 : kg).formatted(.number.precision(.fractionLength(1))) }
    private func save() {
        guard let kg else { return }; saving = true; error = nil
        guard entry?.source != "health" else { saving = false; error = WeightEntryPolicy.Failure.importedReading.localizedDescription; return }
        let row = WeightReading(id: entry?.id ?? identity, measuredAt: editing == nil ? (entry?.measuredAt ?? measuredAt) : measuredAt, kg: kg, version: entry?.version ?? 0)
        Task {
            do { try await model.health.save(row); UINotificationFeedbackGenerator().notificationOccurred(.success); dismiss() }
            catch let failure as WeightEntryPolicy.Failure { self.error = failure.localizedDescription }
            catch { self.error = "Couldn’t save weight. Try again." }
            saving = false
        }
    }
}
