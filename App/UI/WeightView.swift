import Charts
import SwiftUI
import SnoopHealth

struct WeightView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("weightUnit") private var unit = "kg"
    @State private var adding = false
    @State private var syncingHistory = false
    @State private var editing: WeightReading?
    @State private var removing: WeightReading?
    @State private var saveError: String?
    private var rows: [WeightReading] { model.health.rows }
    private var latest: WeightReading? { rows.first.flatMap { WeightReading.preferred(rows, on: $0.measuredAt) } }
    private var chartRange: ClosedRange<Date> {
        let day = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .day, value: -29, to: day)!...Calendar.current.date(byAdding: .day, value: 1, to: day)!
    }
    private func display(_ kg: Double) -> Double { unit == "lb" ? kg * 2.2046226218 : kg }
    @ViewBuilder private var emptyHistory: some View {
        if model.health.connected && model.health.journal.importWeight {
            Text(model.health.journal.ranges.isEmpty
                 ? "Apple Health is connected. Sync older history to bring in past weigh-ins."
                 : "No weights were returned for the selected dates. Try a wider range or check weight access in Apple Health.")
                .font(.subheadline).foregroundStyle(SnoopStyle.secondary)
            if model.health.busy { ProgressView("Syncing…").font(.subheadline) }
            Button { syncingHistory = true } label: {
                Text("Sync older history").foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            }.buttonStyle(.borderedProminent).disabled(model.health.busy)
                .accessibilityIdentifier("weightSyncHistory")
            Button("Log weight") { adding = true }.buttonStyle(.bordered)
        } else {
            Text(model.health.connected ? "Turn on weight imports to bring in Apple Health weigh-ins." : "Log a weigh-in or bring in your Apple Health history.")
                .font(.subheadline).foregroundStyle(SnoopStyle.secondary)
            NavigationLink(model.health.connected ? "Apple Health settings" : "Connect Apple Health") { AppleHealthView() }
            Button { adding = true } label: {
                Text("Log weight").foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            }.buttonStyle(.borderedProminent)
        }
    }
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(latest.map { display($0.kg).formatted(.number.precision(.fractionLength(1))) + " " + unit } ?? "No weigh-ins yet")
                        .font(.largeTitle.weight(.semibold)).monospacedDigit()
                    if let average = WeightReading.trend(rows, ending: Date()) {
                        Text("7-day average · \(display(average).formatted(.number.precision(.fractionLength(1)))) \(unit)").font(.subheadline).foregroundStyle(SnoopStyle.secondary)
                    }
                    if !rows.isEmpty {
                        Chart(rows.filter { $0.measuredAt > chartRange.lowerBound }) { row in
                            PointMark(x: .value("Date", row.measuredAt), y: .value("Weight", display(row.kg))).foregroundStyle(SnoopStyle.load)
                        }.chartYScale(domain: .automatic(includesZero: false))
                            .chartXScale(domain: chartRange)
                            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                                AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            } }.frame(height: 160)
                            .accessibilityLabel("Weight measurements over the last 30 days")
                    }
                    if rows.isEmpty {
                        emptyHistory
                    } else {
                        Button { adding = true } label: {
                            Text("Log weight").foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                        }.buttonStyle(.borderedProminent)
                    }
                }.padding(.vertical, 8)
            }.listRowBackground(SnoopStyle.surface)
            Section {
                Toggle("Remind me after waking", isOn: Binding(get: { model.health.canRemind }, set: { model.health.setReminder($0) }))
                Picker("Unit", selection: $unit) { Text("Kilograms").tag("kg"); Text("Pounds").tag("lb") }
            } footer: { Text("After confirmed wake-up, unless a weight is already recorded. Timing depends on syncing.") }
                .listRowBackground(SnoopStyle.surface)
            if !model.health.journal.pendingWeights.isEmpty {
                Section { Label("Saved on this iPhone · waiting to sync", systemImage: "icloud.and.arrow.up") }
            }
            if let error = saveError ?? model.health.error { Section { Text(error).font(.footnote); Button("Retry sync") { model.health.checkSoon() } } }
            if !rows.isEmpty {
                Section("History") {
                    ForEach(rows) { row in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.measuredAt.formatted(date: .abbreviated, time: .shortened))
                                Text(row.sourceName).font(.caption).foregroundStyle(SnoopStyle.secondary)
                            }
                            Spacer()
                            Text("\(display(row.kg).formatted(.number.precision(.fractionLength(1)))) \(unit)").monospacedDigit()
                            if row.source == "snoop" {
                                Menu { Button("Edit weight") { editing = row }; Button("Delete weigh-in", role: .destructive) { removing = row } } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Weigh-in actions")
                            }
                        }
                    }
                }.listRowBackground(SnoopStyle.surface)
            }
        }
        .scrollContentBackground(.hidden).snoopScreen().tint(SnoopStyle.load)
        .navigationTitle("Weight").navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.health.sync() }
        .sheet(isPresented: $adding) { WeightEntryView() }
        .sheet(isPresented: $syncingHistory) { HealthBackfillView() }
        .sheet(item: $editing) { WeightEntryView(editing: $0) }
        .confirmationDialog("Delete this weigh-in?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Delete weigh-in", role: .destructive) {
                guard var row = removing else { return }; row.removed = true
                Task { do { try await model.health.save(row) } catch { saveError = "Couldn’t delete this weigh-in. Try again." } }; removing = nil
            }
        } message: { Text("This removes the Snoop measurement and its Snoop export. Other apps’ records stay unchanged.") }
    }
}
