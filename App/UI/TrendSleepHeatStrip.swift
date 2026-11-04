import SwiftUI

/// Range and metric changes leave this unchanged eight-week view alone.
struct TrendSleepHeatStrip: View, Equatable {
    let byDay: [Date: Double]
    let nightCount: Int
    let today: Date
    let calendar: Calendar

    /// Eight weeks of sleep duration, one cell per night, Monday-first columns.
    var body: some View {
        let cal = calendar
        let weeks = 8
        let startOfThisWeek = cal.dateInterval(of: .weekOfYear, for: today)!.start
        let gridStart = cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: startOfThisWeek)!
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday
        let labels = (0..<7).map { symbols[($0 + first - 1) % 7] }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sleep, last \(weeks) weeks").font(.caption.weight(.semibold)).foregroundStyle(SnoopStyle.secondary)
                Spacer()
                HStack(spacing: 3) {
                    Text("<5h").font(.caption2).foregroundStyle(SnoopStyle.secondary)
                    ForEach(0..<5) { i in RoundedRectangle(cornerRadius: 2).fill(SnoopStyle.sleep.opacity(0.15 + Double(i) * 0.2)).frame(width: 10, height: 10) }
                    Text("8h+").font(.caption2).foregroundStyle(SnoopStyle.secondary)
                }
            }
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { col in
                    VStack(spacing: 4) {
                        Text(labels[col]).font(.caption2).foregroundStyle(SnoopStyle.secondary).accessibilityHidden(true)
                        ForEach(0..<weeks, id: \.self) { row in
                            let date = cal.date(byAdding: .day, value: row * 7 + col, to: gridStart)!
                            let hours = byDay[date]
                            RoundedRectangle(cornerRadius: 3)
                                .fill(cell(hours, future: date > today))
                                .frame(height: 14)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                                .accessibilityValue(hours.map { duration($0) } ?? "No sleep recorded")
                                .accessibilityHidden(date > today)
                                .accessibilitySortPriority(Double(weeks * 7 - row * 7 - col))
                                .accessibilityIdentifier("sleepHeatmapDay")
                        }
                    }
                }
            }
            if nightCount < 7 {
                Text("Fills in night by night. \(nightCount) so far.").font(.caption2).foregroundStyle(SnoopStyle.secondary)
            }
        }
        .padding()
        .background(SnoopStyle.surface, in: RoundedRectangle(cornerRadius: SnoopStyle.radius))
    }

    private func cell(_ hours: Double?, future: Bool) -> Color {
        if future { return .clear }
        guard let hours else { return Color.secondary.opacity(0.08) }
        let t = min(max((hours - 4) / 4.5, 0), 1)
        return SnoopStyle.sleep.opacity(0.15 + t * 0.8)
    }

    private func duration(_ hours: Double) -> String {
        let minutes = Int((hours * 60).rounded())
        return "\(minutes / 60) hours, \(minutes % 60) minutes asleep"
    }

}
