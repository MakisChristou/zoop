import SwiftUI

struct MetricInformation: View {
    let title: String
    let text: String

    var body: some View {
        DisclosureGroup(title) {
            Text(text).font(.footnote).foregroundStyle(SnoopStyle.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
        }
        .font(.subheadline).tint(SnoopStyle.secondary).padding(.vertical, 12)
    }
}
