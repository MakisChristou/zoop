import SwiftUI
import SnoopHealth

struct WeightView: View {
    enum Period: String, CaseIterable, Identifiable {
        case week = "7D", month = "1M", quarter = "3M", all = "All"
        var id: Self { self }
        var days: Int? { switch self { case .week: 7; case .month: 30; case .quarter: 90; case .all: nil } }
    }
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("weightUnit") private var unit = "kg"
    @State private var period: Period = .month
    @State private var trend = WeightTrend([])
    @State private var choseInitialRange = false
    @State private var adding = false
    @State private var importing = false
    @State private var showAll = false
    @State private var editing: WeightReading?
    @State private var removing: WeightReading?
    @State private var saveError: String?
    private var rows: [WeightReading] { model.health.rows }
    private var latest: WeightReading? { trend.points.last?.reading }
    private var range: ClosedRange<Date> {
        let cal = Calendar.current, today = Calendar.current.startOfDay(for: Date())
        let start = period.days.flatMap { cal.date(byAdding: .day, value: -($0 - 1), to: today) }
            ?? trend.points.first?.day ?? today
        let last = period == .all ? (trend.points.last?.day ?? today) : today
        return start...(cal.date(byAdding: .day, value: 1, to: last) ?? Date())
    }
    private var visiblePoints: [WeightTrend.Point] { trend.points.filter { range.contains($0.date) } }
    private var visibleReadings: [WeightReading] { rows.filter { range.contains($0.measuredAt) && $0.measuredAt <= Date() } }
    private func display(_ kg: Double) -> Double { unit == "lb" ? kg * 2.2046226218 : kg }
    private func value(_ kg: Double) -> String { display(kg).formatted(.number.precision(.fractionLength(1))) + " " + unit }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let latest { summary(latest); trendCard } else { empty }
                if !model.health.journal.pendingWeights.isEmpty {
                    Label("Saved on this iPhone · waiting to sync", systemImage: "icloud.and.arrow.up")
                        .font(.footnote).foregroundStyle(SnoopStyle.secondary)
                }
                if let error = saveError ?? model.health.error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).font(.footnote).foregroundStyle(SnoopStyle.unfavourable)
                        Button("Retry sync") { saveError = nil; model.health.checkSoon() }.disabled(model.health.busy)
                    }.snoopCard()
                }
                if !rows.isEmpty { history; importLink }
            }.padding(.horizontal, SnoopStyle.gutter).padding(.vertical, 20)
        }
        .snoopScreen().tint(SnoopStyle.load)
        .navigationTitle("Weight").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { options } }
        .onChange(of: rows, initial: true) { _, rows in
            trend = WeightTrend(rows)
            if !choseInitialRange, let latest = trend.points.last {
                if let monthAgo = Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: Date())), latest.date < monthAgo { period = .all }
                choseInitialRange = true
            }
        }
        .refreshable { await model.health.sync() }
        .sheet(isPresented: $adding) { WeightEntryView() }
        .sheet(isPresented: $importing) { WeightImportView() }
        .sheet(item: $editing) { WeightEntryView(editing: $0) }
        .confirmationDialog("Delete this weigh-in?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Delete weigh-in", role: .destructive) {
                guard var row = removing else { return }; row.removed = true
                Task { do { try await model.health.save(row) } catch { saveError = "Couldn’t delete this weigh-in. Try again." } }; removing = nil
            }
        } message: { Text("This removes the Snoop measurement and its Snoop export. Other apps’ records stay unchanged.") }
    }
    private func summary(_ row: WeightReading) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack { latestLabel.fixedSize(); Spacer(minLength: 16); logButton }
                VStack(alignment: .leading, spacing: 12) { latestLabel; logButton }
            }
            (Text(display(row.kg).formatted(.number.precision(.fractionLength(1)))).font(.largeTitle.weight(.semibold))
             + Text(" \(unit)").font(.title3).foregroundColor(SnoopStyle.secondary)).monospacedDigit()
            Text("\(row.measuredAt.formatted(date: .abbreviated, time: .shortened)) · \(row.sourceName)")
                .font(.subheadline).foregroundStyle(SnoopStyle.secondary)
        }
    }
    private var latestLabel: some View {
        Text("Latest weigh-in").font(.subheadline.weight(.medium)).foregroundStyle(SnoopStyle.secondary)
    }
    private var logButton: some View {
        Button { adding = true } label: {
            Text("Log weight").font(.subheadline.weight(.semibold)).fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
        }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).accessibilityIdentifier("logWeight")
    }
    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Picker("Chart range", selection: $period) {
                ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            if visibleReadings.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("No weigh-ins in this range").font(.headline)
                    Text("Your older measurements are still in your history.").font(.subheadline).foregroundStyle(SnoopStyle.secondary)
                    Button("Show all history") { period = .all }
                }.frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
            } else {
                WeightTrendChart(points: visiblePoints, readings: visibleReadings, range: range, unit: unit)
                Divider().overlay(SnoopStyle.separator)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) { average; Spacer(minLength: 0); change }
                    VStack(alignment: .leading, spacing: 16) { average; change }
                }
            }
        }.snoopCard()
    }
    private var average: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Latest 7-day average").font(.caption).foregroundStyle(SnoopStyle.secondary)
            Text(visiblePoints.last.map { value($0.average) } ?? "—").font(.title3.weight(.semibold)).monospacedDigit()
        }
    }
    private var change: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Trend change · \(period.rawValue)").font(.caption).foregroundStyle(SnoopStyle.secondary)
            if visiblePoints.count > 1, let first = visiblePoints.first, let last = visiblePoints.last {
                let rounded = (display(last.average - first.average) * 10).rounded() / 10
                let delta = rounded == 0 ? 0.0 : rounded
                Text((delta > 0 ? "+" : "") + delta.formatted(.number.precision(.fractionLength(1))) + " " + unit)
                    .font(.title3.weight(.semibold)).monospacedDigit()
            } else { Text("—").font(.title3.weight(.semibold)) }
        }
    }
    private var empty: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "scalemass").font(.largeTitle).foregroundStyle(SnoopStyle.secondary)
            Text("Your weight, over time").font(.title2.weight(.semibold))
            Text("Bring in your Apple Health weigh-ins, or log your first measurement.")
                .foregroundStyle(SnoopStyle.secondary)
            Button { importing = true } label: {
                Text("Import weight history").foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            }.buttonStyle(.borderedProminent)
            Button("Log weight") { adding = true }.accessibilityIdentifier("logWeight")
        }.frame(maxWidth: .infinity, alignment: .leading).snoopCard()
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent weigh-ins").font(.headline)
                Spacer()
                if rows.count > 3 { Button(showAll ? "Show less" : "See all") { showAll.toggle() }.font(.subheadline) }
            }
            LazyVStack(spacing: 0) {
                ForEach(Array((showAll ? rows : Array(rows.prefix(3))).enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().overlay(SnoopStyle.separator).padding(.vertical, 12) }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { readingDate(row); Spacer(minLength: 8); readingValue(row) }
                        VStack(alignment: .leading, spacing: 8) { readingDate(row); readingValue(row) }
                    }
                }
            }.snoopCard()
        }
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
    private var importLink: some View {
        Button { importing = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "heart").foregroundStyle(SnoopStyle.load)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Import weight history").font(.subheadline.weight(.semibold))
                    Text("From Apple Health").font(.caption).foregroundStyle(SnoopStyle.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(SnoopStyle.secondary)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }.buttonStyle(.plain).accessibilityIdentifier("weightImportHistory")
    }
    private var options: some View {
        Menu {
            Picker("Unit", selection: $unit) { Text("Kilograms").tag("kg"); Text("Pounds").tag("lb") }
            Toggle("Remind me after waking", isOn: Binding(get: { model.health.canRemind }, set: { model.health.setReminder($0) }))
            Button("Import weight history", systemImage: "heart") { importing = true }
        } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }
            .accessibilityLabel("Weight options")
    }
}
