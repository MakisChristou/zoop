import SwiftUI
import SnoopHealth

struct WeightEntryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("weightUnit") private var unit = "kg"
    @State private var value = ""
    @State private var measuredAt = Date()
    @State private var saving = false
    @State private var error: String?
    @State private var identity = "snoop:" + UUID().uuidString
    var editing: WeightReading?
    private var kg: Double? {
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal
        guard let number = formatter.number(from: value)?.doubleValue else { return nil }
        let result = unit == "lb" ? number / 2.2046226218 : number
        return result.isFinite && (20...400).contains(result) ? result : nil
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Weight", text: $value).keyboardType(.decimalPad).font(.largeTitle.weight(.semibold)).monospacedDigit()
                            .accessibilityIdentifier("weightInput")
                        Picker("Unit", selection: $unit) { Text("kg").tag("kg"); Text("lb").tag("lb") }.fixedSize()
                    }
                    DatePicker("Measured", selection: $measuredAt, in: ...Date())
                } footer: { Text("Enter an actual weigh-in. Missing days stay empty.") }
                if let error { Section { Text(error).foregroundStyle(SnoopStyle.unfavourable) } }
                Section {
                    Button("Save weight") {
                        guard let kg else { return }; saving = true; error = nil
                        let row = WeightReading(id: editing?.id ?? identity, measuredAt: measuredAt, kg: kg, version: editing?.version ?? 0)
                        Task { do { try await model.health.save(row); dismiss() } catch { self.error = "Couldn’t save weight. Try again." }; saving = false }
                    }.disabled(kg == nil || saving).accessibilityIdentifier("saveWeight")
                    if saving { ProgressView() }
                }
            }
            .scrollContentBackground(.hidden).snoopScreen().tint(SnoopStyle.load)
            .navigationTitle(editing == nil ? "Log weight" : "Edit weight").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                if let row = editing ?? model.health.lastWeight {
                    value = (unit == "lb" ? row.kg * 2.2046226218 : row.kg).formatted(.number.precision(.fractionLength(1)))
                    if editing != nil { measuredAt = row.measuredAt }
                }
            }
            .onChange(of: unit) { old, new in
                let formatter = NumberFormatter(); formatter.numberStyle = .decimal
                if let number = formatter.number(from: value)?.doubleValue {
                    value = (old == "kg" && new == "lb" ? number * 2.2046226218 : number / 2.2046226218).formatted(.number.precision(.fractionLength(1)))
                }
            }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}
