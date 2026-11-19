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
                Text("Sleep, last 8 weeks").font(ZoopType.font(size: 14, weight: .medium, relativeTo: .subheadline))
                if !typeSize.isAccessibilitySize { Spacer() }
                Text("<5h – 8h+").font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary)
            }
            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 4) {
                    Color.clear.frame(height: 16)
                    ForEach(0..<7, id: \.self) { day in
                        Text(day % 2 == 0 ? calendar.veryShortStandaloneWeekdaySymbols[(day + calendar.firstWeekday - 1) % 7] : "")
                            .font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary).frame(height: 28)
                    }
                }.frame(width: 12).accessibilityHidden(true)
                HStack(alignment: .top, spacing: 4) {
                    ForEach(0..<weeks, id: \.self) { week in
                        let date = calendar.date(byAdding: .day, value: week * 7, to: start)!
                        VStack(spacing: 4) {
                            Text(week == 0 || calendar.component(.month, from: date) != calendar.component(.month, from: calendar.date(byAdding: .day, value: -7, to: date)!) ? date.formatted(.dateTime.month(.abbreviated)) : "")
                                .font(ZoopType.fixed(size: 11)).foregroundStyle(ZoopStyle.secondary).frame(height: 16).accessibilityHidden(true)
                            ForEach(0..<7, id: \.self) { day in
                                cell(calendar.date(byAdding: .day, value: week * 7 + day, to: start)!)
                            }
                        }.frame(maxWidth: .infinity)
                    }
                }
            }.dynamicTypeSize(...DynamicTypeSize.xxxLarge)

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
                .frame(maxWidth: .infinity).frame(height: 18).padding(5).frame(height: 28)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(value == nil || future)
            .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
            .accessibilityValue(value.map { TrendMetric.sleep.formatted($0) + " asleep" } ?? "No sleep recorded")
            .accessibilityHidden(future).accessibilityIdentifier("sleepHeatmapDay")
    }
}
