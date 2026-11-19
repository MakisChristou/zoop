import SwiftUI

struct SleepDuration: View {
    let seconds: Int?
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 34

    init(seconds: Int?, size: CGFloat = 34) {
        self.seconds = seconds
        _size = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
    }

    var body: some View {
        Group {
            if let seconds {
                (Text("\(seconds / 3600)").font(ZoopType.fixed(size: size, weight: .semibold))
                 + Text("h ").font(ZoopType.headline)
                 + Text("\((seconds % 3600) / 60)").font(ZoopType.fixed(size: size, weight: .semibold))
                 + Text("m").font(ZoopType.headline))
            } else {
                Text("—").font(ZoopType.fixed(size: size, weight: .semibold))
            }
        }
        .monospacedDigit()
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(seconds.map { "\($0 / 3600) hours, \(($0 % 3600) / 60) minutes" } ?? "No sleep data")
    }
}
