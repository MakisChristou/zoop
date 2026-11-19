import Charts
import SwiftUI

/// The date fields remain the accessible editing path; chart selection is optional.
struct WorkoutWindowChart: View {
    let minutes: [ZoopAPI.Minute]
    let start: Date
    let end: Date
    let split: Date?
    @Binding var selected: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Heart rate").font(.subheadline)
                Spacer()
                if let selected {
                    Text(selected.formatted(date: .omitted, time: .shortened))
                        .font(.caption).monospacedDigit()
                }
            }
            if minutes.contains(where: { $0.hr != nil }), end > start {
                Chart {
                    RectangleMark(xStart: .value("Start", start), xEnd: .value("End", end))
                        .foregroundStyle(ZoopStyle.load.opacity(0.08))
                    ForEach(minutes) { minute in
                        if let hr = minute.hr {
                            PointMark(x: .value("Time", minute.ts), y: .value("Heart rate", hr))
                                .foregroundStyle(ZoopStyle.heartRate).symbolSize(10)
                        }
                    }
                    if let split {
                        RuleMark(x: .value("Split at", split)).foregroundStyle(ZoopStyle.load)
                            .annotation(position: .top) { Text("Split").font(.caption2) }
                    } else if let selected {
                        RuleMark(x: .value("Selected time", selected)).foregroundStyle(ZoopStyle.secondary)
                    }
                }
                .chartXScale(domain: start...end)
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisValueLabel(format: .dateTime.hour().minute()) } }
                .chartXSelection(value: $selected)
                .frame(height: 150)
                .accessibilityLabel("Recorded heart rate during the selected time")
            } else {
                Text("No heart-rate readings in this range")
                    .font(.footnote).foregroundStyle(ZoopStyle.secondary).padding(.vertical, 12)
            }
        }
    }
}
