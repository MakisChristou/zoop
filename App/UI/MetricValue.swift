import SwiftUI

/// The value retains its prominence at large text sizes; the unit can wrap below it.
struct MetricValue: View {
    let value: String
    var unit = ""
    @ScaledMetric(relativeTo: .largeTitle) private var pointSize: CGFloat = 20

    init(_ value: String, unit: String = "", size: CGFloat = 20) {
        self.value = value
        self.unit = unit
        _pointSize = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 5) { number; units }
            VStack(alignment: .leading, spacing: 2) { number; units }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(unit)")
    }

    private var number: some View {
        Text(value).font(ZoopType.fixed(size: pointSize, weight: .medium))
            .monospacedDigit().fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var units: some View {
        if !unit.isEmpty { Text(unit).font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary) }
    }
}
