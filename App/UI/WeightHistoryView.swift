import SwiftUI
import SnoopHealth

struct WeightHistoryView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("weightUnit") private var unit = "kg"
    @State private var editing: WeightReading?
    @State private var removing: WeightReading?
    @State private var saveError: String?
    private func value(_ kg: Double) -> String {
        (unit == "lb" ? kg * 2.2046226218 : kg).formatted(.number.precision(.fractionLength(1))) + " " + unit
    }
    var body: some View {
        List {
            if let saveError { Text(saveError).foregroundStyle(SnoopStyle.unfavourable) }
            ForEach(model.health.rows) { row in
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { readingDate(row); Spacer(minLength: 8); readingValue(row) }
                    VStack(alignment: .leading, spacing: 8) { readingDate(row); readingValue(row) }
                }.padding(.vertical, 6).listRowBackground(SnoopStyle.surface)
            }
        }
        .scrollContentBackground(.hidden).snoopScreen().tint(SnoopStyle.load)
        .navigationTitle("All weigh-ins").navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.health.sync() }
        .sheet(item: $editing) { WeightEntryView(editing: $0) }
        .confirmationDialog("Delete this weigh-in?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Delete weigh-in", role: .destructive) {
                guard var row = removing else { return }; row.removed = true; saveError = nil
                Task { do { try await model.health.save(row) } catch { saveError = "Couldn’t delete this weigh-in. Try again." } }; removing = nil
            }
        } message: { Text("This removes the Snoop measurement and its Snoop export. Other apps’ records stay unchanged.") }
    }
    private func readingDate(_ row: WeightReading) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.measuredAt.formatted(date: .abbreviated, time: .omitted)).font(.subheadline.weight(.medium))
            Text("\(row.measuredAt.formatted(date: .omitted, time: .shortened)) · \(row.sourceName)")
                .font(.caption).foregroundStyle(SnoopStyle.secondary)
        }.fixedSize(horizontal: false, vertical: true)
    }
    private func readingValue(_ row: WeightReading) -> some View {
        HStack(spacing: 0) {
            Text(value(row.kg)).font(.headline).monospacedDigit().fixedSize()
            if row.source == "snoop" {
                Menu {
                    Button("Edit weight") { editing = row }
                    Button("Delete weigh-in", role: .destructive) { removing = row }
                } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Weigh-in actions for \(row.measuredAt.formatted(date: .abbreviated, time: .shortened))")
            }
        }
    }

}
