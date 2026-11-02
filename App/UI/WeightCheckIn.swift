import Charts
import SwiftUI
import SnoopHealth

/// A lightweight entry point to weight, independent of whether today has a reading.
struct WeightCheckIn: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicType
    @AppStorage("weightUnit") private var unit = "kg"
    private var rows: [WeightReading] { model.health.rows }
    private var latest: WeightReading? { rows.first.flatMap { WeightReading.preferred(rows, on: $0.measuredAt) } }
    private var points: [WeightTrend.Point] {
        let start = Calendar.current.date(byAdding: .day, value: -36, to: Date()) ?? Date()
        return WeightTrend(rows.filter { $0.measuredAt >= start }).points.filter {
            $0.date >= (Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date())
        }
    }
    private func display(_ kg: Double) -> Double { unit == "lb" ? kg * 2.2046226218 : kg }

    var body: some View {
        NavigationLink { WeightView() } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Weight").font(.subheadline.weight(.semibold))
                    if let latest {
                        (Text(display(latest.kg).formatted(.number.precision(.fractionLength(1))))
                            .font(.title2.weight(.semibold)) + Text(" \(unit)").font(.subheadline))
                            .monospacedDigit()
                        Text(Calendar.current.isDateInToday(latest.measuredAt) ? "Today" : latest.measuredAt.formatted(Calendar.current.component(.year, from: latest.measuredAt) == Calendar.current.component(.year, from: Date()) ? .dateTime.day().month(.abbreviated) : .dateTime.day().month(.abbreviated).year()))
                            .font(.caption).foregroundStyle(SnoopStyle.secondary)
                    } else {
                        Text("Log a weigh-in or import history").font(.subheadline)
                            .foregroundStyle(SnoopStyle.secondary)
                    }
                }
                Spacer(minLength: 0)
                if points.count > 1 && !dynamicType.isAccessibilitySize {
                    Chart(points) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Weight", display(point.kg)), series: .value("Segment", point.segment))
                            .foregroundStyle(SnoopStyle.load).lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    .chartXScale(domain: points.first!.date...max(Date(), points.last!.date))
                    .chartYScale(domain: .automatic(includesZero: false)).chartXAxis(.hidden).chartYAxis(.hidden)
                    .frame(width: 104, height: 42).accessibilityHidden(true)
                }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                    .foregroundStyle(SnoopStyle.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading).snoopCard()
            .contentShape(RoundedRectangle(cornerRadius: SnoopStyle.radius))
        }
        .buttonStyle(PressableCardStyle()).accessibilityIdentifier("todayWeight")
        .accessibilityElement(children: .combine).accessibilityHint("Opens your weight chart and history")
    }
}
