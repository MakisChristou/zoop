import SwiftUI

/// One walking bout: when, how long, how many steps. Cadence and the rest stay on
/// the session page so the list scans in one pass.
struct WalkRow: View {
    let bout: SnoopAPI.StepsDay.Bout
    let linked: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.walk")
                .font(.body.weight(.semibold))
                .foregroundStyle(.teal)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(bout.start.formatted(date: .omitted, time: .shortened)) – \(bout.end.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline.weight(.medium)).monospacedDigit()
                Text("\(bout.durationS / 60) min · \(bout.steps.formatted()) steps")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            if linked {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Walk from \(bout.start.formatted(date: .omitted, time: .shortened)) to \(bout.end.formatted(date: .omitted, time: .shortened)), \(bout.durationS / 60) minutes, \(bout.steps.formatted()) steps")
        .accessibilityHint(linked ? "Opens the session" : "")
    }
}
