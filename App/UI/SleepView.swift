import SwiftUI

/// Sleep analysis runs on the server and needs full nights of data. Until the first
/// analysed night exists this screen says so instead of showing invented numbers.
struct SleepView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("No nights yet", systemImage: "moon.zzz")
            } description: {
                Text(description)
            }
            .navigationTitle("Sleep")
        }
    }

    private var description: String {
        if !Settings.isConfigured {
            return "Add your server in Settings. Sleep is analysed there from the strap's overnight data."
        }
        if let b = model.strap.lastBiometric, b.bandState == .sleep {
            return "The strap currently reports sleep. Tonight's data will be analysed after you wake and the app syncs."
        }
        return "Wear the strap overnight with snoop running in the background. The first analysed night appears here the next morning."
    }
}
