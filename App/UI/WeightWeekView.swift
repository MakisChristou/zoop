import SwiftUI
import ZoopHealth

struct WeightWeekView: View {
    let summary: WeightCheckInSummary
    var showsCount = true
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !typeSize.isAccessibilitySize {
                HStack {
                    ForEach(summary.days) { day in
                        VStack(spacing: 6) {
                            ZStack {
                                Circle().fill(day.recorded ? ZoopStyle.favourable : ZoopStyle.track.opacity(0.65))
                                if day.recorded {
                                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(ZoopStyle.background)
                                } else {
                                    Text(day.date, format: .dateTime.day()).font(.caption2).foregroundStyle(ZoopStyle.secondary)
                                }
                            }.frame(width: 25, height: 25)
                                .overlay { if day.isToday && !day.recorded { Circle().stroke(ZoopStyle.load, lineWidth: 1).padding(-3) } }
                            Text(day.date, format: .dateTime.weekday(.narrow)).font(.caption2).foregroundStyle(ZoopStyle.secondary)
                        }.frame(maxWidth: .infinity)
                    }
                }.accessibilityHidden(true)
            }
            if showsCount || typeSize.isAccessibilitySize { Text("\(summary.count) \(summary.count == 1 ? "weigh-in" : "weigh-ins") this week")
                .font(.caption).foregroundStyle(ZoopStyle.secondary).accessibilityIdentifier("weightWeekCompletion") }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week’s weigh-ins")
        .accessibilityValue("\(summary.count) of 7 days completed")
        .accessibilityIdentifier("weightWeekCircles")
    }
}
