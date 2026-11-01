import SwiftUI

/// A past day's steps, pushed from a comparison bar. Going back lands on the same
/// range the day was picked from.
struct DayStepsView: View {
    let day: Date
    let summary: SnoopAPI.Day?
    let summariesLoaded: Bool

    var body: some View {
        ScrollView {
            DaySteps(day: day, summary: summary, summariesLoaded: summariesLoaded)
                .padding(.horizontal, SnoopStyle.gutter).padding(.vertical, 16)
        }
        .snoopScreen()
        .navigationTitle("Steps")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}
