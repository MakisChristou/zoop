import SwiftUI

/// A compact view of the server's stage intervals. Missing intervals remain gaps.
struct Hypnogram: View {
    let segments: [ZoopAPI.Night.Segment]
    let onset: Date
    let offset: Date
    var timezone: TimeZone = .current
    var selection: Binding<Date?>? = nil
    @ScaledMetric(relativeTo: .caption2) private var rowHeight: CGFloat = 28
    private let stages: [ZoopAPI.Night.Stage] = [.wake, .rem, .light, .deep]

    static func color(_ stage: ZoopAPI.Night.Stage) -> Color {
        switch stage {
        case .wake: ZoopStyle.secondary.opacity(0.25)
        case .light: ZoopStyle.sleep.opacity(0.25)
        case .deep: ZoopStyle.sleep
        case .rem: ZoopStyle.sleep.opacity(0.6)
        }
    }
    private func name(_ stage: ZoopAPI.Night.Stage) -> String {
        switch stage { case .wake: "Awake"; case .rem: "REM"; case .light: "Light"; case .deep: "Deep" }
    }
    private var ticks: [Date] { SleepChartTime.ticks(from: onset, to: offset, timezone: timezone) }
    private func time(_ date: Date) -> String { SleepChartTime.label(date, timezone: timezone) }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(stages, id: \.rawValue) { stage in
                    Text(name(stage)).font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary)
                        .frame(height: rowHeight)
                }
            }.fixedSize(horizontal: true, vertical: false)
            VStack(spacing: 8) {
                GeometryReader { geometry in
                    let total = max(offset.timeIntervalSince(onset), 1)
                    ZStack(alignment: .topLeading) {
                        Path { path in
                            for row in 0..<4 {
                                let y = rowHeight * (CGFloat(row) + 0.5)
                                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                            }
                        }.stroke(ZoopStyle.chartGrid, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                            let start = max(segment.start, onset), end = min(segment.end, offset)
                            if end > start, let row = stages.firstIndex(of: segment.stage) {
                                let x = CGFloat(start.timeIntervalSince(onset) / total) * geometry.size.width
                                let width = CGFloat(end.timeIntervalSince(start) / total) * geometry.size.width
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(segment.stage == .wake ? ZoopStyle.secondary.opacity(0.45) : Self.color(segment.stage)).frame(width: max(width, 1), height: 8)
                                    .background(ZoopStyle.surface, in: RoundedRectangle(cornerRadius: 3))
                                    .offset(x: x, y: rowHeight * (CGFloat(row) + 0.5) - 4)
                            }
                        }
                        if let date = selection?.wrappedValue {
                            Rectangle().fill(ZoopStyle.secondary.opacity(0.5)).frame(width: 1)
                                .offset(x: CGFloat(date.timeIntervalSince(onset) / total) * geometry.size.width)
                        }
                    }.clipped()
                    .overlay {
                        if let selection {
                            CalendarChartGesture(select: { point in
                                let fraction = min(max(point.x / max(geometry.size.width, 1), 0), 1)
                                selection.wrappedValue = onset.addingTimeInterval(total * fraction)
                            }, page: { _ in }, endInspection: { selection.wrappedValue = nil }, allowsPaging: false)
                                .accessibilityHidden(true)
                        }
                    }
                }.frame(height: rowHeight * 4)
                GeometryReader { geometry in
                    let total = max(offset.timeIntervalSince(onset), 1)
                    ForEach(ticks, id: \.self) { tick in
                        Text(time(tick)).font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary)
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .fixedSize().position(x: max(20, min(geometry.size.width - 20, CGFloat(tick.timeIntervalSince(onset) / total) * geometry.size.width)), y: 8)
                    }
                }.frame(height: 20)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep stages from \(time(onset)) to \(time(offset))")
    }
}
