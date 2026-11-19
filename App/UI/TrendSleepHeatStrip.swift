import SwiftUI

/// Eight weeks remain visible; recorded days open their actual sleep summary.
struct TrendSleepHeatStrip: View {
    let byDay: [Date: Double]
    let today: Date
    let calendar: Calendar
    var selected: Date?
    let open: (Date) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    private let weeks = 8
    private var start: Date { calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: calendar.dateInterval(of: .weekOfYear, for: today)!.start)! }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())
            layout {
                Text("Sleep, last 8 weeks").font(.subheadline.weight(.medium))
                if !typeSize.isAccessibilitySize { Spacer() }
                Text("<5h – 8h+").font(.caption2).foregroundStyle(ZoopStyle.secondary)
            }
            HStack(spacing: 4) {
                Color.clear.frame(width: 28, height: 1)
                ForEach(0..<7, id: \.self) { col in
                    Text(calendar.veryShortStandaloneWeekdaySymbols[(col + calendar.firstWeekday - 1) % 7])
                        .font(.caption2).foregroundStyle(ZoopStyle.secondary).frame(maxWidth: .infinity)
                }
            }.accessibilityHidden(true).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            VStack(spacing: 4) {
                ForEach(0..<weeks, id: \.self) { row in
                    HStack(spacing: 4) {
                        let date = calendar.date(byAdding: .day, value: row * 7, to: start)!
                        Text(date.formatted(.dateTime.day().month(.abbreviated)))
                            .font(.system(size: 10)).foregroundStyle(ZoopStyle.secondary).frame(width: 28)
                            .accessibilityHidden(true)
                        ForEach(0..<7, id: \.self) { col in cell(calendar.date(byAdding: .day, value: row * 7 + col, to: start)!) }
                    }
                }
            }
        }.zoopCard()
    }
    private func cell(_ date: Date) -> some View {
        let value = byDay[date]
        let future = date > today
        let opacity = value.map { 0.15 + min(max(($0 - 4) / 4.5, 0), 1) * 0.8 } ?? 0.08
        return Button { open(date) } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(future ? .clear : value == nil ? ZoopStyle.secondary.opacity(opacity) : ZoopStyle.sleep.opacity(opacity))
                .overlay { if let selected, calendar.isDate(selected, inSameDayAs: date) { RoundedRectangle(cornerRadius: 4).stroke(ZoopStyle.text, lineWidth: 2) } }
                .frame(maxWidth: .infinity).frame(height: typeSize.isAccessibilitySize ? 44 : 32)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(value == nil || future)
            .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
            .accessibilityValue(value.map { TrendMetric.sleep.formatted($0) + " asleep" } ?? "No sleep recorded")
            .accessibilityHidden(future).accessibilityIdentifier("sleepHeatmapDay")
    }
}
