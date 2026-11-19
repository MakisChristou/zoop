import SwiftUI

struct MetricInformation: View {
    let title: String
    let text: String

    var body: some View {
        DisclosureGroup(title) {
            Text(text).font(ZoopType.footnote).foregroundStyle(ZoopStyle.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
        }
        .font(ZoopType.subheadline).tint(ZoopStyle.secondary).padding(.vertical, 12)
    }
}
