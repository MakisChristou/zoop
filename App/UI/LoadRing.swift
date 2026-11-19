import SwiftUI

/// Load on its 0–21 scale as a blue arc, the one colour load has everywhere. The
/// number next to it carries the value; the ring only gives it a size at a glance.
struct LoadRing: View {
    let load: Double
    var lineWidth: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let maximum = 21.0

    private var fraction: Double { min(max(load / Self.maximum, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(ZoopStyle.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(ZoopStyle.load, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: fraction)
        }
        .accessibilityLabel("Load \(load.formatted(.number.precision(.fractionLength(1)))) of 21")
    }
}
