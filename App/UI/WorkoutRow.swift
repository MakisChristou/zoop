import SwiftUI

struct WorkoutRow: View {
    let workout: ZoopAPI.Workout
    @Environment(\.dynamicTypeSize) private var typeSize
    private var kind: ActivityKind { .named(workout.kind) }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            HStack(spacing: 12) {
                Image(systemName: kind.icon).font(ZoopType.font(size: 16, weight: .medium, relativeTo: .body))
                    .foregroundStyle(kind.color).frame(width: 38, height: 38)
                    .background(ZoopStyle.surface, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.name).font(ZoopType.font(size: 14, weight: .semibold, relativeTo: .subheadline))
                    Text("\(workout.startTs.formatted(date: .omitted, time: .shortened)) · \(workout.durationS / 60) min")
                        .font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary).monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(workout.load.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—")
                        .font(ZoopType.font(size: 14, weight: .medium, relativeTo: .subheadline)).monospacedDigit()
                    Text("Load").font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary)
                }
                Image(systemName: "chevron.right").font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary)
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(ZoopStyle.separator).frame(height: 0.5) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
