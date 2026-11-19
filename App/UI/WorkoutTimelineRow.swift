import SwiftUI

/// The Activity timeline uses compact rows; Today retains its existing workout cards.
struct WorkoutTimelineRow: View {
    let workout: ZoopAPI.Workout
    let isLast: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    private var kind: ActivityKind { .named(workout.kind) }
    private var duration: String {
        let minutes = workout.durationS / 60
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind == .resistance ? "dumbbell" : kind == .walk ? "figure.walk" : "bolt.heart")
                .font(.system(size: 16, weight: .regular))
                .rotationEffect(.degrees(kind == .resistance ? -35 : 0))
                .foregroundStyle(ZoopStyle.text)
                .frame(width: 36, height: 36)
                .background(ZoopStyle.surface, in: Circle())
                .overlay { Circle().stroke(ZoopStyle.separator, lineWidth: 1) }
                .accessibilityHidden(true)
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.name).font(ZoopType.subheadline).foregroundStyle(ZoopStyle.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(duration).font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary).monospacedDigit()
                }.frame(maxWidth: .infinity, alignment: .leading)
                load
            }
        }
        .padding(.vertical, 7).frame(minHeight: 48)
        .background { WorkoutTimelineRail(endsHere: isLast) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.name), \(workout.durationS / 60) minutes, \(workout.startTs.formatted(date: .abbreviated, time: .shortened))")
        .accessibilityValue(workout.load.map { "Load \($0.formatted(.number.precision(.fractionLength(1)))) of 21" } ?? "Load unavailable")
        .accessibilityHint("View workout details")
    }

    private var load: some View {
        HStack(spacing: 12) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(ZoopStyle.track)
                    if let value = workout.load, value.isFinite {
                        Capsule().fill(ZoopStyle.load)
                            .frame(width: geometry.size.width * min(max(value / LoadRing.maximum, 0), 1))
                    }
                }
            }.frame(width: 44, height: 5).accessibilityHidden(true)
            Text(workout.load.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—")
                .font(ZoopType.font(size: 14, weight: .medium, relativeTo: .subheadline))
                .foregroundStyle(ZoopStyle.text).monospacedDigit()
                .frame(minWidth: 32, alignment: .trailing)
        }
    }
}

