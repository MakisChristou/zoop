import SwiftUI

/// A reading framed by a circle, with an optional measured progress arc.
struct TodaySummaryRing: View {
    let title: String
    let value: String
    let color: Color
    var progress: Double? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().strokeBorder(ZoopStyle.track, lineWidth: 6)
                Circle().inset(by: 3)
                    .trim(from: 0, to: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(value)
                    .font(ZoopType.font(size: 20, weight: .medium, relativeTo: .title3))
                    .foregroundStyle(ZoopStyle.text).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.65)
                    .padding(.horizontal, 12)
            }
            .aspectRatio(1, contentMode: .fit)
            Text(title).font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary)
        }
        .frame(maxWidth: typeSize.isAccessibilitySize ? 220 : .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value == "—" ? "No reading" : value)
    }

    private var fraction: Double {
        guard let progress else { return 1 }
        return progress.isFinite ? min(max(progress, 0), 1) : 0
    }
}
