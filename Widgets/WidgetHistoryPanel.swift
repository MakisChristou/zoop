import SwiftUI
import WidgetKit

struct WidgetHistoryPanel: View {
    let entry: ZoopWidgetEntry
    private let calendar = Calendar.current
    private let muted = Color(white: 0.63)
    private let loadColors = [0x202c37, 0x25445c, 0x315e85, 0x397caf, 0x418fce, 0x479eea]

    private var days: [Date] {
        WidgetHistory.heatmapDays(through: entry.date, calendar: calendar)
    }

    var body: some View {
        let dates = days
        let history = entry.data.activity
        let loads = history?.zone == calendar.timeZone.identifier ? history?.loads ?? [:] : [:]
        let hasReadings = dates.contains { loads[$0] != nil }
        Group {
            if hasReadings {
                Canvas { context, size in
                    drawHeatmap(context, size, dates, loads)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Every day, 20 weeks")
                .accessibilityChildren {
                    ForEach(dates, id: \.self) { date in
                        if let load = loads[date] {
                            Text("\(date.formatted(date: .abbreviated, time: .omitted)), load \(load.formatted())")
                        }
                    }
                }
            } else {
                Text("No activity readings yet")
                    .font(.subheadline).foregroundStyle(muted).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(.primary).environment(\.colorScheme, .dark)
    }

    private func color(_ rgb: Int) -> Color {
        Color(red: Double(rgb >> 16) / 255, green: Double(rgb >> 8 & 255) / 255, blue: Double(rgb & 255) / 255)
    }

    private func drawHeatmap(_ context: GraphicsContext, _ size: CGSize, _ dates: [Date], _ loads: [Date: Double]) {
        let columns = CGFloat(WidgetHistory.weeks)
        let gap: CGFloat = 2
        let pitch = min((size.width + gap) / columns, (size.height + gap) / 7)
        let side = max(0, pitch - gap)
        let left = (size.width - (columns * pitch - gap)) / 2
        let top = (size.height - (7 * pitch - gap)) / 2
        for (i, date) in dates.enumerated() where date <= entry.date {
            let x = left + CGFloat(i / 7) * pitch, y = top + CGFloat(i % 7) * pitch
            let tile = Path(roundedRect: CGRect(x: x, y: y, width: side, height: side), cornerRadius: 2.5)
            if let load = loads[date] {
                context.fill(tile, with: .color(color(loadColors[WidgetHistory.loadLevel(load)])))
            } else {
                context.fill(tile, with: .color(Color(white: 0.125)))
                context.stroke(tile, with: .color(Color(white: 0.2)), lineWidth: 0.6)
            }
        }
    }
}
