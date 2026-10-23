import SwiftUI

struct TrendsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Trends need history", systemImage: "chart.line.uptrend.xyaxis")
            } description: {
                Text("Resting heart rate, HRV and sleep trends appear once the server has a few days of data.")
            }
            .navigationTitle("Trends")
        }
    }
}
