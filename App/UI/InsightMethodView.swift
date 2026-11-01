import SwiftUI

struct InsightMethodView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Personal comparisons") {
                    Text("Each night is compared with usable main sleeps from the preceding 28 days. The night being assessed is excluded. Seven readings allow an early comparison; fourteen allow a usual range.")
                    Text("The usual range is one standard deviation around your average. Small minimum widths prevent tiny changes from looking unusual. These are descriptive comparisons, not a recovery score or medical thresholds.")
                    Text("HRV comparisons use logarithms, then convert back to milliseconds. That makes the displayed average a geometric average.")
                }
                Section("Recording quality") {
                    Text("Gaps over two minutes exclude sleep duration from comparisons. Heart measurements need at least 90% recording coverage; HRV also needs six usable five-minute windows and at least half the expected windows. Each measurement is checked separately.")
                    Text("Automatic sleep needs recorded data around both its start and its end. A confirmed time edit can establish its end. Incomplete uploads and ongoing analysis show a waiting state.")
                }
                Section("Sleep timing") {
                    Text("Timing variation is the standard deviation of falling-asleep and waking times over at least five nights. Times wrap across midnight. Weeks spanning different saved time zones are left unscored.")
                }
                Section("Methods") {
                    Link("Plews et al. · Repeated HRV measurements", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/24334285/")!)
                    Link("Fischer et al. · Measuring sleep regularity", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/33864369/")!)
                }
            }
            .scrollContentBackground(.hidden).snoopScreen()
            .navigationTitle("About insights").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(SnoopStyle.load)
    }
}
