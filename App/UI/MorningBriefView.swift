import SwiftUI

/// A quiet entry point beneath the existing daily overview.
struct MorningBriefView: View {
    let insights: MorningInsights
    let day: Date
    var body: some View {
        NavigationLink { MorningInsightsView(day: day) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Morning brief", systemImage: "sun.horizon")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(SnoopStyle.load)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(SnoopStyle.secondary)
                }
                if insights.state == "ready" {
                    ForEach(insights.observations, id: \.self) { Text($0).font(.subheadline).fixedSize(horizontal: false, vertical: true) }
                    if let label = insights.learningLabel {
                        Text(label).font(.caption).foregroundStyle(SnoopStyle.secondary)
                    }
                } else {
                    Text(insights.status).font(.subheadline).foregroundStyle(SnoopStyle.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).snoopCard()
        }
        .buttonStyle(PressableCardStyle()).accessibilityIdentifier("openMorningInsights")
        .accessibilityElement(children: .combine).accessibilityHint("Opens the measurements and comparisons for this day")
    }
}
