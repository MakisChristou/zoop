import SwiftUI
import SnoopHealth

struct WeightWeekView: View {
    let summary: WeightCheckInSummary
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !typeSize.isAccessibilitySize {
                HStack {
                    ForEach(summary.days) { day in
                        VStack(spacing: 6) {
                            ZStack {
                                Circle().fill(day.recorded ? SnoopStyle.favourable : SnoopStyle.surface)
                                if day.recorded {
                                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(SnoopStyle.background)
                                } else {
                                    Text(day.date, format: .dateTime.day()).font(.caption2).foregroundStyle(SnoopStyle.secondary)
                                }
                            }.frame(width: 25, height: 25)
                                .overlay { if day.isToday && !day.recorded { Circle().stroke(SnoopStyle.load, lineWidth: 1).padding(-3) } }
                            Text(day.date, format: .dateTime.weekday(.narrow)).font(.caption2).foregroundStyle(SnoopStyle.secondary)
                        }.frame(maxWidth: .infinity)
                    }
                }.accessibilityHidden(true)
            }
            Text("\(summary.count) \(summary.count == 1 ? "weigh-in" : "weigh-ins") this week")
                .font(.caption).foregroundStyle(SnoopStyle.secondary).accessibilityIdentifier("weightWeekCompletion")
        }
    }
}
