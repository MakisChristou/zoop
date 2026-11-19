import SwiftUI

struct BodyProfileView: View {
    var body: some View {
        Form { BodyProfileSection().listRowBackground(ZoopStyle.surface) }
            .scrollContentBackground(.hidden)
            .zoopScreen()
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
    }
}
