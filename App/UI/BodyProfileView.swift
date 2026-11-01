import SwiftUI

struct BodyProfileView: View {
    var body: some View {
        Form { BodyProfileSection().listRowBackground(SnoopStyle.surface) }
            .scrollContentBackground(.hidden)
            .snoopScreen()
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
    }
}
