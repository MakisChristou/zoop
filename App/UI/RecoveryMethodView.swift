import SwiftUI

struct RecoveryMethodView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("A Zoop index from 0 to 100, using nightly HRV, resting heart rate and sleep. It is not a percentage of recovery.")
                    Text("Heart readings are compared with your previous 28 days. Sleep uses an 8-hour reference and includes recent nights. The lowest component sets the score.")
                    Text("At least 14 usable prior nights and 5 recent nights are needed. Incomplete or unusual readings leave the score blank.")
                }.font(ZoopType.subheadline).padding(ZoopStyle.gutter)
            }.zoopScreen()
            .navigationTitle("About recovery").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
