import SwiftUI

/// A reading framed by a circle, with an optional measured progress arc.
struct TodaySummaryRing: View {
    let title: String
    let value: String
    let color: Color
    var progress: Double? = nil
    var isLoading = false
    var subtitle: String? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().strokeBorder(ZoopStyle.track, lineWidth: 6)
                if progress != nil {
                    Circle().inset(by: 3)
                        .trim(from: 0, to: fraction)
                        .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                if isLoading && value == "—" {
                    ProgressView().tint(ZoopStyle.text)
                } else {
                    VStack(spacing: 3) {
                        Text(value)
                            .font(ZoopType.font(size: 20, weight: .medium, relativeTo: .title3))
                            .foregroundStyle(ZoopStyle.text).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.65)
                        if let subtitle {
                            Text(subtitle).font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                                .lineLimit(1).minimumScaleFactor(0.65)
                        }
                    }.padding(.horizontal, 10)
                    if isLoading {
                        ProgressView().controlSize(.mini).tint(ZoopStyle.text)
                            .offset(y: 26)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            Text(title).font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary)
        }
        .frame(maxWidth: typeSize.isAccessibilitySize ? 220 : .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isLoading ? (value == "—" ? "Loading" : "\(value), updating") : value == "—" ? "No reading" : [value, subtitle].compactMap { $0 }.joined(separator: ", "))
    }

    private var fraction: Double {
        guard let progress else { return 0 }
        return progress.isFinite ? min(max(progress, 0), 1) : 0
    }
}
