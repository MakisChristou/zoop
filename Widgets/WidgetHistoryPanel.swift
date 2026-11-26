import SwiftUI
import WidgetKit

struct WidgetHistoryPanel: View {
    let entry: ZoopWidgetEntry
    let isActivity: Bool
    private let calendar = Calendar.current
    private let muted = Color(white: 0.63)
    private let loadColors = [0x202c37, 0x25445c, 0x315e85, 0x397caf, 0x418fce, 0x479eea]

    private var days: [Date] {
        isActivity ? WidgetHistory.heatmapDays(through: entry.date, calendar: calendar)
            : WidgetHistory.calendarDays(ending: entry.date, count: WidgetHistory.recoveryDays, calendar: calendar)
    }

    var body: some View {
        let dates = days
        let history = entry.data.activity
        let loads = history?.zone == calendar.timeZone.identifier ? history?.loads ?? [:] : [:]
        let recovery = Dictionary(entry.data.recovery.map { (calendar.startOfDay(for: $0.day), $0) },
                                  uniquingKeysWith: { _, last in last })
        let hasReadings = dates.contains { isActivity ? loads[$0] != nil : recovery[$0]?.score != nil }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(isActivity ? "Every day" : "Daily recovery").font(.subheadline.weight(.medium))
                Spacer()
                Text(isActivity ? "20 weeks" : "30 days").font(.caption2).foregroundStyle(muted)
            }
            if hasReadings {
                Canvas { context, size in
                    if isActivity {
                        drawHeatmap(context, size, dates, loads)
                    } else {
                        drawRecovery(context, size, dates, recovery)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityChildren {
                    ForEach(dates, id: \.self) { date in
                        if isActivity, let load = loads[date] {
                            Text("\(date.formatted(date: .abbreviated, time: .omitted)), load \(load.formatted())")
                        } else if !isActivity, let score = recovery[date]?.score {
                            Text("\(date.formatted(date: .abbreviated, time: .omitted)), recovery \(score) percent")
                        }
                    }
                }
            } else {
                Text(isActivity ? "No activity readings yet" : "No recovery scores yet")
                    .font(.subheadline).foregroundStyle(muted).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(.primary).environment(\.colorScheme, .dark)
    }

    private func color(_ rgb: Int) -> Color {
        Color(red: Double(rgb >> 16) / 255, green: Double(rgb >> 8 & 255) / 255, blue: Double(rgb & 255) / 255)
    }

    private func label(_ text: String, _ x: CGFloat, _ y: CGFloat, in context: GraphicsContext, anchor: UnitPoint = .leading) {
        context.draw(Text(verbatim: text).font(.system(size: 10)).foregroundStyle(muted),
                     at: CGPoint(x: x, y: y), anchor: anchor)
    }

    private func drawHeatmap(_ context: GraphicsContext, _ size: CGSize, _ dates: [Date], _ loads: [Date: Double]) {
        let left: CGFloat = 27, top: CGFloat = 17
        let dx = (size.width - left) / CGFloat(WidgetHistory.weeks)
        let dy = (size.height - top) / 7
        let side = max(1, min(dx, dy) - 2)
        var previousLabel: CGFloat = -100
        for (i, date) in dates.enumerated() where date <= entry.date {
            let x = left + CGFloat(i / 7) * dx, y = top + CGFloat(i % 7) * dy
            if i == 0 || calendar.component(.day, from: date) == 1 {
                let labelX = min(x, size.width - 24)
                if labelX - previousLabel >= 25 {
                    label(date.formatted(.dateTime.month(.abbreviated)), labelX, 6, in: context)
                    previousLabel = labelX
                }
            }
            if [0, 2, 4].contains(i) {
                label(date.formatted(.dateTime.weekday(.narrow)), 0, y + side / 2, in: context)
            }
            let tile = Path(roundedRect: CGRect(x: x, y: y, width: side, height: side), cornerRadius: 2)
            if let load = loads[date] {
                context.fill(tile, with: .color(color(loadColors[WidgetHistory.loadLevel(load)])))
            } else {
                context.fill(tile, with: .color(Color(white: 0.125)))
                context.stroke(tile, with: .color(Color(white: 0.2)), lineWidth: 0.6)
            }
        }
    }

    private func drawRecovery(_ context: GraphicsContext, _ size: CGSize, _ dates: [Date], _ readings: [Date: WidgetSnapshot.Recovery]) {
        let left: CGFloat = 30, top: CGFloat = 5, bottom = size.height - 18
        let height = max(1, bottom - top), dx = (size.width - left) / CGFloat(dates.count)
        for tick in [0, 33, 67, 100] {
            let y = bottom - CGFloat(tick) / 100 * height
            var line = Path()
            line.move(to: CGPoint(x: left, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(line, with: .color(Color(white: 0.21)), style: StrokeStyle(lineWidth: 0.6, dash: [2, 3]))
            label("\(tick)%", left - 4, y, in: context, anchor: .trailing)
        }
        for (i, date) in dates.enumerated() {
            guard let reading = readings[date], let score = reading.score else { continue }
            let h = max(1, height * CGFloat(min(100, max(0, score))) / 100)
            let bar = CGRect(x: left + CGFloat(i) * dx + 1, y: bottom - h, width: max(1, dx - 2), height: h)
            let fill: Color
            switch reading.band {
            case "high": fill = color(0x47cf79)
            case "moderate": fill = color(0xfcc447)
            case "low": fill = color(0xf75c61)
            default: fill = muted
            }
            context.fill(Path(roundedRect: bar, cornerRadius: 1.5), with: .color(fill))
        }
        for i in [0, dates.count / 2, dates.count - 1] {
            let first = i == 0, last = i == dates.count - 1
            label(dates[i].formatted(.dateTime.month(.abbreviated).day()),
                  first ? left : last ? size.width : left + (CGFloat(i) + 0.5) * dx,
                  size.height - 5, in: context, anchor: first ? .leading : last ? .trailing : .center)
        }
    }
}
