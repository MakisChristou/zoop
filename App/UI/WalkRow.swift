import SwiftUI

struct WalkRow: View {
    let bout: ZoopAPI.StepsDay.Bout
    let linked: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(bout.start.formatted(date: .omitted, time: .shortened)) – \(bout.end.formatted(date: .omitted, time: .shortened))")
                    .font(ZoopType.font(size: 14, weight: .medium, relativeTo: .subheadline)).monospacedDigit()
                Text("\(bout.durationS / 60) min").font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(bout.steps.formatted()).font(ZoopType.font(size: 14, weight: .semibold, relativeTo: .subheadline)).monospacedDigit()
                Text("steps").font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                if linked { Image(systemName: "chevron.right").font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary) }
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .top) { Rectangle().fill(ZoopStyle.separator).frame(height: 0.5) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Walk from \(bout.start.formatted(date: .omitted, time: .shortened)) to \(bout.end.formatted(date: .omitted, time: .shortened)), \(bout.durationS / 60) minutes, \(bout.steps.formatted()) steps")
        .accessibilityHint(linked ? "Opens the session" : "")
    }
}
