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
                let hours = Text("\(seconds / 3600)").font(ZoopType.fixed(size: size, weight: .semibold))
                let hourUnit = Text("h ").font(ZoopType.headline)
                let minutes = Text("\((seconds % 3600) / 60)").font(ZoopType.fixed(size: size, weight: .semibold))
                let minuteUnit = Text("m").font(ZoopType.headline)
                Text("\(hours)\(hourUnit)\(minutes)\(minuteUnit)")
            } else {
                Text("—").font(ZoopType.fixed(size: size, weight: .semibold))
            }
        }
        .monospacedDigit()
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(seconds.map { "\($0 / 3600) hours, \(($0 % 3600) / 60) minutes" } ?? "No sleep data")
    }
}
