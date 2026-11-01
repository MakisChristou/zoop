import SwiftUI

/// The same day-by-day controls on Today and Sleep.
struct DateNavigation: View {
    let title: String
    let canGoBack: Bool
    let canGoForward: Bool
    let previousLabel: String
    let nextLabel: String
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        HStack {
            Button(action: previous) {
                Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44)
            }
            .foregroundStyle(canGoBack ? SnoopStyle.text : SnoopStyle.secondary.opacity(0.35))
            .disabled(!canGoBack).accessibilityLabel(previousLabel)
            Spacer(minLength: 4)
            Text(title).font(.subheadline).multilineTextAlignment(.center)
            Spacer(minLength: 4)
            Button(action: next) {
                Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
            }
            .foregroundStyle(canGoForward ? SnoopStyle.text : SnoopStyle.secondary.opacity(0.35))
            .disabled(!canGoForward).accessibilityLabel(nextLabel)
        }
    }
}
