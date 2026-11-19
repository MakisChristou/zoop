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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                Text(title).font(.subheadline).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("dayNavigationTitle")
                HStack {
                    Button(action: previous) {
                        Image(systemName: "chevron.left").font(.system(size: 22, weight: .medium))
                            .frame(minWidth: 44, minHeight: 44)
                    }.disabled(!canGoBack).accessibilityLabel(previousLabel)
                    Spacer(minLength: 8)
                    if let reset {
                        Button("Today", action: reset).font(.footnote.weight(.medium))
                            .frame(minWidth: 44, minHeight: 44)
                            .opacity(canReset ? 1 : 0).disabled(!canReset)
                            .accessibilityLabel("Back to today").accessibilityHidden(!canReset)
                    }
                    Spacer(minLength: 8)
                    Button(action: next) {
                        Image(systemName: "chevron.right").font(.system(size: 22, weight: .medium))
                            .frame(minWidth: 44, minHeight: 44)
                    }.disabled(!canGoForward).accessibilityLabel(nextLabel)
                }
            }
        } else { standard }
    }

    private var standard: some View {
        HStack {
            Button(action: previous) {
                Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44)
            }
            .foregroundStyle(canGoBack ? ZoopStyle.text : ZoopStyle.secondary.opacity(0.35))
            .disabled(!canGoBack).accessibilityLabel(previousLabel)
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                if reset != nil {
                    Text("Today").font(.footnote.weight(.medium)).frame(minWidth: 44, minHeight: 44)
                        .hidden().accessibilityHidden(true)
                }
                Text(title).font(.subheadline).multilineTextAlignment(.center).accessibilityIdentifier("dayNavigationTitle")
                if let reset {
                    Button("Today", action: reset)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(ZoopStyle.load)
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
            .foregroundStyle(canGoForward ? ZoopStyle.text : ZoopStyle.secondary.opacity(0.35))
            .disabled(!canGoForward).accessibilityLabel(nextLabel)
        }
    }
}
