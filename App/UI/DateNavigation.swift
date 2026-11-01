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
    var reset: (() -> Void)? = nil
    var canReset = false

    var body: some View {
        HStack {
            Button(action: previous) {
                Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44)
            }
            .foregroundStyle(canGoBack ? SnoopStyle.text : SnoopStyle.secondary.opacity(0.35))
            .disabled(!canGoBack).accessibilityLabel(previousLabel)
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                Text(title).font(.subheadline).multilineTextAlignment(.center)
                if let reset {
                    Button("Today", action: reset)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(SnoopStyle.load)
                        .frame(minWidth: 44, minHeight: 44)
                        .opacity(canReset ? 1 : 0)
                        .disabled(!canReset)
                        .accessibilityLabel("Back to today")
                        .accessibilityHidden(!canReset)
                }
            }
            Spacer(minLength: 4)
            Button(action: next) {
                Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
            }
            .foregroundStyle(canGoForward ? SnoopStyle.text : SnoopStyle.secondary.opacity(0.35))
            .disabled(!canGoForward).accessibilityLabel(nextLabel)
        }
    }
}
