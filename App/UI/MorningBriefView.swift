import SwiftUI

/// The primary morning summary, above the daily measurements.
struct MorningBriefView: View {
    let insights: MorningInsights
    let day: Date
    var body: some View {
        NavigationLink { MorningInsightsView(day: day) } label: {
            MorningOutlookView(insights: insights, showsDisclosure: true)
        }
        .buttonStyle(PressableCardStyle()).accessibilityIdentifier("openMorningInsights")
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the measurements and comparisons for this day")
    }
}
