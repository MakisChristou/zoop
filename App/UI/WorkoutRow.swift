import SwiftUI

struct WorkoutRow: View {
    let workout: SnoopAPI.Workout
    @Environment(\.dynamicTypeSize) private var typeSize
    private var kind: ActivityKind { .named(workout.kind) }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            HStack(spacing: 12) {
                Image(systemName: kind.icon).font(.body.weight(.medium))
                    .foregroundStyle(kind.color).frame(width: 38, height: 38)
                    .background(SnoopStyle.surface, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.name).font(.subheadline.weight(.semibold))
                    Text("\(workout.startTs.formatted(date: .omitted, time: .shortened)) · \(workout.durationS / 60) min")
                        .font(.caption).foregroundStyle(SnoopStyle.secondary).monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(workout.load.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—")
                        .font(.title3.weight(.semibold)).monospacedDigit()
                    Text("Load").font(.caption2).foregroundStyle(SnoopStyle.secondary)
                }
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(SnoopStyle.secondary)
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(SnoopStyle.separator).frame(height: 0.5) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
