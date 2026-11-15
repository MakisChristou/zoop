import SwiftUI
import SnoopHealth

struct WeightView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("weightUnit") private var unit = "kg"
    @State private var adding = false
    @State private var editing: WeightReading?
    @State private var importing = false
    @State private var options = false
    private var rows: [WeightReading] { model.health.rows }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if model.weeklyWeight.goal?.active == true, let summary = model.weeklyWeight.summary {
                    NavigationLink { WeeklyWeightView() } label: { WeeklyWeightCard(summary: summary, unit: unit) }.buttonStyle(.plain).accessibilityIdentifier("openWeeklyWeight")
                }
                if rows.isEmpty { empty } else {
                    WeightTrendChart(readings: rows, unit: unit, target: CutTargets.weight(goal: model.weeklyWeight.goal, summary: model.weeklyWeight.summary), logWeight: { adding = true }, openReading: { editing = $0 })
                    VStack(spacing: 4) {
                        HStack {
                            Text("Recent weigh-ins").font(.headline)
                            Spacer()
                            NavigationLink { WeightHistoryView() } label: { Text("View all").font(.subheadline).frame(minHeight: 44) }
                                .accessibilityIdentifier("weightHistory")
                        }
                        ForEach(Array(rows.prefix(3))) { row in
                            Button { editing = row } label: {
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 12) { readingDate(row); Spacer(); readingValue(row) }
                                    VStack(alignment: .leading, spacing: 8) { readingDate(row); readingValue(row) }.frame(maxWidth: .infinity, alignment: .leading)
                                }.padding(.vertical, 10).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            if row.id != rows.prefix(3).last?.id { Divider().overlay(SnoopStyle.separator) }
                        }
                    }
                    DisclosureGroup {
                        WeightWeekView(summary: WeightCheckInSummary(rows)).padding(.vertical, 8)
                    } label: {
                        Text("This week’s check-ins").font(.subheadline).frame(minHeight: 44)
                    }.tint(SnoopStyle.secondary)
                    Button { importing = true } label: {
                        HStack {
                            Label("Import weight history", systemImage: "heart")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }.font(.subheadline).frame(minHeight: 44)
                    }.accessibilityIdentifier("openWeightImport")
                }
                if !model.health.journal.pendingWeights.isEmpty {
                    Label("Saved on this iPhone · waiting to sync", systemImage: "icloud.and.arrow.up").font(.footnote).foregroundStyle(SnoopStyle.secondary)
                }
                if let error = model.health.error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).font(.footnote).foregroundStyle(SnoopStyle.unfavourable)
                        Button("Retry sync") { model.health.checkSoon() }.disabled(model.health.busy)
                    }.snoopCard()
                }
            }.padding(.horizontal, SnoopStyle.gutter).padding(.vertical, 16)
        }.accessibilityIdentifier("weightScroll").snoopScreen().tint(SnoopStyle.load)
        .navigationTitle("Weight").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { options = true } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Weight options")
            }
        }
        .refreshable { await model.health.sync() }
        .sheet(isPresented: $adding) { WeightEntryView() }
        .sheet(item: $editing) { WeightEntryView(editing: $0) }
        .sheet(isPresented: $importing) { WeightImportView() }
        .sheet(isPresented: $options) { WeightOptionsView() }
    }
    private func readingDate(_ row: WeightReading) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Calendar.current.isDateInToday(row.measuredAt) ? "Today" : Calendar.current.isDateInYesterday(row.measuredAt) ? "Yesterday" : row.measuredAt.formatted(.dateTime.day().month(.abbreviated).year())).font(.subheadline)
            Text("\(row.measuredAt.formatted(date: .omitted, time: .shortened)) · \(row.source == "health" ? "Apple Health" : row.sourceName)")
                .font(.caption).foregroundStyle(SnoopStyle.secondary)
        }
    }
    private func readingValue(_ row: WeightReading) -> some View {
        Text("\((unit == "lb" ? row.kg * 2.2046226218 : row.kg).formatted(.number.precision(.fractionLength(1)))) \(unit)")
            .font(.headline).monospacedDigit().fixedSize()
    }
    private var empty: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "chart.xyaxis.line").font(.largeTitle).foregroundStyle(SnoopStyle.load)
            Text("No weigh-ins yet").font(.title.weight(.semibold))
            Button { adding = true } label: {
                Text("Log your weight").font(.headline).frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            }.buttonStyle(.borderedProminent).accessibilityIdentifier("logWeight")
            Button("Import weight history") { importing = true }.frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.bordered)
        }.padding(.vertical, 20)
    }
}
