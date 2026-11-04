import SwiftUI
import Charts
import SnoopData

struct TrendWeekdayPattern: View {
    let metric: TrendMetric
    let series: TrendSeries
    let calendar: Calendar
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Typical \(metric.rawValue.lowercased()) by weekday").font(.subheadline.weight(.medium))
            Chart(0..<7, id: \.self) { offset in
                let weekday = (offset + calendar.firstWeekday - 1) % 7 + 1
                if let value = series.weekdays[weekday] {
                    BarMark(x: .value("Weekday", offset), y: .value(metric.rawValue, value))
                        .foregroundStyle(metric.color)
                        .accessibilityLabel(calendar.weekdaySymbols[weekday - 1])
                        .accessibilityValue(metric.formatted(value) + " " + metric.readoutUnit)
                }
            }
            .chartXAxis { AxisMarks(values: Array(0..<7)) { value in
                AxisValueLabel { if let offset = value.as(Int.self) { Text(calendar.shortStandaloneWeekdaySymbols[(offset + calendar.firstWeekday - 1) % 7]) } }
            } }
            .chartYAxis(.hidden).frame(height: 100)
            Text("Past 8 weeks").font(.caption).foregroundStyle(SnoopStyle.secondary)
        }.accessibilityIdentifier("weekdayPattern")
    }
}
