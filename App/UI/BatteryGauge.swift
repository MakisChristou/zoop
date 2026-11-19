import SwiftUI

/// The direction and labels remain visible when motion is disabled.
struct BatteryGauge: View {
    enum Flow { case none, receiving, supplying }
    let percent: Double?
    let flow: Flow
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: flow == .none || reduceMotion || scenePhase != .active)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3) / 3
            ZStack {
                Circle().stroke(.primary.opacity(0.09), lineWidth: 9)
                if let percent {
                    Circle().trim(from: 0, to: min(max(percent / 100, 0), 1))
                        .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: percent)
                } else {
                    Circle().stroke(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [3, 6]))
                }
                if flow != .none {
                    Circle().trim(from: 0, to: 0.15)
                        .stroke(BatteryColors.flow, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(reduceMotion ? -90 : phase * (flow == .receiving ? 360 : -360) - 90))
                        .padding(-7)
                }
                VStack(spacing: 4) {
                    Image(systemName: flow == .receiving ? "bolt.fill" : flow == .supplying ? "arrow.up.right" : "battery.100percent")
                        .font(.system(size: 18, weight: .semibold)).foregroundStyle(flow == .none ? color : BatteryColors.flow)
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(percent.map { String(Int($0.rounded(.down))) } ?? "—")
                            .font(.system(size: 36, weight: .semibold, design: .default))
                            .monospacedDigit().contentTransition(.numericText())
                        if percent != nil { Text("%").font(.system(size: 14)).foregroundStyle(ZoopStyle.secondary) }
                    }
                    .minimumScaleFactor(0.7).lineLimit(1)
                }
                .padding(14)
            }
            .padding(12)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
