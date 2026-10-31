import SwiftUI

/// Load on its 0–21 scale as an arc that warms from yellow to red as it fills. The
/// number next to it carries the value; the ring only gives it a size at a glance.
struct LoadRing: View {
    let load: Double
    var lineWidth: CGFloat = 6

    static let maximum = 21.0

    private var fraction: Double { min(max(load / Self.maximum, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary.opacity(0.6), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(colors: [.yellow, .orange, .red, .red], center: .center, startAngle: .degrees(0), endAngle: .degrees(360)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.35), value: fraction)
        }
        .accessibilityLabel("Load \(load.formatted(.number.precision(.fractionLength(1)))) of 21")
    }
}
