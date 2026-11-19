import SwiftUI

/// Each row draws its own rail so it also follows wrapped accessibility text.
struct WorkoutTimelineRail: View {
    var startsHere = false
    var endsHere = false
    @Environment(\.layoutDirection) private var layoutDirection
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let x = layoutDirection == .rightToLeft ? geometry.size.width - 18 : 18
                path.move(to: .init(x: x, y: startsHere ? geometry.size.height / 2 : 0))
                path.addLine(to: .init(x: x, y: endsHere ? geometry.size.height / 2 : geometry.size.height))
            }.stroke(ZoopStyle.separator, lineWidth: 1)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
