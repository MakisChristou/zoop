import Charts
import SwiftUI

/// Both Today and Steps use the server's full-resolution walking count per hour.
struct HourlyStepsChart: View {
    let hours: [Int]
    let day: Date
    var compact = false
    var interactive = false
    @Binding var selection: Double?

    init(hours: [Int], day: Date, compact: Bool = false, interactive: Bool = false,
         selection: Binding<Double?> = .constant(nil)) {
        self.hours = hours
        self.day = day
        self.compact = compact
        self.interactive = interactive
        _selection = selection
    }

    var body: some View {
        if interactive {
            chart.chartXSelection(value: $selection)
        } else { chart }
    }

    private var chart: some View {
        Chart(Array(hours.prefix(24).enumerated()), id: \.offset) { hour, steps in
            BarMark(x: .value("Hour", Double(hour) + 0.5), y: .value("Steps", steps))
                .foregroundStyle(ZoopStyle.steps.opacity(selection == nil || Int(selection ?? -1) == hour ? 1 : 0.35))
                .cornerRadius(2)
                .accessibilityLabel(Self.hourLabel(hour, on: day))
                .accessibilityValue("\(steps.formatted()) steps")
        }
        .chartXScale(domain: 0...24)
        .chartYScale(domain: 0...max(hours.max() ?? 0, 100))
        .chartXAxis {
            AxisMarks(values: [0, 12, 23]) { value in
                AxisValueLabel(anchor: value.index == 0 ? .topLeading : value.index == 2 ? .topTrailing : .top) {
                    Text(Self.hourLabel(value.as(Int.self) ?? 0, on: day))
                        .font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                }
            }
        }
        .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(ZoopStyle.chartGrid)
                    AxisValueLabel().font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary)
                }
        }
        .chartPlotStyle { $0.padding(.top, 4) }
        .accessibilityLabel("Steps by hour")
    }

    static func hourLabel(_ hour: Int, on day: Date) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        return date.formatted(.dateTime.hour())
    }
}
