import SwiftUI
import SnoopHealth

struct HealthBackfillView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var from = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var to = Date()
    @State private var all = false
    @State private var preview: HealthCoordinator.Preview?
    @State private var checking = false
    @State private var error: String?
    @State private var started = false
    private var range: HealthJournal.Range {
        let first = all ? (model.health.earliest ?? from) : Calendar.current.startOfDay(for: from)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: to)) ?? to
        return .init(from: first, to: end)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("All available history", isOn: $all)
                    if !all { DatePicker("From", selection: $from, in: ...to, displayedComponents: .date) }
                    DatePicker("Through", selection: $to, in: ...Date(), displayedComponents: .date)
                }.disabled(started)
                if let preview {
                    Section {
                        LabeledContent("Sleep recordings", value: "\(preview.sleep)")
                        LabeledContent("Workouts", value: "\(preview.workouts)")
                        if model.health.journal.exportSteps { LabeledContent("Days with steps", value: "\(preview.stepDays.count)") }
                        if model.health.journal.exportWeight { LabeledContent("Weigh-ins to Health", value: "\(preview.weights)") }
                        if preview.already > 0 { LabeledContent("Already synced", value: "\(preview.already)") }
                    } header: { Text("Snoop → Apple Health") } footer: { Text("Records still being analysed will follow when ready. Repeating this range won’t duplicate Snoop exports.") }
                }
                if let error = error ?? model.health.error { Section { Text(error).foregroundStyle(SnoopStyle.unfavourable) } }
                Section {
                    if started {
                        Label(model.health.status, systemImage: model.health.busy ? "arrow.triangle.2.circlepath" : "checkmark")
                        if model.health.busy { ProgressView(); Button("Pause sync") { model.health.pause(true) } }
                        else if model.health.journal.paused { Button("Resume sync") { model.health.pause(false) } }
                        else if model.health.error != nil { Button("Retry sync") { model.health.checkSoon() } }
                    } else if preview != nil {
                        Button("Export selected history") {
                            let selected = range; started = true
                            Task { do { try await model.health.backfill(selected) } catch { self.error = error.localizedDescription; started = false } }
                        }
                    } else {
                        Button("Preview history") {
                            let selected = range; checking = true; error = nil
                            Task { do { preview = try await model.health.preview(selected) } catch { self.error = error.localizedDescription }; checking = false }
                        }.disabled(checking || model.health.busy)
                        if checking { ProgressView().accessibilityLabel("Preparing history preview") }
                    }
                }
            }
            .scrollContentBackground(.hidden).snoopScreen().tint(SnoopStyle.load)
            .navigationTitle("Export Snoop history").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: from) { _, _ in preview = nil }
            .onChange(of: to) { _, _ in preview = nil }
            .onChange(of: all) { _, _ in preview = nil }
        }
    }
}
