import SwiftUI

struct WalkRow: View {
    let bout: SnoopAPI.StepsDay.Bout
    let linked: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(bout.start.formatted(date: .omitted, time: .shortened)) – \(bout.end.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline.weight(.medium)).monospacedDigit()
                Text("\(bout.durationS / 60) min").font(.caption).foregroundStyle(SnoopStyle.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(bout.steps.formatted()).font(.subheadline.weight(.semibold)).monospacedDigit()
                Text("steps").font(.caption).foregroundStyle(SnoopStyle.secondary)
                if linked { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(SnoopStyle.secondary) }
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .top) { Rectangle().fill(SnoopStyle.separator).frame(height: 0.5) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Walk from \(bout.start.formatted(date: .omitted, time: .shortened)) to \(bout.end.formatted(date: .omitted, time: .shortened)), \(bout.durationS / 60) minutes, \(bout.steps.formatted()) steps")
        .accessibilityHint(linked ? "Opens the session" : "")
    }
}
