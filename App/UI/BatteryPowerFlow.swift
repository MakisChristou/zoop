import SwiftUI

struct BatteryPowerFlow: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active || reduceMotion || scenePhase != .active)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.5) / 1.5
            ZStack {
                Capsule().fill(.secondary.opacity(0.25)).frame(height: 2)
                if active {
                    Image(systemName: "chevron.right")
                        .font(ZoopType.font(size: 12, weight: .bold, relativeTo: .caption)).foregroundStyle(BatteryColors.flow)
                        .offset(x: reduceMotion ? 0 : (phase - 0.5) * 20)
                        .opacity(reduceMotion ? 1 : 0.35 + 0.65 * sin(phase * .pi))
                }
            }
        }
        .frame(width: 24, height: 32)
        .accessibilityHidden(true)
    }
}
