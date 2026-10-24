import Charts
import SwiftUI

/// Night-over-night trends from the server's analysed nights. One point per night;
/// the range widens as history builds.
struct TrendsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var nights: [SnoopAPI.Night] = []
    @State private var error: String?
    @State private var range: Range = .month

    enum Range: String, CaseIterable, Identifiable {
        case week = "W", month = "M", quarter = "3M", all = "ALL"
        var id: String { rawValue }
        var limit: Int {
            switch self {
            case .week: 7
            case .month: 30
            case .quarter: 90
            case .all: 365
            }
        }
    }

    private typealias Point = TrendsViewPoint

    var body: some View {
        NavigationStack {
            Group {
                if nights.isEmpty {
                    ContentUnavailableView {
                        Label("Trends need history", systemImage: "chart.line.uptrend.xyaxis")
                    } description: {
                        Text(error ?? "Resting heart rate, HRV and sleep trends appear once the server has analysed a few nights.")
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Picker("Range", selection: $range) {
                                ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            if nights.count < 3 {
                                Text("Longer ranges unlock as more nights build up.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            TrendCard(title: "Asleep", unit: "h", points: points { Double($0.metrics.window.asleepS) / 3600 }, decimals: 1, color: .indigo)
                            TrendCard(title: "Resting HR", unit: "bpm", points: points { $0.metrics.physiology.restingHr }, decimals: 0, color: .red)
                            TrendCard(title: "HRV", unit: "ms", points: points { $0.metrics.physiology.hrvRmssdMs }, decimals: 0, color: .teal)
                            TrendCard(title: "Breathing", unit: "/min", points: points { $0.metrics.physiology.respiratoryRate }, decimals: 1, color: .mint)
                            TrendCard(title: "Skin temp", unit: "°C", points: points { $0.metrics.physiology.skinTempC }, decimals: 1, color: .orange)
                            TrendCard(title: "Efficiency", unit: "%", points: points { $0.metrics.window.efficiency * 100 }, decimals: 0, color: .purple)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Trends")
            .refreshable { await load() }
            .task { await load() }
            .onChange(of: range) { _, _ in Task { await load() } }
        }
    }

    private func points(_ value: (SnoopAPI.Night) -> Double?) -> [Point] {
        nights.compactMap { night in
            value(night).map { Point(date: night.endTs, value: $0) }
        }
        .sorted { $0.date < $1.date }
    }

    private func load() async {
        guard !model.strap.serial.isEmpty else {
            error = "Waiting for the strap's serial number."
            return
        }
        do {
            nights = try await SnoopAPI.nights(deviceId: model.strap.serial, limit: range.limit)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct TrendCard: View {
    let title: String
    let unit: String
    let points: [Point]
    let decimals: Int
    let color: Color

    typealias Point = TrendsViewPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                if let last = points.last {
                    Text(format(last.value)).font(.title3.weight(.semibold)).monospacedDigit()
                    Text(unit).font(.footnote).foregroundStyle(.secondary)
                }
            }
            if points.count >= 2 {
                Chart(points) { p in
                    LineMark(x: .value("Night", p.date), y: .value(title, p.value))
                        .foregroundStyle(color)
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Night", p.date), y: .value(title, p.value))
                        .foregroundStyle(color)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                .frame(height: 110)
                HStack {
                    stat("min", points.map(\.value).min())
                    Spacer()
                    stat("avg", points.map(\.value).reduce(0, +) / Double(points.count))
                    Spacer()
                    stat("max", points.map(\.value).max())
                }
            } else if let only = points.first {
                Text("One night so far, \(only.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))). A line needs two.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("No values yet.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }

    private func stat(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.tertiary).textCase(.uppercase)
            Text(value.map(format) ?? "—").font(.subheadline.weight(.medium)).monospacedDigit()
        }
    }

    private func format(_ v: Double) -> String {
        String(format: "%.\(decimals)f", v)
    }
}

/// Shared point type for the trend cards.
struct TrendsViewPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}
